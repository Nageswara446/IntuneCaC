# Determine the root path (one level up from Rollback_Deletion_Module folder)
$moduleRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$commonPath = Join-Path $moduleRoot "..\Modules\Common" | Resolve-Path

# Import the required scripts
$commonScripts = @(
    "Get-DatabaseConnection.ps1",
    "Auth.ps1",
    "Get-IntunePolicyDetails.ps1"
)

foreach ($script in $commonScripts) {
    $fullPath = Join-Path $commonPath $script
    if (Test-Path $fullPath) {
        . $fullPath
        # Write-Output "Imported $script"
    }
    else {
        Write-Error "Required script $script not found at $fullPath"
    }
}

# Import Rollback Deletion Module Scripts
$requiredScripts = @(
    "Modules/Import-PolicyAssignment.ps1"
)

foreach ($script in $requiredScripts) {
    $fullPath = Join-Path $PSScriptRoot $script
    if (Test-Path $fullPath) {
        . $fullPath
        # Write-Output "Imported $script"
    }
    else {
        Write-Error "Required $script not found at $fullPath"
    }
}

function Set-ImportPolicyAssignment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Environment,  # ADT or Prod

        [Parameter(Mandatory = $true)]
        [string]$PolicyGitPath,  # GitHub path to policy folder containing JSON file

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkFlowID,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkFlowTaskID,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Destination,

        [Parameter(Mandatory = $false)]
        [PSCustomObject]$Configuration,

        [Parameter(Mandatory = $true)]
        [string]$PolicyId
    )

    try {
        # Step 1: Read credentials/config
	$configPath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath "..\Modules\Common\config.json")
        #$configPath = "C:\Users\HCL0733\OneDrive - Allianz\Desktop\WPS_INTUNE_CaC\scripts\Rollback_Deletion_Module\rollback-deletion-config.json"
        if (-not (Test-Path $configPath)) { throw "Config file not found at $configPath" }

        $jsonConfig = Get-Content -Raw -Path $configPath | ConvertFrom-Json

        # Save back
        $jsonConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath

        $config = $jsonConfig

        # Step 2: GitHub Configuration
        $repoOwner = $config.Git.repoOwner
        $repoName  = $config.Git.repoName
        $branch    = $config.Git.branch
        $gitPAT    = $config.Git.GitPAT

        if (-not $gitPAT -or $gitPAT -eq "") {
            Write-Error "Git Personal Access Token (GitPAT) is missing in config.json under Git.GitPAT"
            return
        }

        # Step 3: Process Policy Git Path
        # Convert backslashes to forward slashes for GitHub API
        $currentPolicyGitPath = $PolicyGitPath -replace '\\', '/'

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
            $statusCode = $_.Exception.Response.StatusCode.value__
            if ($statusCode -eq 404) {
                $errorResult = [PSCustomObject]@{
                    Success      = $false
                    Response     = $null
                    ErrorMessage = "Assignment not found"
                }
                return $errorResult
            } else {
                $errorResult = [PSCustomObject]@{
                    Success      = $false
                    Response     = $null
                    ErrorMessage = "Failed to fetch folder contents from GitHub for path $currentPolicyGitPath : $($_.Exception.Message)"
                }
                return $errorResult
            }
        }

        # ---------- Find JSON file ----------
        $jsonFile = $folderContents | Where-Object { $_.name -match '\.json$' } | Select-Object -First 1
        # Write-Host "*************"$jsonFile
        if (-not $jsonFile) {
            $errorResult = [PSCustomObject]@{
                Success      = $false
                Response     = $null
                ErrorMessage = "Assignment not found"
            }
            return $errorResult
        }

        # ---------- Download JSON file content ----------
        try {
            $rawUrl = $jsonFile.download_url
            # Remove token from URL if present
            $rawUrl = $rawUrl.Split('?')[0]
            $policyJsonText = Invoke-RestMethod -Uri $rawUrl -Headers $headers -ErrorAction Stop
            # Write-Host "Raw response length: $($policyJsonText.Length)" -ForegroundColor Green
            # Write-Host "First 1000 chars of raw response: $($policyJsonText.Substring(0, [Math]::Min(1000, $policyJsonText.Length)))" -ForegroundColor Blue
            # Remove BOM if present
            $policyJsonText = $policyJsonText.TrimStart([char]0xFEFF)
            # Write-Host "After BOM removal, first 100 chars: $($policyJsonText.Substring(0, [Math]::Min(100, $policyJsonText.Length)))" -ForegroundColor Cyan
            $policyJson = $policyJsonText | ConvertFrom-Json

        }
        catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            if ($statusCode -eq 404) {
                $errorResult = [PSCustomObject]@{
                    Success      = $false
                    Response     = $null
                    ErrorMessage = "Assignment not found"
                }
                return $errorResult
            } else {
                $errorResult = [PSCustomObject]@{
                    Success      = $false
                    Response     = $null
                    ErrorMessage = "Failed to fetch or parse assignment JSON from GitHub for path $currentPolicyGitPath : $($_.Exception.Message)"
                }
                return $errorResult
            }
        }
        # Step 4: Authenticate
        $AccessToken = Get-AccessToken -Environment $Environment -Config $config
        if (-not $AccessToken) { throw "Authentication failed." }

        # Step 5: Connect to DB (might not be needed for assignment, but keeping for consistency)
        $connection = Get-DatabaseConnection -Config $config
        if (-not $connection) { throw "DB Connection failed." }

        $Headers = @{
            "Authorization" = "Bearer $AccessToken"
            "Content-Type"  = "application/json"
        }

        # Call assignment function
        $AssignmentOutput = Import-PolicyAssignmentToIntune -policyJson $policyJson -Token $AccessToken -Config $config -WorkFlowID $WorkFlowID -WorkFlowTaskID $WorkFlowTaskID -Destination $Destination -PolicyID $PolicyId -Environment $Environment 

        Write-Output $AssignmentOutput.Response

        return $AssignmentOutput

    }
    catch {
        Write-Error "Error during assignment: $_"
        $errorResult = [PSCustomObject]@{
            Success      = $false
            Response     = $null
            ErrorMessage = "Error during assignment: $_"
        }
        return $errorResult
    }
}

# Export the function
Export-ModuleMember -Function Set-ImportPolicyAssignment