function Import-PolicyAssignmentToIntune {
    param (
        [Parameter(Mandatory)][psobject]$policyJson,
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][PSCustomObject]$Config,
        [Parameter(Mandatory)][PSCustomObject]$WorkFlowID,
        [Parameter(Mandatory)][PSCustomObject]$WorkFlowTaskID,
        [Parameter(Mandatory)][PSCustomObject]$Destination,
        [Parameter(Mandatory)][string]$PolicyID,
        [Parameter(Mandatory)][string]$Environment
    )

    $connection = Get-DatabaseConnection -Config $Config

    $result = [PSCustomObject]@{
        Success      = $false
        Response     = $null
        ErrorMessage = ""
    }

    # Write-Host "DEBUG: Starting policy assignment for PolicyID: $PolicyID" -ForegroundColor Cyan
    # Write-Host "DEBUG: Environment: $Environment" -ForegroundColor Cyan

    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
    }

    # Convert JSON string/object to PowerShell object
    $policyAssignments = $policyJson
    if (-not $policyAssignments) {
        throw "Invalid or empty policy JSON data."
    }

    # Write-Host "DEBUG: Parsed $($policyAssignments.Count) assignments from JSON" -ForegroundColor Green

    # --- 🔍 Detect correct Intune policy resource path dynamically ---
    $baseUri = "https://graph.microsoft.com/beta/deviceManagement"
    $possiblePaths = @(
        "deviceConfigurations",
        "deviceCompliancePolicies",
        "configurationPolicies",
        "deviceEnrollmentConfigurations",
        "deviceManagementScripts",
        "mobileAppConfigurations",
        "intents",
        "managedAppPolicies"
    )

    $resourcePath = $null
    foreach ($path in $possiblePaths) {
        $testUri = "$baseUri/$path/$PolicyID"
        try {
            $response = Invoke-RestMethod -Headers $headers -Uri $testUri -Method GET -ErrorAction Stop
            if ($response) {
                $resourcePath = $path
                break
            }
        } catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
        }
    }

    if (-not $resourcePath) {
        throw "Could not determine Graph API resource path for PolicyID: $PolicyID"
    }

    $assignUri = "$baseUri/$resourcePath/$PolicyID/assign"
    # Write-Host "DEBUG: Assignment URI: $assignUri" -ForegroundColor Yellow

    # --- Build the assignment request body ---
    $assignments = @()
    foreach ($assignment in $policyAssignments) {
        if ($assignment.target) {
            $targetObj = @{
                "@odata.type" = $assignment.target.'@odata.type'
                groupId       = $assignment.target.groupId
            }

            if ($assignment.target.deviceAndAppManagementAssignmentFilterId) {
                $targetObj.deviceAndAppManagementAssignmentFilterId   = $assignment.target.deviceAndAppManagementAssignmentFilterId
                $targetObj.deviceAndAppManagementAssignmentFilterType = $assignment.target.deviceAndAppManagementAssignmentFilterType
            }

            $assignments += @{ target = $targetObj }
        }
    }

    if (-not $assignments -or $assignments.Count -eq 0) {
        throw "No valid assignment targets found in JSON."
    }

    $body = @{ assignments = $assignments } | ConvertTo-Json -Depth 10
    # Write-Host "DEBUG: JSON body prepared for submission (length: $($body.Length))" -ForegroundColor Gray

    # Show preview of JSON for debugging
    # Write-Host "`nDEBUG: Assignment body preview:" -ForegroundColor DarkGray
    # Write-Host $body

    # --- 🚀 Submit to Graph API ---
    try {
        # Write-Host "DEBUG: Submitting assignments to Graph API..." -ForegroundColor Yellow
        $response = Invoke-RestMethod -Headers $headers -Method POST -Uri $assignUri -Body $body -ErrorAction Stop
        Write-Host "Policy assignments applied successfully" 

        $result.Success = $true
        $result.Response = $response

        # Store assignment data in database
        foreach ($assignment in $policyAssignments) {
            $assignmentId = $assignment.id
            $policyId     = $assignment.sourceId
            $groupId      = $assignment.target.groupId
            $importedDate = Get-Date

            $command = $connection.CreateCommand()
            $command.CommandText = @"
INSERT INTO policyassignments (
    AssignmentId, PolicyId, GroupId, ExportedDate , Rollback
) VALUES (
    @AssignmentId, @PolicyId, @GroupId, @ExportedDate, @Rollback
)
ON DUPLICATE KEY UPDATE
    ExportedDate = VALUES(ExportedDate)
"@
            $command.Parameters.Add("@AssignmentId", [MySql.Data.MySqlClient.MySqlDbType]::VarChar, 100).Value = $assignmentId
            $command.Parameters.Add("@PolicyId",     [MySql.Data.MySqlClient.MySqlDbType]::VarChar, 100).Value = $policyId
            $command.Parameters.Add("@GroupId",      [MySql.Data.MySqlClient.MySqlDbType]::VarChar, 100).Value = $groupId
            $command.Parameters.AddWithValue("@ExportedDate", $importedDate) | Out-Null
            $command.Parameters.Add("@Rollback",      [MySql.Data.MySqlClient.MySqlDbType]::VarChar, 100).Value = "True"

            try {
                $command.ExecuteNonQuery() | Out-Null
            } catch {
                # Continue if insert fails
            }
        }
    }
    catch {
        Write-Host "Failed to apply assignments." -ForegroundColor Red

        # Try to extract detailed Graph error message
        $errorMessage = ""
        if ($_.Exception.Response -and ($_.Exception.Response -is [System.Net.HttpWebResponse])) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $responseBody = $reader.ReadToEnd()
            $reader.Close()
            $errorMessage = try { ($responseBody | ConvertFrom-Json).error.message } catch { $responseBody }
            Write-Host "GRAPH ERROR RESPONSE: $errorMessage" -ForegroundColor Red
        } else {
            $errorMessage = $_.Exception.Message
        }

        $result.ErrorMessage = "Failed to apply assignments: $errorMessage"
    }

    return $result
}
