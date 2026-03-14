function Get-AllPolicyJsons {
    param(
        [Parameter(Mandatory)][string[]]$GitPaths,
        [Parameter(Mandatory)][PSCustomObject]$Config,
        [string]$DownloadFolder = "C:\URM\html-reports"
    )

    # Ensure download directory exists
    if (-not (Test-Path $DownloadFolder)) {
        New-Item -Path $DownloadFolder -ItemType Directory | Out-Null
    }

    $results = @()

    foreach ($gitpath in $GitPaths) {
        Write-Host "`nProcessing: $gitpath" -ForegroundColor Cyan

        $result = [PSCustomObject]@{
            GitPath      = $gitpath
            PolicyGuid   = $null
            ReleaseTag   = $null
            RawJson      = $null
            Success      = $false
            ErrorMessage = ""
            ReleaseURL   = ""
        }

        try {
            # --- Extract release tag and policy GUID ---
            if ($gitpath -match 'releases/download/(Release-[^/]+)/') {
                $result.ReleaseTag = $matches[1]
            } else {
                throw "Release tag not found in Git path: $gitpath"
            }

            if ($gitpath -match '/([0-9a-fA-F\-]{36})\.json$') {
                $result.PolicyGuid = $matches[1]
            } else {
                throw "Policy GUID not found in Git path: $gitpath"
            }

            # --- Prepare GitHub API URLs ---
            $Token        = $Config.Git.GitPAT
            $RepoOwner    = $Config.Git.repoOwner
            $RepoName     = $Config.Git.repoName
            $GitReleaseURL = $Config.Git.ReleaseUrl
            $GitAssetReleaseURL = $Config.Git.ReleaseAssetUrl
            $ReleaseTag   = $result.ReleaseTag
            $AssetName    = "$($result.PolicyGuid).json"

            $releaseApiUrl = $GitReleaseURL.Replace("{RepoOwner}", $RepoOwner).Replace("{RepoName}", $RepoName).Replace("{TagName}", $ReleaseTag)

            $headers = @{
                Authorization = "token $Token"
                Accept        = "application/json"
                "User-Agent"  = "PowerShellScript/1.0"
            }

            Write-Host "Fetching release info for tag: $ReleaseTag" -ForegroundColor Yellow
            Write-Host $releaseApiUrl
            # --- Get release info ---
            $release = Invoke-RestMethod -Uri $releaseApiUrl -Headers $headers -ErrorAction Stop

            if (-not $release.assets) {
                throw "No assets found in release: $ReleaseTag"
            }

            $asset = $release.assets | Where-Object { $_.name -eq $AssetName }
            if (-not $asset) {
                throw "Asset not found for policy: $($result.PolicyGuid)"
            }

            $assetId = $asset.id
            $assetApiUrl = $GitAssetReleaseURL.Replace("{RepoOwner}", $RepoOwner).Replace("{RepoName}", $RepoName).Replace("{assetId}", $assetId)

            # --- Download asset ---
            $downloadHeaders = @{
                Authorization = "token $Token"
                Accept        = "application/octet-stream"
                "User-Agent"  = "PowerShellScript/1.0"
            }

            $outputFile = Join-Path -Path $DownloadFolder -ChildPath $AssetName
            Write-Host "Downloading $AssetName ..." -ForegroundColor Green

            Invoke-WebRequest -Uri $assetApiUrl -Headers $downloadHeaders -OutFile $outputFile -ErrorAction Stop

            # --- Parse JSON ---
            $rawJsonString = Get-Content -Path $outputFile -Raw
            $policyJson = $rawJsonString | ConvertFrom-Json

            $result.RawJson = $policyJson
            $result.Success = $true
            $result.ReleaseURL = $releaseApiUrl
        }
        catch {
            $err = $_.Exception.Message
            $result.ErrorMessage = $err
            Write-Warning "Failed to fetch JSON for $($result.GitPath): $err"
        }

        $results += $result
    }

    return $results
}
