function Get-CloneGitRepo {
    param (
        [Parameter(Mandatory)][PSCustomObject]$Config
    )

    try {
        $GitHubPAT = $Config.GitHubPAT
        $ClonePath = $Config.ClonePath
        $RepoUrl = $Config.RepoUrl
        $Branch = $Config.Branch

        # Ensure the clone path exists
        if (-not (Test-Path -Path $ClonePath)) {
            Write-Host "Clone path does not exist. Creating: $ClonePath"
            New-Item -ItemType Directory -Path $ClonePath -Force | Out-Null
        }

        # Insert PAT into URL
        $RepoUrlWithPAT = $RepoUrl -replace "^https://", "https://$GitHubPAT@"

        Write-Host "Cloning repository using URL with PAT..." -ForegroundColor Cyan
        Write-Host $RepoUrlWithPAT

        # Execute Git clone
        git clone --branch $Branch $RepoUrlWithPAT $ClonePath -q

        # Verify clone
        if (-not (Test-Path -Path $ClonePath)) {
            throw "Failed to clone repository. Directory does not exist: $ClonePath"
        }

        Write-Host "Repository cloned successfully!" -ForegroundColor Green
    } catch {
        Write-Host "Error cloning GitHub repository: $_" -ForegroundColor Red
        throw
    }
}
