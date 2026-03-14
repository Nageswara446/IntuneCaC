# Determine the root path (one level up from RestoreModule folder)
$moduleRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$commonPath = Join-Path $moduleRoot "..\Modules\Common" | Resolve-Path

# Import the required scripts
$commonScripts = @(
    "Get-DatabaseConnection.ps1",
    "Add-RollbackRequest.ps1",
    "Auth.ps1"
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
function Set-IntunePolicyAssignment {
<#
.SYNOPSIS
    Assigns Intune policy assignments (Compliance or Configuration) via Graph API.

.PARAMETER Environment
    The environment to use (ADT or Prod).

.PARAMETER PolicyId
    The ID (GUID) of the Intune Policy.

.PARAMETER PolicyType
    The type of policy: "compliance" or "configuration".

.PARAMETER AssignmentsJson
    Path to a JSON file or JSON string with an array of assignment objects.
    Example assignment object:
    [
      {
        "target": {
          "@odata.type": "#microsoft.graph.groupAssignmentTarget",
          "groupId": "00000000-0000-0000-0000-000000000000"
        }
      }
    ]
#>
    param(
        [Parameter(Mandatory)][PSCustomObject]$Configuration,
        [Parameter(Mandatory)][string]$RollbackData
    )

    # Path to your JSON config file
    $configPath = "$PSScriptRoot\config.json"

    if (-not (Test-Path $configPath)) {
        Write-Output "Missing config file at $configPath"
        exit 1
    }
    $Config = Get-Content -Raw -Path $configPath | ConvertFrom-Json

    # Split into lines and trim whitespace
    $lines = $rollbackData -split "`n" | ForEach-Object { $_.Trim() }

    # Now extract the line containing 'Exists'
    $existsLine = $lines | Where-Object { $_ -match '^Exists\s*:' }

    # Step 2: Remove the leading "Exists :"
    $existsData = $existsLine -replace '^Exists\s*:\s*', ''

    # Step 3: Split on ';' to get each pair (ignore empty entries)
    $pairs = $existsData -split ';' | Where-Object { $_.Trim() -ne '' }
    foreach ($pair in $pairs) {
        $parts = $pair -split '\s* - \s*'  # Split on " - " with optional surrounding spaces
        # Write-Host $parts
        # exit 1
        if ($parts.Length -eq 6) {
            $PolicyGuid = $parts[0].Trim()
            $AssignmentsJson = $parts[1].Trim()
            $Env = $parts[2].Trim()
            $PolicyType = $parts[3].Trim()
            $Rollback_workflowid = $parts[4].Trim()
            $Release_git = $parts[4].Trim()
            
            # ===== Authenticate with Graph API =====
            Write-Host "Fetching Graph Access Token..."
            $AccessToken = Get-AccessToken -Environment "ADT" -Config $Config
            
            if (-not $AccessToken) {
                Write-Host "Failed to acquire Graph API token. Make sure you are connected using Connect-MgGraph."
            }
            # ===== Determine URL =====
            switch ($PolicyType) {
                "Compliance Policy" {
                    $graphUrl = "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies/$PolicyGuid/assign"
                }
                "Configuration Policy" {
                    try {
                        $null = Invoke-RestMethod -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$PolicyGuid" -Headers @{Authorization = "Bearer $AccessToken"} -ErrorAction Stop
                        $graphUrl = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$PolicyGuid/assign"
                    } catch {
                        $graphUrl = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$PolicyGuid/assign"
                    }
                }
            }

            Write-Host "Graph URL: $graphUrl"

            # ===== Load Assignments =====
            if (Test-Path $AssignmentsJson) {
                $assignments = Get-Content -Raw -Path $AssignmentsJson | ConvertFrom-Json
            } else {
                $assignments = $AssignmentsJson | ConvertFrom-Json
            }

            if (-not $assignments) {
                # throw "Assignments JSON is empty or invalid."
            }

            # Clean assignments (strip id/source/etc.)
            $cleanAssignments = foreach ($a in $assignments) {
                [PSCustomObject]@{
                    target = $a.target
                }
            }

            $body = @{ assignments = $cleanAssignments } | ConvertTo-Json -Depth 10 -Compress

            Write-Host "Assignments JSON Body:"
            Write-Host $body

            # ===== Call Graph API =====
            $response = Invoke-RestMethod -Method POST -Uri $graphUrl -Headers @{
                "Authorization" = "Bearer $AccessToken"
                "Content-Type"  = "application/json"
            } -Body $body

            Add-RollbackRequest -PolicyID $PolicyGuid -RequestedBy "XLR Admin" -Status "Completed" -ExecutedBy "XLR Admin" -RollbackTargetFile $AssignmentsJson -Remarks "Rollback of Assignments" -RollBackType "Assignment" -Config $Config

            Write-Host "Assignments applied successfully $response"
        }
    }
}
