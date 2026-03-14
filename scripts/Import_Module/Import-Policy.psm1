function Import-Policy {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateSet("ADT", "Prod", "Dev")]
        [string]$Source,

        [Parameter(Mandatory)]
        [ValidateSet("ADT", "Prod", "Dev")]
        [string]$Destination,

        [Parameter(Mandatory)]
        [string]$PolicyIDs,

        [Parameter(Mandatory)]
        [PSCustomObject]$ScopeTags,

        [Parameter(Mandatory)]
        [ValidateSet("Create New Policy","Update Policy")]
        [string]$Action,

        [Parameter(Mandatory)]
        [string]$WorkFlowID,

        [Parameter(Mandatory)]
        [string]$WorkFlowTaskID,

        [Parameter(Mandatory = $false)]
        [hashtable]$Configuration,

        [Parameter(Mandatory = $false)]
        [string]$OptionalData,

        [Parameter(Mandatory = $false)]
        [string]$ExportData
        
    )

    # Path to your JSON config file
    $configPath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath "..\Modules\Common\config.json")


    # Read and convert JSON file into PowerShell object
    $jsonConfig = Get-Content -Raw -Path $configPath | ConvertFrom-Json

    # Replace the tenantId under Destination -> ADT with the one from $config
    $jsonConfig.Destination.ADT.tenantId = $Configuration.'ADT-TenantID'
    $jsonConfig.Destination.ADT.clientSecret = $ConConfigurationfig.'ADT-ClientSecret'
    $jsonConfig.Destination.ADT.clientId = $Configuration.'ADT-ClientID'
    $jsonConfig.Destination.Prod.tenantId = $Configuration.'Prod-TenantID'
    $jsonConfig.Destination.Prod.clientSecret = $Configuration.'Prod-ClientSecret'
    $jsonConfig.Destination.Prod.clientId = $Configuration.'Prod-ClientID'
    $jsonConfig.Source.ADT.tenantId = $Configuration.'ADT-TenantID'
    $jsonConfig.Source.ADT.clientSecret = $Configuration.'ADT-ClientSecret'
    $jsonConfig.Source.ADT.clientId = $Configuration.'ADT-ClientID'
    $jsonConfig.Source.Prod.tenantId = $Configuration.'Prod-TenantID'
    $jsonConfig.Source.Prod.clientSecret = $Configuration.'Prod-ClientSecret'
    $jsonConfig.Source.Prod.clientId = $Configuration.'Prod-ClientID'
    $jsonConfig.Git.GitPAT = $Configuration.'TU-GITPAT'
   
    # Write the updated config back to file (preserves formatting)
    $jsonConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath

    if (-not (Test-Path $configPath)) {
        throw "Missing config file at loc $configPath"
    }
    $Config = Get-Content -Raw -Path $configPath | ConvertFrom-Json

    # Load modules
    . "$PSScriptRoot\Modules\Auth.ps1"
    . "$PSScriptRoot\Modules\Validate-Policy.ps1"
    . "$PSScriptRoot\Modules\Validate-Policy-Update.ps1"
    . "$PSScriptRoot\Modules\FetchPolicyFromGit.ps1"
    . "$PSScriptRoot\Modules\Import-Policy.ps1"


    # Extract all Base Policy IDs using regex
    if ($null -ne $OptionalData -and $OptionalData -ne '') {
        $imppattern = '(?is)imported\s+successfully\s+with\s+ID:\s*([a-f0-9\-]{36})'
    
        $imp_matches = [regex]::Matches($OptionalData, $imppattern)
    
        $imported_policy = ($imp_matches | ForEach-Object { $_.Groups[1].Value }) -join ','
        $PolicyIDs = $imported_policy
       # Write-Host "testing $PolicyIDs" -ForegroundColor Cyan
    }
    

    # Convert input to array
    $policyIdArray = $PolicyIDs -split ',' | ForEach-Object { $_.Trim() }
    
    # Variables to handle success, errors
    $missingPolicies = @()
    $errorsList = @()
    $importedPolicies = @()
    $comparePolicies = @()
    $failedImportedPolicies = @()
    $export_release_url = $null

    # Looping Policies
    foreach ($policyId in $policyIdArray) {
        #Write-Warning "Processing Policy ID: $policyId" -ForegroundColor Cyan
        $existingPolicyinSource="False"
        $existingPolicyGuidinSource="False"
       # Write-Warning "existingPolicyGuidinSource $($existingPolicyGuidinSource)"
        if ($Action -eq "Update Policy" ) {
            
            $policyRecordBeforeUpdate = Validate-Policy-Before-Update -PolicyId $policyId -Config $Config  -Source $Source -Action $Action 
            #Write-Host "Output of Validate-Policy-Before-Update:"
            
            if ($policyRecordBeforeUpdate) {
                $existingPolicyinSource = $policyRecordBeforeUpdate.PolicyRowId
                $existingPolicyGuidinSource = $policyRecordBeforeUpdate.existingPolicyGuidinSource
                $policyVersion = $policyRecordBeforeUpdate.PolicyVersion
                $gitpath = $policyRecordBeforeUpdate.GitPath
            }

            if ($null -ne $ExportData -and $ExportData -ne '') {
                if ($null -ne $OptionalData -and $OptionalData -ne '') {
                    if ($OptionalData -match "$policyId.*?Base Policy ID - ([0-9a-fA-F-]{36})") {
                        $basePolicyID = $matches[1]
                        Write-Output $basePolicyID
                    } else {
                        Write-Output "Base Policy ID not found for $importedPolicyID"
                    }

                    $pattern = [regex]::Escape($basePolicyID) + '.*?- GitPath:\s*(https?://.*?\.json)'

                    # Use Singleline so . matches newlines
                    $match = [regex]::Match($ExportData, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

                    if ($match.Success) {
                        # Remove any embedded whitespace/newlines from URL
                        $export_release_url = ($match.Groups[1].Value -replace '\s+', '')
                       
                    }
                }
            }
            
        }
       # Write-Host "existingPolicyinSource $existingPolicyinSource"
    
        # Check policy in database using Validate-Policy.ps1 module
        $policyRecord = Get-PolicyFromTable -PolicyId $policyId -Config $Config -WorkFlowID $WorkFlowID -Source $Source -Action $Action -Destination $Destination
        if (-not $policyRecord) {
            #Write-Warning "Policy ID $policyId not found in table."
            $missingPolicies += "`nPolicy ID does not exist or not exported in git: $($policyId)"
            $failedImportedPolicies += "$($policyId)"
            continue
        } else {

            $policyName = $($policyRecord.PolicyName)
            $PolicyRowId = $($policyRecord.PolicyRowId)
            $SourcePolicyID = $($policyRecord.PolicyId)
            $policyType = $policyRecord.PolicyType  # "Compliance Policy" or "Configuration Policy"
            $policyVersion = $policyRecord.PolicyVersion
            $gitpath = $policyRecord.GitPath
           # Write-Warning "$existingPolicyinSource"
           #Write-Warning "gitpath $gitpath"

           if ([string]::IsNullOrWhiteSpace($gitpath)) {
                $errorsList += "`ngitpath is empty for Policy ID $($policyId). Cannot proceed with import."
                $failedImportedPolicies += "$($policyId)"
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
                #Write-Warning "$PolicyType"
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
            #Write-Host "rawurl: $rawUrl" -ForegroundColor Cyan

            

            try {
                #Write-Host "ScopeTags = $ScopeTags"
                $gitjsonresponse = Fetch-PolicyFromGit -PolicyType $policyType -Config $Config -Source $Source -Destination $Destination -PolicyId $policyId -ExportGitPath $rawUrl -gitpath $gitpath -ExistingPolicyinSource $existingPolicyinSource -ScopeTags $ScopeTags
                #Write-Host $ScopeTags

                #$gitjsonresponse | Format-List
                if ($gitjsonresponse.Success) {
                    
                    $policyJson = $gitjsonresponse.Response
                    $release_url = $gitjsonresponse.releaseURL
                    $AssignedScopeTags = $gitjsonresponse.roleScopeTags
                    #Write-Host "policyJson: $policyJson" -ForegroundColor Cyan
                
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
                    

                    if ($Action -eq "Create New Policy" -and $Source -eq "ADT" -and $Destination -eq "Prod") {

                        # Handle displayName if present
                        if ($policyJson.displayName -and (-not $policyJson.displayName.StartsWith("CaC-"))) {
                            $policyJson.displayName = "CaC-$($policyJson.displayName)"
                        }

                        # Handle name if present
                        if ($policyJson.name -and (-not $policyJson.name.StartsWith("CaC-"))) {
                            $policyJson.name = "CaC-$($policyJson.name)"
                        }

                        # Determine ProdPolicyName from either displayName or name
                        if ($policyJson.displayName) {
                            $ProdPolicyName = $policyJson.displayName
                        }
                        elseif ($policyJson.name) {
                            $ProdPolicyName = $policyJson.name
                        }

                        # Update the description with the additional text at the beginning
                        $policyJson.description = $additionalDescription + "`n" + $truncatedDescription
                    }
                    if ($Action -eq "Update Policy" -and $Source -eq "ADT" -and $Destination -eq "Prod") {
                        # Update the description with the additional text at the beginning
                        $policyJson.description = $additionalDescription + "`n" + $truncatedDescription
                    }

                    if ($ProdPolicyName -eq $null) {
                        $ProdPolicyName = $policyName
                    }
                   
                    #Write-Host "policyJsonNN: $policyJson" -ForegroundColor Cyan
                    # Check for Duplicate Policy in Destination
                    # Write-Host "existingPolicyGuidinSourceSS: $existingPolicyGuidinSource" -ForegroundColor Cyan
                    $duplicatePolicyinDestination = Check-Duplicate-PolicyInDestination -ProdPolicyName $ProdPolicyName -Config $Config -Destination $Destination -policyType $policyType -Action $Action
                    if (-not $duplicatePolicyinDestination -or $Action -eq 'Update Policy') {
                        # Import from Import-Policy Module

                        $response = Import-PolicyToIntune -Action $Action -PolicyJson $policyJson -PolicyType $policyType -Token $token -Config $Config -PolicyRowId $PolicyRowId -policyVersion $policyVersion -PolicyId $policyId -WorkFlowID $WorkFlowID -Destination $Destination -ExportGitPath $rawUrl -WorkFlowTaskID $WorkFlowTaskID -ScopeTags $ScopeTags -PolicyName $ProdPolicyName -Source $Source -ExistingPolicyGuidinSource $existingPolicyGuidinSource
                        #Write-Host "`nFull Response:"
                       # $response | Format-List
                        if ($response.Success) {
                               #Write-Host "AssignedScopeTags: $AssignedScopeTags"  
                            $importedPolicies += "`n`n $($response.Response.policytype) - $($response.Response.policyname) imported successfully with ID: $($response.Response.id). Base Policy ID - $($response.Response.baseID) "
                            $comparePolicies+= "`n $($response.Response.uri)/$($response.Response.id) - $rawUrl"
                           
                            
                        } else {
                            $errorsList += "`nImport failed for Policy ID $($policyId) : $($response.ErrorMessage)"
                            $failedImportedPolicies += "$($policyId)"
                            continue
                        }
                    }else{
                        $errorsList += "Duplicate policy. Policy $($duplicatePolicyinDestination.PolicyName) found in destination tenant"
                        $failedImportedPolicies += "$($policyId)"
                            continue
                    } 

                    
                } else {
                    $errorsList += "`nFailed to fetch policy from Git for Policy ID $($policyId): $($gitjsonresponse.ErrorMessage)"
                    $failedImportedPolicies += "$($policyId)"
                }
                
            }
            catch {
                $errorsList += "`nFailed to fetch or parse JSON for Policy ID $($policyId): $($_.Exception.Message)"
                $failedImportedPolicies += "$($policyId)"
                continue
            }

        }


    }

    if ($missingPolicies.Count -gt 0) {
        Write-Host "`nMissing Policy IDs:" -ForegroundColor Yellow
        $missingPolicies | ForEach-Object { Write-Host "- $_" }
    }
    #if ($errorsList.Count -gt 0) {
    #    Write-Host "`nSummary of Errors:"
    #    $errorsList | ForEach-Object { Write-Warning $_ }
    #}
    if ($errorsList.Count -gt 0) {
        Write-Host "`n=====================" -ForegroundColor Yellow
        Write-Host " Failed to import policies:" -ForegroundColor Yellow
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
    if ($importedPolicies.Count -gt 0) {
        Write-Host "`nImported Policies:" -ForegroundColor Green
        $importedPolicies | ForEach-Object { Write-Host $_ }
    }
    if ($failedImportedPolicies.Count -gt 0) {
        Write-Host "`nFailed to import Policy:" -ForegroundColor Yellow
        $failedImportedPolicies | ForEach-Object { Write-Host $_ }
    }

    if ($comparePolicies.Count -gt 0) {
        Write-Host "`nCompare Policies:" -ForegroundColor Green
        $comparePolicies | ForEach-Object { Write-Host $_ }
    }
    

}
