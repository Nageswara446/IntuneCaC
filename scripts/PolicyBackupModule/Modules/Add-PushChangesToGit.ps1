function Add-PushChangesToGit {
    param (
        [Parameter(Mandatory = $true)]
        [string]$RepoPath,

        [Parameter(Mandatory = $true)]
        [string]$BranchName,

        [Parameter(Mandatory = $true)]
        [string]$GitPAT,

        [Parameter(Mandatory = $false)]
        [string]$CommitMessage = "Backup and copy policies",

        [Parameter(Mandatory = $true)]
        [string]$GitPolicyBackUpPath
    )

    if (-Not $RepoPath) {
        # Write-Output "Repository path is required." -ForegroundColor Red
        return [PSCustomObject]@{
            Success = $false
            Message = "Repository path is required."
        }
    }
    if (-Not $BranchName) {
        # Write-Output "Branch name is required." -ForegroundColor Red
        return [PSCustomObject]@{
            Success = $false
            Message = "Branch name is required."
        }
    }

    try {
        Push-Location -Path $RepoPath

        # Check for uncommitted changes inside backup path
        $Status = git status --porcelain -- $GitPolicyBackUpPath
        if (-not $Status) {
            # Write-Output "No changes to commit under $GitPolicyBackUpPath." -ForegroundColor Yellow
            return [PSCustomObject]@{
                Success = $true
                ChangesCommitted = $false
                BranchName = $BranchName
                RepoPath = $RepoPath
                Message = "No changes to commit under $GitPolicyBackUpPath."
            }
        }

        # Stage only files under the backup path
        git add "$GitPolicyBackUpPath/*"

        git commit -m $CommitMessage

        # Configure temporary remote URL with PAT
        $OriginalUrl = git remote get-url origin
        #$RemoteWithPAT = $OriginalUrl -replace 'https://', "https://$GitPAT@"
        
        git remote set-url origin $OriginalUrl
        git push origin $BranchName
        # Write-Output "Changes pushed to $BranchName successfully." -ForegroundColor Green

        # Restore original remote URL
        # git remote set-url origin $OriginalUrl

        return [PSCustomObject]@{
            Success = $true
            ChangesCommitted = $true
            BranchName = $BranchName
            RepoPath = $RepoPath
            CommitMessage = $CommitMessage
            Message = "Changes pushed successfully."
        }
    }
    catch {
        # Write-Output "Error during commit and push: $_" -ForegroundColor Red
        return [PSCustomObject]@{
            Success = $false
            ChangesCommitted = $false
            BranchName = $BranchName
            RepoPath = $RepoPath
            Message = "Error during commit and push: $_"
        }
    }
    finally {
        Pop-Location
    }
}
