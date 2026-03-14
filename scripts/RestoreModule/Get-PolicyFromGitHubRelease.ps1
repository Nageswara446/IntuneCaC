function Get-PolicyFromGitHubRelease {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Owner,

        [Parameter(Mandatory = $true)]
        [string]$Repo,

        [Parameter(Mandatory = $true)]
        [string]$Tag,

        [Parameter(Mandatory = $true)]
        [string]$Token,   # Pass a valid GitHub token

        [Parameter(Mandatory = $true)]
        [string]$DownloadPath,

        [Parameter(Mandatory = $true)]
        [ValidateSet("ADT","Dev","Prod")]
        [string]$Environment,

        [Parameter(Mandatory = $true)]
        [string]$PolicyID
    )

    # Prepare headers
    $Headers = @{
        Authorization = "Bearer $Token"
        Accept        = "application/vnd.github+json"
    }

    function Write-Log {
        param (
            [string]$Message,
            [string]$Type = "INFO"
        )

        $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $color = switch ($Type.ToUpper()) {
            "SUCCESS" { "Green" }
            "ERROR"   { "Red" }
            "INFO"    { "Blue" }
            "WARN"    { "Yellow" }
            "DEBUG"   { "Cyan" }
            default   { "White" }
        }

        Write-Host "[$timestamp] [$Type] $Message" -ForegroundColor $color
    }

    # Define extraction folder
    $extractPath = Join-Path $DownloadPath "$Repo-$Tag"

    # Download & extract if not exists
    if (-not (Test-Path $extractPath)) {
        try {
            # Get release by tag
            $release = Invoke-RestMethod -Uri "https://github.developer.allianz.io/api/v3/repos/$Owner/$Repo/releases/tags/$Tag" -Headers $Headers -ErrorAction Stop
            Write-Log "Release found: $($release.name) (Tag: $($release.tag_name))" "SUCCESS"

            if ($release.assets.Count -gt 0) {
                Write-Log "Release assets found. Downloading all assets..." "INFO"
                foreach ($asset in $release.assets) {
                    $outputFile = Join-Path $DownloadPath $asset.name
                    try {
                        Write-Log "Downloading $($asset.name) to $outputFile..." "INFO"
                        Invoke-WebRequest -Uri $asset.browser_download_url -Headers $Headers -OutFile $outputFile -ErrorAction Stop
                        Write-Log "Downloaded $($asset.name)." "SUCCESS"
                    } catch {
                        Write-Log "Failed to download asset $($asset.name). Error: $($_.Exception.Message)" "ERROR"
                    }
                }
            } else {
                # Fallback to zip download
                $zipUrl    = "https://github.developer.allianz.io/api/v3/repos/$Owner/$Repo/zipball/$Tag"
                $outputZip = Join-Path $DownloadPath "$Repo-$Tag.zip"

                Write-Log "Downloading zip from $zipUrl to $outputZip..." "INFO"
                Invoke-WebRequest -Uri $zipUrl -Headers $Headers -OutFile $outputZip -ErrorAction Stop
                Write-Log "Repo zip downloaded successfully." "SUCCESS"

                try {
                    if (Test-Path $extractPath) { Remove-Item -Recurse -Force $extractPath }
                    Expand-Archive -Path $outputZip -DestinationPath $extractPath -Force
                    Write-Log "Repo zip extracted to $extractPath" "SUCCESS"

                    # Flatten nested folder if exists
                    $innerFolders = Get-ChildItem -Path $extractPath | Where-Object { $_.PSIsContainer }
                    if ($innerFolders.Count -eq 1) {
                        Write-Log "Flattening extraction folder structure..." "INFO"
                        $inner = $innerFolders[0].FullName
                        Get-ChildItem -Path $inner | ForEach-Object {
                            Move-Item -Path $_.FullName -Destination $extractPath -Force
                        }
                        Remove-Item -Recurse -Force $inner
                        Write-Log "Flattening complete." "SUCCESS"
                    }

                    Remove-Item $outputZip -Force
                    Write-Log "Deleted zip file $outputZip" "SUCCESS"
                } catch {
                    Write-Log "Failed to extract repo zip. Error: $($_.Exception.Message)" "ERROR"
                    return
                }
            }
        } catch {
            Write-Log "Failed to fetch release or download repo. Error: $($_.Exception.Message)" "ERROR"
            return
        }
    } else {
        Write-Log "Extract path already exists at $extractPath. Skipping download & extraction." "INFO"
    }

    # -------------------------------
    # Search for Policy JSON
    # -------------------------------
    try {
        $envFolder = Join-Path $extractPath "windows10orlater\$($Environment)_Tenant\backup"

        if (-not (Test-Path $envFolder)) {
            Write-Log "Backup folder for environment '$Environment' not found under $envFolder" "ERROR"
            return $null
        }

        $backupFolders = Get-ChildItem -Path $envFolder -Directory | Sort-Object Name -Descending
        if (-not $backupFolders) {
            Write-Log "No backup folders found under $envFolder" "ERROR"
            return $null
        }

        Write-Log "Found backup folders: $($backupFolders.Name -join ', ')" "INFO"

        $policyFound = $false
        $policyContent = $null

        foreach ($backup in $backupFolders) {
            $compliancePath    = Join-Path $backup.FullName "compliance"
            $configurationPath = Join-Path $backup.FullName "configuration"

            $pathsToCheck = @()
            if (Test-Path $compliancePath)    { $pathsToCheck += $compliancePath }
            if (Test-Path $configurationPath) { $pathsToCheck += $configurationPath }

            if (-not $pathsToCheck) {
                Write-Log "No compliance or configuration folders in backup: $($backup.FullName)" "WARN"
                continue
            }

            foreach ($path in $pathsToCheck) {
                $policyFile = Get-ChildItem -Path $path -Filter "$PolicyID.json" -File -ErrorAction SilentlyContinue
                if ($policyFile) {
                    Write-Log "Policy file found: $($policyFile.FullName)" "SUCCESS"
                    try {
                        $policyContent = Get-Content $policyFile.FullName -Raw
                        # Write-Host $policyContent
                        $policyFound = $true
                        # break 2  # Exit both loops
                        return $policyContent
                    } catch {
                        Write-Log "Failed to read policy file. Error: $($_.Exception.Message)" "ERROR"
                    }
                }
            }
        }

        if (-not $policyFound) {
            Write-Log "Policy file $PolicyID.json not found in any backup folder." "ERROR"
            return $null
        }
    } catch {
        Write-Log "Unexpected error while processing extracted content. Error: $($_.Exception.Message)" "ERROR"
        return $null
    }
}
