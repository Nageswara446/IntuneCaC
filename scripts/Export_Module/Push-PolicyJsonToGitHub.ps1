function Push-PolicyJsonToGitHub {
    param (
        [Parameter(Mandatory = $true)][string]$GitHubPAT,
        [Parameter(Mandatory = $true)][array]$Policies,
        [Parameter(Mandatory = $true)][string]$BaseExportPath,
        [Parameter(Mandatory = $true)][string]$AssignmentsPath,
        [Parameter(Mandatory = $true)][PSCustomObject]$Config,
        [Parameter(Mandatory = $true)][string]$changeId,
        [Parameter(Mandatory = $true)][string]$WorkFlowID,
        [Parameter(Mandatory = $true)][string]$WorkFlowTaskID
    )

    if (-not $Policies) { return $false }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $false }

    $tempDir = $Config.TempDir
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

    try {
        $repoUrlWithAuth = $Config.RepoUrl -replace "https://", "https://$GitHubPAT@"
        git clone --branch $Config.Branch $repoUrlWithAuth $tempDir -q
        if ($LASTEXITCODE -ne 0) { return $false }

        $compliancePath      = Join-Path $tempDir (Join-Path $Config.BaseRepoPath "compliance")
        $configurationPath   = Join-Path $tempDir (Join-Path $Config.BaseRepoPath "configuration")
        $assignmentsPathRepo = Join-Path $tempDir (Join-Path $Config.BaseRepoPath "assignments")

        New-Item -ItemType Directory -Path $compliancePath -Force | Out-Null
        New-Item -ItemType Directory -Path $configurationPath -Force | Out-Null
        New-Item -ItemType Directory -Path $assignmentsPathRepo -Force | Out-Null

        foreach ($policy in $Policies) {
            $policyId = $policy.PolicyId
            $policyFileName = "$policyId.json"
            $assignmentFileName = "$policyId`_assignment.json"

            $policyFile = Join-Path $BaseExportPath $policyFileName
            $assignmentFile = Join-Path $AssignmentsPath $assignmentFileName

            $targetPolicyPath = if ($policy.PolicyTypeFull -eq "Compliance Policy") { $compliancePath } else { $configurationPath }

            if (Test-Path $policyFile) {
                $content = Get-Content -Raw -LiteralPath $policyFile
                Set-Content -LiteralPath (Join-Path $targetPolicyPath $policyFileName) -Value $content -Encoding UTF8
                # Write-Host "Copied policy file: $policyFile to $targetPolicyPath\$policyFileName"
            } else {
                # Write-Host "Policy file not found: $policyFile"
            }

            if (Test-Path $assignmentFile) {
                $content = Get-Content -Raw -LiteralPath $assignmentFile
                Set-Content -LiteralPath (Join-Path $assignmentsPathRepo $assignmentFileName) -Value $content -Encoding UTF8
                # Write-Host "Copied assignment file: $assignmentFile to $assignmentsPathRepo\$assignmentFileName"
            } else {
                # Write-Host "Assignment file not found: $assignmentFile"
            }
        }

        Set-Location $tempDir
        # Write-Host "Changed directory to: $tempDir"

        # Debug: check git status before staging
        $statusBefore = git status --porcelain
        # Write-Host "Git status before staging:`n$statusBefore"

        # Stage all changes including new files
        git add -A

        # Also try --renormalize for line ending normalization
        git add --renormalize .

        # Debug: check staged files
        $stagedFiles = git diff --cached --name-status
        # Write-Host "Staged files:`n$stagedFiles"

        # Debug: check git status after staging
        $statusAfter = git status --porcelain
        # Write-Host "Git status after staging:`n$statusAfter"

        # Debug: check if there are any differences in tracked files
        $diffFiles = git diff --name-only
        # Write-Host "Files with uncommitted changes:`n$diffFiles"

        # Configure Git user if missing
        if (-not (git config user.name)) { git config user.name "WPS INTUNE CaC" }
        if (-not (git config user.email)) { git config user.email "wps-intune-cac@allianz.com" }

        # Commit with --allow-empty to force commit even if Git thinks nothing changed
        $groups = $Policies | Group-Object PolicyTypeFull
        $policyTypeStr = if ($groups.Count -eq 1) { $groups[0].Name } else { "policy" }
        git commit -m "Export $policyTypeStr | $changeId"
        # git commit -m "Exported policy with $changeId"
        if ($LASTEXITCODE -ne 0) { 
            # Write-Host "Commit failed.";
            return $false }

        git push origin $Config.Branch -q
        if ($LASTEXITCODE -ne 0) {
            # Write-Host "Push failed.";
            return $false }

        # Handle tagging
        $existingTags = git tag --list "Release-v*" | Sort-Object {
            if ($_ -match "Release-v(\d+)\.(\d+)\.(\d+)$") {
                [int]$matches[1]*10000 + [int]$matches[2]*100 + [int]$matches[3]
            } else { 0 }
        }
        if ($existingTags.Count -eq 0) { $tagName = "Release-v1.0.0" }
        else {
            $latestTag = $existingTags[-1]
            if ($latestTag -match "Release-v(\d+)\.(\d+)\.(\d+)$") {
                $major=[int]$matches[1]; $minor=[int]$matches[2]; $patch=[int]$matches[3]+1
                $tagName="Release-v$major.$minor.$patch"
            } else { return $false }
        }

        git tag -a $tagName -m "Release $tagName"
        if ($LASTEXITCODE -ne 0) { return $false }
        git push origin $tagName -q
        if ($LASTEXITCODE -ne 0) { return $false }

        # Create GitHub release
        $headers = @{
            Authorization          = "Bearer $GitHubPAT"
            Accept                 = "application/vnd.github+json"
            "X-GitHub-Api-Version" = "2022-11-28"
        }
        if (-not $Config.RepoOwner -or -not $Config.RepoName) { throw "Repo owner and name must be set" }
        $repo = "$($Config.RepoOwner)/$($Config.RepoName)"
        $releaseBody = @{
            tag_name   = $tagName
            name       = "Release $tagName"
            body       = "Automated release of policies under tag `$tagName`."
            draft      = $false
            prerelease = $false
        } | ConvertTo-Json -Depth 5

        try { $releaseResponse = Invoke-RestMethod -Uri "https://github.developer.allianz.io/api/v3/repos/$repo/releases" -Headers $headers -Method Post -Body $releaseBody }
        catch { 
            # Write-Host "GitHub release creation failed";
            return $false }

        # Upload changed JSON files as release assets
        $changedFiles = git diff --name-only HEAD~1 HEAD | Where-Object { $_ -like "*.json" }
        if (-not $changedFiles) { $changedFiles = git show --name-only --pretty="" HEAD | Where-Object { $_ -like "*.json" } }

        if ($releaseResponse.upload_url) {
            foreach ($relativePath in $changedFiles) {
                $fullFilePath = Join-Path $tempDir $relativePath
                if (-not (Test-Path $fullFilePath)) { continue }
                $fileName = [System.IO.Path]::GetFileName($fullFilePath)
                $uploadUrl = $releaseResponse.upload_url -replace "\{.*\}", "?name=$fileName"
                try {
                    $uploadResponse = Invoke-RestMethod -Uri $uploadUrl -Headers @{ Authorization="Bearer $GitHubPAT"; "Content-Type"="application/octet-stream" } -Method Post -InFile $fullFilePath
                    if ($uploadResponse.browser_download_url) {
                        # Save the download URL to database
                        $downloadUrl = $uploadResponse.browser_download_url
                        $policyIdFromFile = $fileName -replace '_assignment\.json$', '' -replace '\.json$', ''

                        try {
                            $connectionString = "Server=$($Config.Database.Server);Port=$($Config.Database.Port);Database=$($Config.Database.DatabaseName);Uid=$($Config.Database.Username);Pwd=$($Config.Database.Password);SslMode=Required;Charset=utf8mb4;"
                            [void][System.Reflection.Assembly]::LoadWithPartialName("MySql.Data")
                            $connection = New-Object MySql.Data.MySqlClient.MySqlConnection
                            $connection.ConnectionString = $connectionString
                            $connection.Open()

                            $updateQuery = "UPDATE policies SET GitPath = @GitPath WHERE PolicyGuid = @PolicyGuid AND WorkflowID = @WorkFlowID AND XLRTaskID = @XLRTaskID"
                            $command = $connection.CreateCommand()
                            $command.CommandText = $updateQuery
                            $command.Parameters.AddWithValue("@GitPath", $downloadUrl) | Out-Null
                            $command.Parameters.AddWithValue("@PolicyGuid", $policyIdFromFile) | Out-Null
                            $command.Parameters.AddWithValue("@WorkflowID", $WorkFlowID) | Out-Null
                            $command.Parameters.AddWithValue("@XLRTaskID", $WorkFlowTaskID) | Out-Null
                            $command.ExecuteNonQuery() | Out-Null

                            $connection.Close()
                        } catch {
                            # Silently handle DB update failure
                        }
                    }
                } catch { 
                    # Write-Host "Failed to upload $fileName";
                    continue }
            }
        }

    }
    catch { 
        # Write-Host "Error: $_";
        return $false }
    finally {
        if (Test-Path $tempDir) {
            if ($PSScriptRoot) { Set-Location $PSScriptRoot } else { Set-Location (Get-Location).Path }
            Remove-Item -Path $tempDir -Recurse -Force
        }
    }

    return $true
}
