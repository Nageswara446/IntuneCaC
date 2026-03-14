# Determine the root path (one level up from RestoreModule folder)
$moduleRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$commonPath = Join-Path $moduleRoot "..\Modules\Common" | Resolve-Path

# Import the required scripts
$commonScripts = @(
    "Get-DatabaseConnection.ps1",
    "Auth.ps1"
)

foreach ($script in $commonScripts) {
    $fullPath = Join-Path $commonPath $script
    if (Test-Path $fullPath) {
        . $fullPath
        Write-Output "Imported $script"
    }
    else {
        Write-Error "Required script $script not found at $fullPath"
    }
}

function ValidateXLRIDorReleaseTag {
    param (
        [Parameter(Mandatory)][PSCustomObject]$Configuration,
        [Parameter(Mandatory)][string]$XLRIDReleaseTag,
        [Parameter(Mandatory)][string]$XLRIDReleaseTagValue,
        [Parameter(Mandatory)][string]$policy,
        [Parameter(Mandatory)][string]$PolicyID
    )

    $connection = $null
    $result = [PSCustomObject]@{
        Success      = $false
        Response     = $null
        ErrorMessage = ""
    }

    try {
        # Split PolicyID string into an array if 'Specific Policy' is selected
        $PolicyIDArray = @()
        if ($policy -eq 'Specific Policy') {
            $PolicyIDArray = $PolicyID -split ',' | ForEach-Object { $_.Trim() }
        }

        # Path to your JSON config file
        $configPath = "$PSScriptRoot\config.json"

        if (-not (Test-Path $configPath)) {
            throw "Missing config file at $configPath"
        }

        # Read and update JSON config
        $jsonConfig = Get-Content -Raw -Path $configPath | ConvertFrom-Json
        $jsonConfig.Git.GitPAT = $Configuration.'TU-GITPAT'
        $jsonConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath

        $Config = Get-Content -Raw -Path $configPath | ConvertFrom-Json
        $connection = Get-DatabaseConnection -Config $Config
        if ($XLRIDReleaseTag -eq 'XLRelease ID') {
            $command = $connection.CreateCommand()
            try {
                $query = @"
                SELECT COUNT(*) AS RecordCount 
            FROM policies p
            INNER JOIN policybackups pb ON p.PolicyID = pb.PolicyID
            WHERE p.WorkflowID=@XLRIDReleaseTagValue
"@
                $command.CommandText = $query
                $command.Parameters.Clear() 
                $command.Parameters.Add("@XLRIDReleaseTagValue", $XLRIDReleaseTagValue) | Out-Null
                # Write-Output $XLRIDReleaseTagValue
                # Get-SqlCommandWithParametersReplaced -Command $command
                $reader = $command.ExecuteReader()
                $count = 0
                if ($reader.Read()) {
                    $count = [int]$reader["RecordCount"]
                }
                $reader.Close()
            } finally {
                $command.Dispose()
            }
            Write-Output "Count $count"
            if ($count -gt 0) {
                $command2 = $connection.CreateCommand()
                try {
                    $query2 = @"
SELECT * 
FROM policies p 
INNER JOIN policybackups pb ON p.PolicyID = pb.PolicyID 
WHERE p.WorkflowID=@XLRIDReleaseTagValue
"@
                    $command2.CommandText = $query2
                    $command2.Parameters.Clear()
                    $command2.Parameters.Add("@XLRIDReleaseTagValue", $XLRIDReleaseTagValue) | Out-Null
                    # Write-Output $XLRIDReleaseTagValue
                    # Get-SqlCommandWithParametersReplaced -Command $command2
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
                            AssignmentFile  = $reader2["AssignmentFile"] + "\" + $reader2["PolicyGuid"] + "_assignment.json"
                            BackupFilePath  = $reader2["BackupFilePath"]
                            PolicyVersion   = $reader2["PolicyVersion"]
                            Env             = $reader2["Environment"]
                            PolicyType      = $reader2["PolicyType"]
                            release_workflowID = $reader2["WorkflowID"]
                            release_version = $ReleaseVersion
                        }
                        $releaseList += $obj
                    }
                    $reader2.Close()
                } finally {
                    $command2.Dispose()
                }
                foreach ($item in $releaseList) {
                    $release_git        = $item.GitPathdb
                    $release_env        = $item.Env
                    $release_policytype = $item.PolicyType
                    $release_version    = $item.release_version
                    $release_workflowID    = $item.release_workflowID

                    Write-Host "release_version - $release_version"

                    if ($release_git -match '/([0-9a-fA-F\-]{36})\.json$') {
                        $PolicyGuid = $matches[1]
                    } else {
                        Write-Host "No valid PolicyGuid found in path $release_git"
                        continue
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
                    $TagName     = $release_version
                    # $AssetName   = "$PolicyGuid.json"
                    $AssetNames = @(
                        # "$PolicyGuid.json",
                        "${PolicyGuid}_assignment.json"
                    )
                    $releaseUrl  = "$ApiBaseUrl/api/v3/repos/$RepoOwner/$RepoName/releases/tags/$TagName"
                    $DownloadPath = "C:\URM\Testing"

                    $headers = @{ 
                        Authorization = "token $Token" 
                        Accept        = "application/json" 
                        "User-Agent"  = "MyPowerShellScript/1.0" 
                    }

                    $release = Invoke-RestMethod -Uri $releaseUrl -Headers $headers -Method Get 
                    # $asset = $release.assets | Where-Object { $_.name -eq $AssetName }

                    # if ($asset) {
                    #     $assetId = $asset.id
                    #     Write-Host "Found asset ID: $assetId"
                    #     $assetDownloadUrl = "$ApiBaseUrl/api/v3/repos/$RepoOwner/$RepoName/releases/assets/$assetId"
                    #     $outputFile = Join-Path -Path $DownloadPath -ChildPath $AssetName

                    #     $downloadHeaders = @{
                    #         Authorization = "token $Token"
                    #         Accept        = "application/octet-stream"
                    #         "User-Agent"  = "MyPowerShellScript/1.0"
                    #     }

                    #     Invoke-WebRequest -Uri $assetDownloadUrl -Headers $downloadHeaders -OutFile $outputFile 
                    #     $GitPathdb += "$PolicyGuid - $outputFile - $release_env - $release_policytype;"
                    # } else {
                    #     $result.ErrorMessage = "Asset not found for PolicyGuid $PolicyGuid"
                    #     continue
                    # }
                    foreach ($AssetName in $AssetNames) {
                        $asset = $release.assets | Where-Object { $_.name -eq $AssetName }

                        if ($asset) {
                            $assetId = $asset.id
                            Write-Host "Found asset ID: $assetId for $AssetName"
                            $assetDownloadUrl = "$ApiBaseUrl/api/v3/repos/$RepoOwner/$RepoName/releases/assets/$assetId"
                            $outputFile = Join-Path -Path $DownloadPath -ChildPath $AssetName

                            $downloadHeaders = @{
                                Authorization = "token $Token"
                                Accept        = "application/octet-stream"
                                "User-Agent"  = "MyPowerShellScript/1.0"
                            }

                            Invoke-WebRequest -Uri $assetDownloadUrl -Headers $downloadHeaders -OutFile $outputFile 
                            $GitPathdb += "$PolicyGuid - $outputFile - $release_env - $release_policytype - $release_workflowID - $release_git;"
                        } 
                        else {
                            Write-Host "Asset not found for $AssetName"
                            continue
                        }
                    }
                }

                $result.Success  = $true
                $result.Response = "Exists : $($GitPathdb)"
                return $result
            } else {
                $result.ErrorMessage = "XLR ID does not exist"
                return $result
            }
        }

        if ($XLRIDReleaseTag -eq 'Release Tag') {
            $command = $connection.CreateCommand()
            try {
                $query = @"
                SELECT COUNT(*) AS RecordCount 
            FROM policies p
            INNER JOIN policybackups pb ON p.PolicyID = pb.PolicyID
            WHERE p.WorkflowID = @XLRIDReleaseTagValue
"@
                $command.CommandText = $query
                $command.Parameters.Clear()
                $command.Parameters.Add("@XLRIDReleaseTagValue", "%$XLRIDReleaseTagValue%") | Out-Null
                $reader = $command.ExecuteReader()
                $count = 0
                if ($reader.Read()) {
                    $count = [int]$reader["RecordCount"]
                }
                $reader.Close()
            } finally {
                $command.Dispose()
            }

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
                    try {
                        $query2 = @"
SELECT * FROM policies p 
INNER JOIN policybackups pb ON p.PolicyID = pb.PolicyID 
WHERE p.WorkflowID = @XLRIDReleaseTagValue
"@
                        $command2.CommandText = $query2
                        $command2.Parameters.Clear()
                        $command2.Parameters.Add("@XLRIDReleaseTagValue", "%$XLRIDReleaseTagValue%") | Out-Null
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
                                AssignmentFile  = $reader2["AssignmentFile"] + "\" + $reader2["PolicyGuid"] + "_assignment.json"
                                BackupFilePath  = $reader2["BackupFilePath"]
                                PolicyVersion   = $reader2["PolicyVersion"]
                                Env             = $reader2["Environment"]
                                PolicyType      = $reader2["PolicyType"]
                                release_workflowID = $reader2["WorkflowID"]
                                release_version = $ReleaseVersion
                            }
                            $releaseList += $obj
                        }
                        $reader2.Close()
                    } finally {
                        $command2.Dispose()
                    }

                    foreach ($item in $releaseList) {
                        $release_git        = $item.GitPathdb
                        $release_env        = $item.Env
                        $release_policytype = $item.PolicyType
                        $release_version    = $item.release_version
                        $release_workflowID    = $item.release_workflowID

                        if ($release_git -match '/([0-9a-fA-F\-]{36})\.json$') {
                            $PolicyGuid = $matches[1]
                        } else {
                            Write-Host "No valid PolicyGuid found in path $release_git"
                            continue
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
                        # $AssetName   = "$PolicyGuid.json"
                        $AssetNames = @(
                            # "$PolicyGuid.json",
                            "${PolicyGuid}_assignment.json"
                        )
                        $releaseUrl  = "$ApiBaseUrl/api/v3/repos/$RepoOwner/$RepoName/releases/tags/$TagName"
                        $DownloadPath = "C:\URM\Testing"

                        $headers = @{ 
                            Authorization = "token $Token" 
                            Accept        = "application/json" 
                            "User-Agent"  = "MyPowerShellScript/1.0" 
                        }

                        $release = Invoke-RestMethod -Uri $releaseUrl -Headers $headers -Method Get 
                        # $asset = $release.assets | Where-Object { $_.name -eq $AssetName }

                        # if ($asset) {
                        #     $assetId = $asset.id
                        #     Write-Host "Found asset ID: $assetId"
                        #     $assetDownloadUrl = "$ApiBaseUrl/api/v3/repos/$RepoOwner/$RepoName/releases/assets/$assetId"
                        #     $outputFile = Join-Path -Path $DownloadPath -ChildPath $AssetName

                        #     $downloadHeaders = @{
                        #         Authorization = "token $Token"
                        #         Accept        = "application/octet-stream"
                        #         "User-Agent"  = "MyPowerShellScript/1.0"
                        #     }

                        #     Invoke-WebRequest -Uri $assetDownloadUrl -Headers $downloadHeaders -OutFile $outputFile 
                        #     $GitPathdb += "$PolicyGuid - $outputFile - $release_env - $release_policytype;"
                        # } else {
                        #     $result.ErrorMessage = "Asset not found for PolicyGuid $PolicyGuid"
                        #     continue
                        # }
                        foreach ($AssetName in $AssetNames) {
                            $asset = $release.assets | Where-Object { $_.name -eq $AssetName }

                            if ($asset) {
                                $assetId = $asset.id
                                Write-Host "Found asset ID: $assetId for $AssetName"
                                $assetDownloadUrl = "$ApiBaseUrl/api/v3/repos/$RepoOwner/$RepoName/releases/assets/$assetId"
                                $outputFile = Join-Path -Path $DownloadPath -ChildPath $AssetName

                                $downloadHeaders = @{
                                    Authorization = "token $Token"
                                    Accept        = "application/octet-stream"
                                    "User-Agent"  = "MyPowerShellScript/1.0"
                                }

                                Invoke-WebRequest -Uri $assetDownloadUrl -Headers $downloadHeaders -OutFile $outputFile 
                                $GitPathdb += "$PolicyGuid - $outputFile - $release_env - $release_policytype - $release_workflowID - $release_git;"
                            } 
                            else {
                                Write-Host "Asset not found for $AssetName"
                            }
                        }
                    }

                    $result.Success  = $true
                    $result.Response = "Exists : $($GitPathdb)"
                    return $result
                } else {
                    $result.ErrorMessage = "Release not found for tag $TagName"
                    return $result
                }
            } else {
                $result.ErrorMessage = "Release Tag does not exist in database"
                return $result
            }
        }
    } catch {
        $result.ErrorMessage = "Failed to validate release or git tag: $($_.Exception.Message)"
        if ($_.Exception.PSObject.Properties.Name -contains "Response" -and $_.Exception.Response) {
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $result.ErrorMessage += "`n" + $reader.ReadToEnd()
            } catch {}
        }
        return $result
    } finally {
        if ($connection) {
            $connection.Close()
            $connection.Dispose()
        }
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

        # safer replace with word boundaries
        $query = [regex]::Replace($query, "\b$([regex]::Escape($paramName))\b", $replacement)
    }

    return $query
}
