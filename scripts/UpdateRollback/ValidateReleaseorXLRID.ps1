. "$PSScriptRoot\..\Modules\Common\Get-DatabaseConnection.ps1"
function ValidateXLRIDorReleaseTag {

    param (
        [Parameter(Mandatory)][PSCustomObject]$Configuration,
        [Parameter(Mandatory)][string]$XLRIDReleaseTag,
        [Parameter(Mandatory)][string]$XLRIDReleaseTagValue,
        [Parameter(Mandatory)][string]$policy,
        [string]$PolicyID
    )

    $connection = $null
    $result = [PSCustomObject]@{
        Success      = $false
        Response     = $null
        ErrorMessage = ""
    }
    #$timestamp = Get-Date -Format "yyyyMMdd_HHmmssfff"

    try {
        # Split PolicyID string into an array if 'Specific Policy' is selected
        $PolicyIDArray = @()
        if ($policy -eq 'Specific Policy') {
           if (-not [string]::IsNullOrWhiteSpace($PolicyID)) {
            $PolicyIDArray = $PolicyID -split ',' | ForEach-Object { $_.Trim() }
            } else {
                # If policy is 'Specific Policy' but PolicyID empty, throw or handle gracefully
                $result.ErrorMessage = "PolicyID must be provided when policy is 'Specific Policy'."
                return $result
            }
        }

        # Path to your JSON config file
        $configPath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath "..\Modules\Common\config.json")


        # Read and convert JSON file into PowerShell object
        $jsonConfig = Get-Content -Raw -Path $configPath | ConvertFrom-Json
        $jsonConfig.Git.GitPAT = $Configuration.'TU-GITPAT'

        # Write the updated config back to file (preserves formatting)
        $jsonConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath

        if (-not (Test-Path $configPath)) {
            throw "Missing config file at $configPath"
        }

        $Config = Get-Content -Raw -Path $configPath | ConvertFrom-Json

        if ($XLRIDReleaseTag -eq 'XLRelease ID') {
            $connection = Get-DatabaseConnection -Config $Config
            $command = $connection.CreateCommand()
            $query = @"
            SELECT COUNT(*) AS RecordCount
            FROM unified_release_management.policies 
            WHERE WorkflowID = @XLRIDReleaseTagValue 
            AND ActionType IN ('Update Policy') 
            AND Is_Deleted = 'False'
            AND XLRTaskID LIKE '%12'
"@
            $command.CommandText = $query
            $command.Parameters.AddWithValue("@XLRIDReleaseTagValue", $XLRIDReleaseTagValue) | Out-Null
            #Write-Host "SQL Query with parameters replaced:"
            #Write-Host (Get-SqlCommandWithParametersReplaced -Command $command)
            $reader = $command.ExecuteReader()
            $count = 0

            if ($reader.Read()) {
                $count = $reader["RecordCount"]
            }
            $reader.Close()

            if ($count -gt 0) {
                # Extract policy IDs:
                $command2 = $connection.CreateCommand()
                $query2 = @"
                SELECT GitPath,Environment,PolicyType,WorkflowID
                FROM unified_release_management.policies 
                WHERE WorkflowID = @XLRIDReleaseTagValue 
                AND ActionType IN ('Export Policy') 
                AND Is_Deleted = 'False'
                AND XLRTaskID LIKE '%05'
"@
                $command2.CommandText = $query2
                $command2.Parameters.AddWithValue("@XLRIDReleaseTagValue", $XLRIDReleaseTagValue) | Out-Null
                #Write-Host "SQL Query with parameters replaced:"
                #Write-Host (Get-SqlCommandWithParametersReplaced -Command $command2)
                $reader2 = $command2.ExecuteReader()

                $GitPathdb = ""
                $releaseList = @()

                while ($reader2.Read()) {
                    $gitPath = $reader2["GitPath"]
                    $ReleaseVersion = $null

                    if ($gitPath -match 'releases/download/(Release-[^/]+)') {
                        $ReleaseVersion = $matches[1]
                    }

                    $obj = [PSCustomObject]@{
                        GitPathdb       = $gitPath
                        Env             = $reader2["Environment"]
                        PolicyType      = $reader2["PolicyType"]
                        release_version = $ReleaseVersion
                        release_workflowID = $reader2["WorkflowID"]
                    }

                    $releaseList = $releaseList + @($obj)
                }
                $reader2.Close()

                foreach ($item in $releaseList) {
                    $release_git        = $item.GitPathdb
                    $release_env        = $item.Env
                    $release_policytype = $item.PolicyType
                    $release_version    = $item.release_version
                    $release_workflowID    = $item.release_workflowID


                    #Write-Host "release_version - $release_version"

                    if ($release_git -match '/([0-9a-fA-F\-]{36})\.json$') {
                        $PolicyGuid = $matches[1]
                    }

                    Write-Host "Validating - $PolicyGuid"

                    if ($policy -eq 'Specific Policy' -and -not ($PolicyIDArray -contains $PolicyGuid)) {
                        Write-Host "Skipping PolicyGuid $PolicyGuid as it is not in specified list."
                        continue
                    }
                
                    $Token       = $Config.Git.GitPAT
                    $RepoOwner   = $Config.Git.repoOwner
                    $RepoName    = $Config.Git.repoName
                    $ApiBaseUrl  = $Config.Git.rawUrl
                    $TagName     = $release_version
                    $AssetName   = "$PolicyGuid.json"
                    $AssignmentAssetName   = "${PolicyGuid}_assignment.json"
                    $releaseUrl  = "$ApiBaseUrl/api/v3/repos/$RepoOwner/$RepoName/releases/tags/$TagName"
                    $DownloadPath = "C:\URM\backup-rollback"

                    $headers = @{ 
                        Authorization = "token $Token" 
                        Accept        = "application/json" 
                        "User-Agent"  = "MyPowerShellScript/1.0" 
                    }

                    $release = Invoke-RestMethod -Uri $releaseUrl -Headers $headers -Method Get 
                    $asset = $release.assets | Where-Object { $_.name -eq $AssetName }

                    if ($asset) {
                        $assetId = $asset.id
                        #Write-Host "Found asset ID: $assetId"
                        $assetDownloadUrl = "$ApiBaseUrl/api/v3/repos/$RepoOwner/$RepoName/releases/assets/$assetId"
                        $uniquePolicyName = "${PolicyGuid}.json"
                        $outputFile = Join-Path -Path $DownloadPath -ChildPath $uniquePolicyName

                        $downloadHeaders = @{
                            Authorization = "token $Token"
                            Accept        = "application/octet-stream"
                            "User-Agent"  = "MyPowerShellScript/1.0"
                        }

                        Invoke-WebRequest -Uri $assetDownloadUrl -Headers $downloadHeaders -OutFile $outputFile 
                        $GitPathdb += "$PolicyGuid - $outputFile - $release_env - $release_policytype - $release_workflowID - $release_git;"
                        $PolicyValidation += "Updated $release_policytype Found with $PolicyGuid in $release_workflowID ;"
                        # Download Policy Assignment JSON Asset (if exists)
                        $assignmentAsset = $release.assets | Where-Object { $_.name -eq $AssignmentAssetName }
                        if ($assignmentAsset) {
                            $assignmentAssetId = $assignmentAsset.id
                            #Write-Host "Found assignment asset ID: $assignmentAssetId"
                            $assignmentDownloadUrl = "$ApiBaseUrl/api/v3/repos/$RepoOwner/$RepoName/releases/assets/$assignmentAssetId"
                            $uniquePolicyAssignmentName = "${PolicyGuid}_assignment.json"
                            $assignmentOutputFile = Join-Path -Path $DownloadPath -ChildPath $uniquePolicyAssignmentName

                            Invoke-WebRequest -Uri $assignmentDownloadUrl -Headers $downloadHeaders -OutFile $assignmentOutputFile 
                        } else {
                            $result.ErrorMessage ="Assignment asset not found for $PolicyGuid"
                            continue
                        }
                    } else {
                        $result.ErrorMessage = "Asset ID not found for $($PolicyId)"
                        continue
                    }
                }

                $result.Success  = $true
                $result.Response = "Validation Report : $($PolicyValidation) Exists : $($GitPathdb)"

                return $result
            } else {
                $result.ErrorMessage = "XLR ID does not exists"
                return $result
            }
        }

        if ($XLRIDReleaseTag -eq 'Release Tag') {
            $connection = Get-DatabaseConnection -Config $Config
            $command = $connection.CreateCommand()
            $query = @"
            SELECT COUNT(*) AS RecordCount
            FROM unified_release_management.policies 
            WHERE GitPath LIKE @XLRIDReleaseTagValue
            AND ActionType IN ('Export Policy') 
            AND Is_Deleted = 'False'
            AND XLRTaskID LIKE '%05'
"@
            $command.CommandText = $query
            $command.Parameters.AddWithValue("@XLRIDReleaseTagValue", "%$XLRIDReleaseTagValue%") | Out-Null
            $reader = $command.ExecuteReader()
            $count = 0

            if ($reader.Read()) {
                $count = $reader["RecordCount"]
            }
            $reader.Close()

            if ($count -gt 0) {
                $Token       = $Config.Git.GitPAT
                $RepoOwner   = $Config.Git.repoOwner
                $RepoName    = $Config.Git.repoName
                $ApiBaseUrl  = $Config.Git.rawUrl
                $TagName     = $XLRIDReleaseTagValue
                $releaseUrl  = "$ApiBaseUrl/api/v3/repos/$RepoOwner/$RepoName/releases/tags/$TagName"

                $headers = @{ 
                    Authorization = "token $Token" 
                    Accept        = "application/json" 
                    "User-Agent"  = "MyPowerShellScript/1.0" 
                }

                $release = Invoke-RestMethod -Uri $releaseUrl -Headers $headers -Method Get -ErrorAction Stop

                if ($release) {
                    Write-Host "Release with tag '$TagName' exists."

                    $command2 = $connection.CreateCommand()
                    $query2 = @"
                    SELECT GitPath,Environment,PolicyType,WorkflowID
                    FROM unified_release_management.policies 
                    WHERE GitPath LIKE @XLRIDReleaseTagValue
                    AND ActionType IN ('Export Policy') 
                    AND Is_Deleted = 'False'
                    AND XLRTaskID LIKE '%05'
"@
                    $command2.CommandText = $query2
                    $command2.Parameters.AddWithValue("@XLRIDReleaseTagValue", "%$XLRIDReleaseTagValue%") | Out-Null
                    $reader2 = $command2.ExecuteReader()

                    $GitPathdb = ""
                    $releaseList = @()

                    while ($reader2.Read()) {
                        $gitPath = $reader2["GitPath"]

                        $obj = [PSCustomObject]@{
                            GitPathdb  = $gitPath
                            Env        = $reader2["Environment"]
                            PolicyType = $reader2["PolicyType"]
                            release_workflowID = $reader2["WorkflowID"]
                        }

                        $releaseList = $releaseList + @($obj)
                    }
                    $reader2.Close()

                    foreach ($item in $releaseList) {
                        $release_git        = $item.GitPathdb
                        $release_env        = $item.Env
                        $release_policytype = $item.PolicyType
                        $release_workflowID = $item.release_workflowID

                        if ($release_git -match '/([0-9a-fA-F\-]{36})\.json$') {
                            $PolicyGuid = $matches[1]
                        }

                        Write-Host "PolicyGuid - $PolicyGuid"

                        if ($policy -eq 'Specific Policy' -and -not ($PolicyIDArray -contains $PolicyGuid)) {
                            Write-Host "Skipping PolicyGuid $PolicyGuid as it is not in specified list."
                            continue
                        }

                        $Token       = $Config.Git.GitPAT
                        $RepoOwner   = $Config.Git.repoOwner
                        $RepoName    = $Config.Git.repoName
                        $ApiBaseUrl  = $Config.Git.rawUrl
                        $TagName     = $XLRIDReleaseTagValue
                        $AssetName   = "$PolicyGuid.json"
                        $AssignmentAssetName   = "${PolicyGuid}_assignment.json"
                        $releaseUrl  = "$ApiBaseUrl/api/v3/repos/$RepoOwner/$RepoName/releases/tags/$TagName"
                        $DownloadPath = "C:\URM\backup-rollback"

                        $headers = @{ 
                            Authorization = "token $Token" 
                            Accept        = "application/json" 
                            "User-Agent"  = "MyPowerShellScript/1.0" 
                        }

                        $release = Invoke-RestMethod -Uri $releaseUrl -Headers $headers -Method Get 
                        $asset = $release.assets | Where-Object { $_.name -eq $AssetName }
                        

                        if ($asset) {
                            $assetId = $asset.id
                            Write-Host "Found asset ID: $assetId"
                            $assetDownloadUrl = "$ApiBaseUrl/api/v3/repos/$RepoOwner/$RepoName/releases/assets/$assetId"
                            $outputFile = Join-Path -Path $DownloadPath -ChildPath $AssetName

                            $downloadHeaders = @{
                                Authorization = "token $Token"
                                Accept        = "application/octet-stream"
                                "User-Agent"  = "MyPowerShellScript/1.0"
                            }

                            Invoke-WebRequest -Uri $assetDownloadUrl -Headers $downloadHeaders -OutFile $outputFile 
                            $GitPathdb += "$PolicyGuid - $outputFile - $release_env - $release_policytype - $release_workflowID - $release_git;"
                            $PolicyValidation += "Updated $release_policytype Found with $PolicyGuid in $release_workflowID ;"

                        } else {
                            $result.ErrorMessage = "Asset ID not found for $($PolicyId)"
                            continue
                        }

                        # Download Policy Assignment JSON Asset (if exists)
                        $assignmentAsset = $release.assets | Where-Object { $_.name -eq $AssignmentAssetName }
                        if ($assignmentAsset) {
                            $assignmentAssetId = $assignmentAsset.id
                            Write-Host "Found assignment asset ID: $assignmentAssetId"
                            $assignmentDownloadUrl = "$ApiBaseUrl/api/v3/repos/$RepoOwner/$RepoName/releases/assets/$assignmentAssetId"
                            $assignmentOutputFile = Join-Path -Path $DownloadPath -ChildPath $AssignmentAssetName

                            Invoke-WebRequest -Uri $assignmentDownloadUrl -Headers $downloadHeaders -OutFile $assignmentOutputFile 
                        } else {
                            Write-Host "Assignment asset not found for $PolicyGuid"
                        }

                    }

                    $result.Success  = $true
                    $result.Response = "Validation Report : $($PolicyValidation)  Exists : $($GitPathdb)"
                    return $result
                } else {
                    Write-Host "Release with tag '$TagName' does not exist."
                    $result.ErrorMessage = "Release not found for tag $TagName"
                    return $result
                }
            } else {
                $result.ErrorMessage = "Release Tag does not exists in database"
                return $result
            }
        }

    } catch {
        $result.ErrorMessage = "Failed to validate release or git tag: $($_.Exception.Message)"
        if ($_.Exception.Response -ne $null) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $result.ErrorMessage += "`n" + $reader.ReadToEnd()
        }
        return $result
    }
}

function Get-SqlCommandWithParametersReplaced {
    param(
        [System.Data.Common.DbCommand]$Command
    )

    $query = $Command.CommandText

    foreach ($param in $Command.Parameters) {
        $paramName = $param.ParameterName
        $paramValue = $param.Value

        if ($null -eq $paramValue) {
            $replacement = "NULL"
        } elseif ($paramValue -is [string]) {
            $escapedValue = $paramValue.Replace("'", "''")
            $replacement = "'$escapedValue'"
        } elseif ($paramValue -is [DateTime]) {
            $replacement = "'$($paramValue.ToString("yyyy-MM-dd HH:mm:ss"))'"
        } else {
            $replacement = $paramValue.ToString()
        }

        $query = $query -replace [regex]::Escape($paramName), $replacement
    }

    return $query
}
