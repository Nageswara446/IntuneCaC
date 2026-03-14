# Function: Validate-PolicyJson
# Description: Validates JSON files for policies and assignments to ensure required keys are present.
# Parameters:
#   - BaseExportPath (string, Mandatory): Path to the directory containing policy JSON files.
#   - AssignmentsPath (string, Mandatory): Path to the directory containing assignment JSON files.

function Validate-PolicyJson {
    param (
        [Parameter(Mandatory=$true)][string]$BaseExportPath,
        [Parameter(Mandatory=$true)][string]$AssignmentsPath
    )

    try {
        $policyRequiredKeys = @("id", "displayName", "version", "@odata.type")
        $assignmentRequiredKeys = @("id")
        $jsonFiles = @()

        if (Test-Path $BaseExportPath) {
            $jsonFiles += Get-ChildItem -Path $BaseExportPath -Filter "*.json" -File
        }

        if (Test-Path $AssignmentsPath) {
            $jsonFiles += Get-ChildItem -Path $AssignmentsPath -Filter "*_assignment.json" -File
        }

        if ($jsonFiles.Count -eq 0) {
            return $false
        }

        $isValid = $true
        foreach ($file in $jsonFiles) {
            try {
                $jsonContent = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
                $itemsToCheck = if ($jsonContent -is [array]) { $jsonContent } else { @($jsonContent) }
                $requiredKeys = if ($file.Name -match "_assignment\.json$") { $assignmentRequiredKeys } else { $policyRequiredKeys }
                foreach ($item in $itemsToCheck) {
                    foreach ($key in $requiredKeys) {
                        if (-not ($item.PSObject.Properties.Name -contains $key)) {
                            $isValid = $false
                        }
                    }
                }
            }
            catch {
                $isValid = $false
            }
        }
        return $isValid
    }
    catch {
        return $false
    }
}
 