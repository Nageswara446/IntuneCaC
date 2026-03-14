function Get-BackupPolicyJson {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateSet("ADT", "Prod", "Dev")]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$BackupPath
    )

    $result = @()

    # ---------- Load Configuration ----------
    try {
        $configPath = "C:\URM\WPS_INTUNE_CaC\scripts\Rollback_Deletion_Module\rollback-deletion-config.json"
        if (-not (Test-Path $configPath)) {
            throw "Missing config file at $configPath"
        }

        $Config = Get-Content -Raw -Path $configPath | ConvertFrom-Json
    }
    catch {
        Write-Error "Failed to load configuration: $($_.Exception.Message)"
        return $null
    }

    # ---------- GitHub Configuration ----------
    $repoOwner = $Config.Git.repoOwner
    $repoName  = $Config.Git.repoName
    $branch    = $Config.Git.branch
    $gitPAT    = $Config.Git.GitPAT

    if (-not $gitPAT -or $gitPAT -eq "") {
        Write-Error "Git Personal Access Token (GitPAT) is missing in config.json under Git.GitPAT"
        return $null
    }

    # Split BackupPath by comma and process each path
    $policyPaths = $BackupPath -split ',' | ForEach-Object { $_.Trim() }

    # Process each policy path
    foreach ($currentPolicyGitPath in $policyPaths) {
        # Convert backslashes to forward slashes for GitHub API
        $currentPolicyGitPath = $currentPolicyGitPath -replace '\\', '/'

        # ---------- Construct GitHub API URL to list contents ----------
        $apiUrl = 'https://github.developer.allianz.io/api/v3/repos/' + $repoOwner + '/' + $repoName + '/contents/' + $currentPolicyGitPath + '?ref=' + $branch

        $headers = @{
            "Authorization" = "Bearer $gitPAT"
            "User-Agent"    = "PowerShellScript"
            "Accept"        = "application/vnd.github+json"
        }

        try {
            $folderContents = Invoke-RestMethod -Uri $apiUrl -Headers $headers -ErrorAction Stop
        }
        catch {
            Write-Error "Failed to fetch folder contents from GitHub for path $currentPolicyGitPath : $($_.Exception.Message)"
            continue
        }

        # ---------- Find JSON file ----------
        $jsonFile = $folderContents | Where-Object { $_.name -match '\.json$' } | Select-Object -First 1

        if (-not $jsonFile) {
            Write-Error "No JSON file found in the specified GitHub folder: $currentPolicyGitPath"
            continue
        }

        # ---------- Download JSON file content ----------
        try {
            $rawUrl = $jsonFile.download_url
            $rawUrl = $rawUrl.Split('?')[0]

            $policyJsonText = Invoke-RestMethod -Uri $rawUrl -Headers $headers -ErrorAction Stop

            # Remove BOM if present
            $policyJsonText = $policyJsonText.TrimStart([char]0xFEFF)

            $policyJson = $policyJsonText | ConvertFrom-Json

            # Add to result array
            $result += $policyJson
        }
        catch {
            Write-Error "Failed to fetch or parse policy JSON from GitHub for path $currentPolicyGitPath : $($_.Exception.Message)"
            continue
        }
    }

    return $result
}

Export-ModuleMember -Function Get-BackupPolicyJson