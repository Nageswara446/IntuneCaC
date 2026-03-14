# Function: Push-PolicyJsonToGitHub
# Description: Pushes exported policy and assignment JSON files to a GitHub repository.
# Parameters:
#   - GitHubPAT (string, Mandatory): GitHub Personal Access Token for authentication.
#   - Policies (array, Mandatory): Array of policy objects to push.
#   - BaseExportPath (string, Mandatory): Path to the directory containing policy JSON files.
#   - AssignmentsPath (string, Mandatory): Path to the directory containing assignment JSON files.
#   - Config (PSCustomObject, Mandatory): Configuration object containing repository details.
 
function Push-PolicyJsonToGitHub {
    param (
        [Parameter(Mandatory = $true)][string]$GitHubPAT,
        [Parameter(Mandatory = $true)][array]$Policies,
        [Parameter(Mandatory = $true)][string]$BaseExportPath,
        [Parameter(Mandatory = $true)][string]$AssignmentsPath,
        [Parameter(Mandatory = $true)][PSCustomObject]$Config
    )

    $OriginalLocation = Get-Location

    if (-not $Policies) {
        return $false
    }

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        return $false
    }

    $tempDir = $Config.TempDir
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

    try {
        $repoUrlWithAuth = $Config.RepoUrl -replace "https://", "https://$GitHubPAT@"
        git clone --branch $Config.Branch $repoUrlWithAuth $tempDir -q
        if ($LASTEXITCODE -ne 0) {
            return $false
        }

        $compliancePath      = Join-Path $tempDir (Join-Path $Config.BaseRepoPath "backup/compliance")
        $configurationPath   = Join-Path $tempDir (Join-Path $Config.BaseRepoPath "backup/configuration")
        $assignmentsPathRepo = Join-Path $tempDir (Join-Path $Config.BaseRepoPath "backup/assignments")

        New-Item -ItemType Directory -Path $assignmentsPathRepo -Force | Out-Null

        foreach ($policy in $Policies) {
            $policyId = $policy.PolicyId
            $policyFileName = "$policyId.json"
            $assignmentFileName = "$policyId`_assignment.json"

            $policyFile = Join-Path $BaseExportPath $policyFileName
            $assignmentFile = Join-Path $AssignmentsPath $assignmentFileName

            $targetPolicyPath = if ($policy.PolicyTypeFull -eq "Compliance Policy") {
                $compliancePath
            } else {
                $configurationPath
            }

            if (Test-Path $policyFile) {
                Copy-Item -Path $policyFile -Destination (Join-Path $targetPolicyPath $policyFileName) -Force
                # Write-Log "Copied policy file: $policyFileName"
            } else {
                
            }

            if (Test-Path $assignmentFile) {
                Copy-Item -Path $assignmentFile -Destination (Join-Path $assignmentsPathRepo $assignmentFileName) -Force
                # Write-Log "Copied assignment file: $assignmentFileName"
            } 
            # else {
            #     Write-Log "No assignment file for: $policyFileName"
            # }
        }

        # Commit and push changes - only stage relevant files
        Set-Location $tempDir

        foreach ($policy in $Policies) {
            $policyId = $policy.PolicyId
            $policyFileName = "$policyId.json"
            $assignmentFileName = "$policyId`_assignment.json"

            $policyPathInRepo = if ($policy.PolicyTypeFull -eq "Compliance Policy") {
                Join-Path (Join-Path $Config.BaseRepoPath "backup/compliance") $policyFileName
            } else {
                Join-Path (Join-Path $Config.BaseRepoPath "backup/configuration") $policyFileName
            }

            $assignmentPathInRepo = Join-Path (Join-Path $Config.BaseRepoPath "backup/assignments") $assignmentFileName

            if (Test-Path (Join-Path $tempDir $policyPathInRepo)) {
                git add $policyPathInRepo
            }

            if (Test-Path (Join-Path $tempDir $assignmentPathInRepo)) {
                git add $assignmentPathInRepo
            }
        }

        # Check if commit was made
        $commitMade = $false
        git commit -m "Taken Backup for Policy Assignments for $(Get-Date -Format 'yyyy-MM-dd_HH-mm')" -q
        if ($LASTEXITCODE -ne 0) {
            # No changes to commit, do nothing
        } else {
            $commitMade = $true
            git push origin $Config.Branch -q
            if ($LASTEXITCODE -ne 0) {
                return $false
            }
        }


        if ($commitMade) {

            # Generate next global release version
            $existingTags = git tag --list "Release-v*" | Sort-Object {
                if ($_ -match "Release-v(\d+)\.(\d+)\.(\d+)$") {
                    [int]$matches[1] * 10000 + [int]$matches[2] * 100 + [int]$matches[3]
                } else {
                    0
                }
            }

            if ($existingTags.Count -eq 0) {
                $tagName = "Release-v1.0.0"
            } else {
                $latestTag = $existingTags[-1]
                if ($latestTag -match "Release-v(\d+)\.(\d+)\.(\d+)$") {
                    $major = [int]$matches[1]
                    $minor = [int]$matches[2]
                    $patch = [int]$matches[3] + 1
                    $tagName = "Release-v$major.$minor.$patch"
                } else {
                    
                    return $false
                }
            }

            git tag -a $tagName -m "Release $tagName"
            if ($LASTEXITCODE -ne 0) {
                
                return $false
            }

            git push origin $tagName -q
            if ($LASTEXITCODE -ne 0) {
                
                return $false
            }

            

            # Create GitHub release
            $headers = @{
                Authorization          = "Bearer $GitHubPAT"
                Accept                 = "application/vnd.github+json"
                "X-GitHub-Api-Version" = "2022-11-28"
            }

            if (-not $Config.RepoOwner -or -not $Config.RepoName) {
                throw [System.Exception]::new("Repository owner and name must be configured")
            }

            $repo = "$($Config.RepoOwner)/$($Config.RepoName)"
            $releaseTitle = "Release $tagName"
            $releaseNotes = "Automated release of policies under tag `$tagName`."
            $createReleaseUrl = "https://github.developer.allianz.io/api/v3/repos/$repo/releases"

            

            $releaseBody = @{
                tag_name   = $tagName
                name       = $releaseTitle
                body       = $releaseNotes
                draft      = $false
                prerelease = $false
            } | ConvertTo-Json -Depth 5

            try {
                $releaseResponse = Invoke-RestMethod -Uri $createReleaseUrl -Headers $headers -Method Post -Body $releaseBody
                
            }
            catch {
                
                return $false
            }

            # --- Upload only changed JSON files as release assets ---
            try {
                $changedFiles = git diff --name-only HEAD~1 HEAD | Where-Object { $_ -like "*.json" }
            } catch {
                
                $changedFiles = git show --name-only --pretty="" HEAD | Where-Object { $_ -like "*.json" }
            }

            if (-not $changedFiles -or $changedFiles.Count -eq 0) {
                
                $changedFiles = Get-ChildItem -Path $tempDir -Recurse -Filter "*.json" -File | Where-Object {
                    $_.DirectoryName -like "*compliance*" -or
                    $_.DirectoryName -like "*configuration*" -or
                    $_.DirectoryName -like "*assignments*"
                } | ForEach-Object {
                    $_.FullName.Replace("$tempDir\", "").Replace("$tempDir", "")
                }
            }
            
            # Use GitHub's provided upload URL template from the release response
            if ($releaseResponse.upload_url) {
                

                # Verify PAT token permissions by checking if we can access the repo
                try {
                    $testUrl = "https://github.developer.allianz.io/api/v3/repos/$($Config.RepoOwner)/$($Config.RepoName)"
                    $testResponse = Invoke-RestMethod -Uri $testUrl -Headers $headers -Method Get
                    
                }
                catch {
                    
                    
                }

                foreach ($relativePath in $changedFiles) {
                    $fullFilePath = Join-Path $tempDir $relativePath
                    if (-not (Test-Path $fullFilePath)) {
                        
                        continue
                    }

                    $fileName = [System.IO.Path]::GetFileName($fullFilePath)

                    # Use GitHub's upload URL template - replace the placeholder with filename
                    $uploadUrl = $releaseResponse.upload_url -replace "\{.*\}", "?name=$fileName"

                    try {
                        

                        $response = Invoke-RestMethod -Uri $uploadUrl -Headers @{
                            Authorization = "Bearer $GitHubPAT"
                            "Content-Type" = "application/octet-stream"
                        } -Method Post -InFile $fullFilePath

                        if ($response.browser_download_url) {
                            # Save the download URL to database
                            $downloadUrl = $response.browser_download_url
                            $policyIdFromFile = $fileName -replace '_assignment\.json$', '' -replace '\.json$', ''

                            try {
                                $connectionString = "Server=$($Config.Database.Server);Port=$($Config.Database.Port);Database=$($Config.Database.DatabaseName);Uid=$($Config.Database.Username);Pwd=$($Config.Database.Password);SslMode=Required;Charset=utf8mb4;"
                                [void][System.Reflection.Assembly]::LoadWithPartialName("MySql.Data")
                                $connection = New-Object MySql.Data.MySqlClient.MySqlConnection
                                $connection.ConnectionString = $connectionString
                                $connection.Open()

                                $updateQuery = "UPDATE policies SET GitPath = @GitPath WHERE PolicyGuid = @PolicyGuid"
                                $command = $connection.CreateCommand()
                                $command.CommandText = $updateQuery
                                $command.Parameters.AddWithValue("@GitPath", $downloadUrl) | Out-Null
                                $command.Parameters.AddWithValue("@PolicyGuid", $policyIdFromFile) | Out-Null
                                $command.ExecuteNonQuery() | Out-Null

                                $connection.Close()
                            } catch {
                                # Silently handle DB update failure
                            }
                        }

                    } catch {
                        
                    }
                }

            } else {
                
            }

        } # if $commitMade

    }
    catch {
        
        return $false
    }
    finally {
        Set-Location $originalLocation

        if (Test-Path $tempDir) {
            Remove-Item -Path $tempDir -Recurse -Force
        }
    }

    return $true
}