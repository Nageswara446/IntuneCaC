function Import-Policy {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateSet("ADT", "Prod", "Dev")]
        [string]$Destination,

        [Parameter(Mandatory)]
        [string]$Action,

        [Parameter(Mandatory)]
        [string]$PolicyGitPath,   # Comma-separated paths inside GitHub repo (e.g. "windows10orlater\ADT_Tenant\backup\14-Oct-2025_07-20-39_Releasea7581d06ad114115bf8a9a0a0caf4d30\configuration,windows10orlater\ADT_Tenant\backup\14-Oct-2025_07-20-39_Releasea7581d06ad114115bf8a9a0a0caf4d30\configuration")

        [Parameter(Mandatory)]
        [string]$WorkFlowID,

        [Parameter(Mandatory)]
        [string]$WorkFlowTaskID
    )
     # ---------- Load Configuration ----------
        try {
            $configPath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath "..\Modules\Common\config.json")
            # $configPath = "C:\Users\HCL0733\OneDrive - Allianz\Desktop\WPS_INTUNE_CaC\scripts\Rollback_Deletion_Module\rollback-deletion-config.json"
            if (-not (Test-Path $configPath)) {
                throw "Missing config file at $configPath"
            }

            $Config = Get-Content -Raw -Path $configPath | ConvertFrom-Json
        }
        catch {
            Write-Error "Failed to load configuration: $($_.Exception.Message)"
            return
        }

        # ---------- Load Modules ----------
        . "$PSScriptRoot\Modules\Auth.ps1"
        . "$PSScriptRoot\Modules\Import-Policy.ps1"

        # ---------- GitHub Configuration ----------
        $repoOwner = $Config.Git.repoOwner
        $repoName  = $Config.Git.repoName
        $branch    = $Config.Git.branch
        $gitPAT    = $Config.Git.GitPAT

        if (-not $gitPAT -or $gitPAT -eq "") {
            Write-Error "Git Personal Access Token (GitPAT) is missing in config.json under Git.GitPAT"
            return
        }

        # Split PolicyGitPath by comma and process each path
        $policyPaths = $PolicyGitPath -split ',' | ForEach-Object { $_.Trim() }
        # Write-Host "Processing $($policyPaths.Count) policy paths:" -ForegroundColor Cyan
        foreach ($path in $policyPaths) {
            # Write-Host "  - $path" -ForegroundColor Yellow
        }

        # Process each policy path
        foreach ($currentPolicyGitPath in $policyPaths) {
            # Write-Host "`n--- Processing Policy Path: $currentPolicyGitPath ---" -ForegroundColor Magenta

            # Convert backslashes to forward slashes for GitHub API
            $currentPolicyGitPath = $currentPolicyGitPath -replace '\\', '/'

            # ---------- Construct GitHub API URL to list contents ----------
            $apiUrl = 'https://github.developer.allianz.io/api/v3/repos/' + $repoOwner + '/' + $repoName + '/contents/' + $currentPolicyGitPath + '?ref=' + $branch

            $headers = @{
                "Authorization" = "Bearer $gitPAT"
                "User-Agent"    = "PowerShellScript"
                "Accept"        = "application/vnd.github+json"
            }

            # Write-Host "Listing files in GitHub folder: $currentPolicyGitPath" -ForegroundColor Cyan
            # Write-Host "API URL: $apiUrl" -ForegroundColor Yellow

            try {
                # Write-Host "Fetching folder contents..." -ForegroundColor Cyan
                $folderContents = Invoke-RestMethod -Uri $apiUrl -Headers $headers -ErrorAction Stop
                # Write-Host "Folder contents response length: $($folderContents.Length)" -ForegroundColor Green
            }
            catch {
                Write-Error "Failed to fetch folder contents from GitHub for path $currentPolicyGitPath : $($_.Exception.Message)"
                # Write-Host "Full exception: $($_.Exception | Out-String)" -ForegroundColor Red
                continue  # Continue to next path instead of returning
            }

            # ---------- Find JSON file ----------
            $jsonFile = $folderContents | Where-Object { $_.name -match '\.json$' } | Select-Object -First 1

            if (-not $jsonFile) {
                Write-Error "No JSON file found in the specified GitHub folder: $currentPolicyGitPath"
                # Write-Host "Available files: $($folderContents | ForEach-Object { $_.name })" -ForegroundColor Yellow
                continue  # Continue to next path
            }

            # Extract BasePolicyID from JSON file name (remove .json extension)
            $BasePolicyID = $jsonFile.name -replace '\.json$', ''

            # Write-Host "Found JSON file: $($jsonFile.name)" -ForegroundColor Green
            # Write-Host "BasePolicyID: $BasePolicyID" -ForegroundColor Green

            # ---------- Download JSON file content ----------
            try {
                $rawUrl = $jsonFile.download_url
                # Remove token from URL if present
                $rawUrl = $rawUrl.Split('?')[0]

                # Write-Host "Raw URL: $rawUrl" -ForegroundColor Yellow
                # Fetch raw JSON directly
                # Write-Host "Fetching raw JSON content..." -ForegroundColor Cyan
                $policyJsonText = Invoke-RestMethod -Uri $rawUrl -Headers $headers -ErrorAction Stop
                # $jsonFile = "C:\Users\HCL0733\OneDrive - Allianz\Desktop\WPS_INTUNE_CaC\scripts\Export_Module\PolicyExport_20251106171052\9adb3137-cb8b-4485-8acf-69b504c3992f.json"
                # $policyJsonText = Get-Content -Raw -Path $jsonFile
                # Write-Host "Raw response length: $($policyJsonText.Length)" -ForegroundColor Green
                # Write-Host "First 1000 chars of raw response: $($policyJsonText.Substring(0, [Math]::Min(1000, $policyJsonText.Length)))" -ForegroundColor Blue
                # Remove BOM if present
                $policyJsonText = $policyJsonText.TrimStart([char]0xFEFF)
                # Write-Host "After BOM removal, first 100 chars: $($policyJsonText.Substring(0, [Math]::Min(100, $policyJsonText.Length)))" -ForegroundColor Cyan
                $policyJson = $policyJsonText | ConvertFrom-Json

                # Extract roleScopeTagIds array into ScopeTagsArray

                $roleScopeTagIds = $policyJson.roleScopeTagIds
                # Handle array properly
                if ($roleScopeTagIds -is [System.Array]) {
                    $roleScopeTagIdsString = $roleScopeTagIds -join ", "
                } else {
                    $roleScopeTagIdsString = $roleScopeTagIds
                }
                $scopetags = "@{Success=True;ScopeTags=$roleScopeTagIdsString;ErrorMessage=$null}"
            }
            catch {
                Write-Error "Failed to fetch or parse policy JSON from GitHub for path $currentPolicyGitPath : $($_.Exception.Message)"
                continue  # Continue to next path
            }

        # ---------- Update Policy Metadata ----------
        try {
            if ($policyJson.displayName -and (-not $policyJson.displayName.StartsWith("CaC-"))) {
                $policyJson.displayName = "CaC-$($policyJson.displayName)"
            }
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
            $policyJson | Add-Member -MemberType NoteProperty -Name 'description' -Value "Imported via automated workflow. XL Release ID: $WorkFlowID" -Force
        }
        catch {
            Write-Warning "Failed to update displayName/description fields: $($_.Exception.Message)"
        }

        # ---------- Authenticate ----------
        # Write-Host "Authenticating to $Destination..." -ForegroundColor Cyan
        try {
            $tokenIntune = Get-AccessToken -Environment $Destination -Config $Config
        }
        catch {
            Write-Error "Authentication failed: $($_.Exception.Message)"
            return
        }

            # ---------- Import Policy ----------
            # Write-Host "Importing policy into Intune..." -ForegroundColor Green
            try {
                $response = Import-PolicyToIntune `
                    -Action "Create New Policy" `
                    -PolicyJson $policyJson `
                    -Token $tokenIntune `
                    -Config $Config `
                    -WorkFlowID $WorkFlowID `
                    -WorkFlowTaskID $WorkFlowTaskID `
                    -Destination $Destination `
                    -PolicyName $ProdPolicyName `
                    -Source "GitHub" `
                    -ScopeTags $scopetags `
                    -GitPath $currentPolicyGitPath

                if ($response.Success) {
                    Write-Host "Policy imported successfully!" 
                    Write-Host "Backup Path: $($currentPolicyGitPath)" 
                    Write-Host "Policy Name: $($response.Response.policyname)"
                    Write-Host "Policy Type: $($response.Response.policytype)"
                    Write-Host "Policy ID:   $($response.Response.id)"
                    Write-Host "Base ID:     $($BasePolicyID)"
                    Write-Host "-----------------"
                }
                else {
                    Write-Host " Import failed: $($response.ErrorMessage)" -ForegroundColor Red
                }
            }
            catch {
                Write-Error "Error during import process for path $currentPolicyGitPath : $($_.Exception.Message)"
            }

            # Write-Host "`n---- Completed processing for: $currentPolicyGitPath ----" -ForegroundColor Cyan
        }

        # Write-Host "`n---- All Import Processes Completed ----" -ForegroundColor Cyan
    }

Export-ModuleMember -Function Import-Policy