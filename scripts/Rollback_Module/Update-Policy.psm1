function Update-Policy {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateSet("ADT", "Prod", "Dev")]
        [string]$Source,

        [Parameter(Mandatory)]
        [ValidateSet("ADT", "Prod", "Dev")]
        [string]$Destination,

        [Parameter(Mandatory)]
        [ValidateSet("Update Policy")]
        [string]$Action,

        [Parameter(Mandatory)]
        [string]$PolicyIDs,

        [Parameter(Mandatory)]
        [PSCustomObject]$ScopeTags,

        [Parameter(Mandatory)]
        [string]$WorkFlowID,

        [Parameter(Mandatory)]
        [string]$WorkFlowTaskID,

        [Parameter(Mandatory = $false)]
        [hashtable]$Configuration
    )

    # Path to your JSON config file
    $configPath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath "..\Modules\Common\config.json")

    if (-not (Test-Path $configPath)) {
        throw "Missing config file at loc $configPath"
    }
    $Config = Get-Content -Raw -Path $configPath | ConvertFrom-Json

    # Load modules
    . "$PSScriptRoot\Modules\Auth.ps1"
    . "$PSScriptRoot\Modules\Validate-Policy.ps1"
    . "$PSScriptRoot\Modules\Validate-Policy-Update.ps1"
    . "$PSScriptRoot\Modules\FetchPolicyFromGit.ps1"
    . "$PSScriptRoot\Modules\Update-Policy.ps1"

    # Convert input to array
    $policyIdArray = $PolicyIDs -split ',' | ForEach-Object { $_.Trim() }

    # Variables to handle success, errors
    $missingPolicies = @()
    $errorsList = @()
    $updatedPolicies = @()
    $comparePolicies = @()
    $failedUpdatedPolicies = @()
    $export_release_url = $null

    # Looping Policies
    foreach ($policyId in $policyIdArray) {
        # $existingPolicyinSource="False"
        # $existingPolicyGuidinSource="False"
        $policyRecord = Validate-Policy-Before-Update -PolicyId $policyId -Config $Config -Source $Source -Action "Update Policy"

        # Check policy in database using Validate-Policy.ps1 module
        # $policyRecord = Get-PolicyFromTable -PolicyId $policyRecord -Config $Config -WorkFlowID $WorkFlowID -Source $Source -Action "Update Policy" -Destination $Destination
        if (-not $policyRecord) {
            $missingPolicies += "`nPolicy ID does not exist or not exported in git: $($policyId)"
            $failedUpdatedPolicies += "$($policyId)"
            continue
        } else {

            $policyName = $($policyRecord.PolicyName)
            # $PolicyRowId = $($policyRecord.PolicyRowId)
            # $SourcePolicyID = $($policyRecord.PolicyId)
            $policyType = $policyRecord.PolicyType  # "Compliance Policy" or "Configuration Policy"
            $gitpath = $policyRecord.gitpath
            $PolicyVersion = $policyRecord.PolicyVersion

            if ([string]::IsNullOrWhiteSpace($gitpath)) {
                $errorsList += "`ngitpath is empty for Policy ID $($policyId). Cannot proceed with update."
                $failedUpdatedPolicies += "$($policyId)"
                continue
            }

            $JSONPath = ""
            if ($Source -eq "ADT") {
                if ($PolicyType -eq "Compliance Policy") {
                    $JSONPath = $Config.Source.ADT.compliancePolicyJSON
                }
                elseif ($PolicyType -eq "Configuration Policy") {
                    $JSONPath = $Config.Source.ADT.configurationPolicyJSON
                }
                else {
                    $errorsList += "`nUnknown PolicyType for Policy ID $($policyId) "
                }
            }elseif ($Source -eq "Prod"){
                if ($PolicyType -eq "Compliance Policy") {
                    $JSONPath = $Config.Source.Prod.compliancePolicyJSON
                }
                elseif ($PolicyType -eq "Configuration Policy") {
                    $JSONPath = $Config.Source.Prod.configurationPolicyJSON
                }
                else {
                    $errorsList += "`nUnknown PolicyType for Policy ID $($policyId) "
                }
            }

            $relativePath = "$JSONPath/$PolicyId.json"
            # GitHub details
            $repoOwner = $Config.Git.repoOwner
            $repoName = $Config.Git.repoName
            $branch = $Config.Git.branch
            $gitURL = $Config.Git.rawUrl
            $rawUrl = "$gitURL/raw/$repoOwner/$repoName/$branch/$relativePath"
            try {
                # $gitjsonresponse = Fetch-PolicyFromGit -PolicyType $policyType -Config $Config -Source $Source -Destination $Destination -PolicyId $policyId -ExportGitPath $rawUrl -gitpath $gitpath -ExistingPolicyinSource $existingPolicyinSource -ScopeTags $ScopeTags
                $gitjsonresponse = Fetch-PolicyFromGit -PolicyType $policyType -Config $Config -Source $Source -Destination $Destination -PolicyId $policyId -ExportGitPath $rawUrl -gitpath $gitpath -ScopeTags $ScopeTags

                if ($gitjsonresponse.Success) {

                    $policyJson = $gitjsonresponse.Response
                    $release_url = $gitjsonresponse.releaseURL
                    $AssignedScopeTags = $gitjsonresponse.roleScopeTags

                    # Authenticate using Auth.ps1 module
                    $token = Get-AccessToken -Environment $Destination -Config $Config

                    $ProdPolicyName = $null

                    # Define the additional description string
                    if (-not [string]::IsNullOrEmpty($export_release_url)) {
                        $additionalDescription = "$Source exported policy ID $SourcePolicyID - and release path - $release_url . XL Release ID - $WorkFlowID. To rollback use - $export_release_url .`n"
                    }else{
                        $additionalDescription = "$Source exported policy ID $SourcePolicyID - and release path - $release_url . XL Release ID - $WorkFlowID .`n"
                    }

                    # Maximum allowed length for description
                    $maxLength = 1000

                    # Ensure existing description is a string (not null)
                    if (-not $policyJson.description) {
                        $policyJson.description = ""
                    }

                    # Calculate available space for the original description after adding additional content and newline
                    # Subtract 1 for the newline character
                    $availableLength = $maxLength - $additionalDescription.Length - 1

                    if ($policyJson.description.Length -gt $availableLength) {
                        # Truncate existing description to fit within max length
                        $truncatedDescription = $policyJson.description.Substring(0, $availableLength)
                    } else {
                        $truncatedDescription = $policyJson.description
                    }

                    # Update the description with the additional text at the beginning
                    $policyJson.description = $additionalDescription + "`n" + $truncatedDescription

                    if ($ProdPolicyName -eq $null) {
                        $ProdPolicyName = "CaC-"+$policyName
                    }

                    $response = Update-PolicyToIntune -Action "Update Policy" -PolicyJson $policyJson -PolicyType $policyType -Token $token -Config $Config -PolicyId $policyId -WorkFlowID $WorkFlowID -Destination $Destination -ExportGitPath $rawUrl -WorkFlowTaskID $WorkFlowTaskID -ScopeTags $ScopeTags -PolicyName $ProdPolicyName -Source $Source -policyVersion $PolicyVersion
                    # $response = Update-PolicyToIntune -Action "Update Policy" -PolicyJson $policyJson -PolicyType $policyType -Token $token -Config $Config -PolicyRowId $PolicyRowId -policyVersion $policyVersion -PolicyId $policyId -WorkFlowID $WorkFlowID -Destination $Destination -ExportGitPath $rawUrl -WorkFlowTaskID $WorkFlowTaskID -ScopeTags $ScopeTags -PolicyName $ProdPolicyName -Source $Source -ExistingPolicyGuidinSource $existingPolicyGuidinSource

                    if ($response.Success) {
                        $updatedPolicies += "`n`n $($response.Response.policytype) - $($response.Response.policyname) updated successfully with ID: $($response.Response.id)"
                        $comparePolicies+= "`n $($response.Response.uri)/$($response.Response.id) - $rawUrl"
                    } else {
                        $errorsList += "`nUpdate failed for Policy ID $($policyId) : $($response.ErrorMessage)"
                        $failedUpdatedPolicies += "$($policyId)"
                        continue
                    }
                } else {
                    $errorsList += "`nFailed to fetch policy from Git for Policy ID $($policyId): $($gitjsonresponse.ErrorMessage)"
                    $failedUpdatedPolicies += "$($policyId)"
                }

            }
            catch {
                $errorsList += "`nFailed to fetch or parse JSON for Policy ID $($policyId): $($_.Exception.Message)"
                $failedUpdatedPolicies += "$($policyId)"
                continue
            }

        }
    }

    if ($missingPolicies.Count -gt 0) {
        Write-Host "`nMissing Policy IDs:" -ForegroundColor Yellow
        $missingPolicies | ForEach-Object { Write-Host "- $_" }
    }

    if ($errorsList.Count -gt 0) {
        Write-Host "`n=====================" -ForegroundColor Yellow
        Write-Host " Failed to update policies:" -ForegroundColor Yellow
        Write-Host "=====================" -ForegroundColor Yellow

        foreach ($failure in $errorsList) {
            # Extract the Policy ID if possible
            if ($failure -match "Policy ID\s+([a-zA-Z0-9\-]+)") {
                $policyId = $matches[1]
                Write-Host "`nPolicy ID: $policyId" -ForegroundColor Cyan
            } else {
                Write-Host "`nPolicy: (Unknown ID)" -ForegroundColor Cyan
            }

            # If the failure contains JSON, try to parse it
            if ($failure -match '{.*}') {
                try {
                    $jsonPart = $failure -replace '.*?({.*})','$1'
                    $parsed = $jsonPart | ConvertFrom-Json -ErrorAction Stop

                    Write-Host "Error Code: $($parsed.error.code)" -ForegroundColor Red
                    Write-Host "Message: $($parsed.error.message)" -ForegroundColor Red

                    if ($parsed.error.innerError) {
                        Write-Host "Inner Error: $($parsed.error.innerError.message)" -ForegroundColor DarkRed
                        Write-Host "Date: $($parsed.error.innerError.date)" -ForegroundColor DarkGray
                    }
                } catch {
                    Write-Host "Raw Error: $failure" -ForegroundColor Magenta
                }
            } else {
                # Just print the raw failure message
                Write-Host "Details: $failure" -ForegroundColor Yellow
            }

            Write-Host "------------------------" -ForegroundColor DarkGray
        }
    }
    if ($updatedPolicies.Count -gt 0) {
        Write-Host "`nUpdated Policies:" -ForegroundColor Green
        $updatedPolicies | ForEach-Object { Write-Host $_ }
    }
    if ($failedUpdatedPolicies.Count -gt 0) {
        Write-Host "`nFailed to update Policy:" -ForegroundColor Yellow
        $failedUpdatedPolicies | ForEach-Object { Write-Host $_ }
    }

    if ($comparePolicies.Count -gt 0) {
        Write-Host "`nCompare Policies:" -ForegroundColor Green
        $comparePolicies | ForEach-Object { Write-Host $_ }
    }

    # Return a summary object or string
    return @{
        MissingPolicies = $missingPolicies
        ErrorsList = $errorsList
        UpdatedPolicies = $updatedPolicies
        FailedUpdatedPolicies = $failedUpdatedPolicies
        ComparePolicies = $comparePolicies
    }
}