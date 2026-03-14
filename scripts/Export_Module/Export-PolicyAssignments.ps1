function Export-PolicyAssignments {
    param (
        [Parameter(Mandatory = $true)][string]$AccessToken,
        [Parameter(Mandatory = $true)][array]$Policies,
        [Parameter(Mandatory = $true)][string]$AssignmentEndpointBase,
        [Parameter(Mandatory = $true)][string]$TempExportPath,
        [Parameter(Mandatory=$true)][PSCustomObject]$Config
    )

    # Write-Host "Export-PolicyAssignments called with $($Policies.Count) policies" -ForegroundColor Cyan

    if (-not $Policies -or -not $AccessToken -or -not $AssignmentEndpointBase -or -not $TempExportPath -or -not $Config) {
        # Write-Host "Missing required parameters" -ForegroundColor Red
        return $false
    }

    try {
        $connectionString = "Server=$($Config.Database.Server);Port=$($Config.Database.Port);Database=$($Config.Database.DatabaseName);Uid=$($Config.Database.Username);Pwd=$($Config.Database.Password);SslMode=Required;Charset=utf8mb4;"

        [void][System.Reflection.Assembly]::LoadWithPartialName("MySql.Data")

        $connection = New-Object MySql.Data.MySqlClient.MySqlConnection
        $connection.ConnectionString = $connectionString
        $connection.Open()

        $headers = @{
            Authorization = "Bearer $AccessToken"
        }

        $assignmentsPath = Join-Path $TempExportPath "Assignments"
        if (-not (Test-Path $assignmentsPath)) {
            New-Item -Path $assignmentsPath -ItemType Directory | Out-Null
        }

        foreach ($policy in $Policies) {
            # Write-Host "Processing policy: $($policy.PolicyId), Category: $($policy.PolicyCategory)" -ForegroundColor Cyan

            if (-not $policy.PolicyId -or -not $policy.PolicyCategory) {
                # Write-Host "Skipping policy due to missing PolicyId or PolicyCategory" -ForegroundColor Yellow
                continue
            }

            $assignmentUri = "$AssignmentEndpointBase/$($policy.PolicyCategory)/$($policy.PolicyId)/assignments"
            # Write-Host "Fetching assignments from: $assignmentUri" -ForegroundColor Gray

            try {
                $assignments = Invoke-RestMethod -Uri $assignmentUri -Headers $headers -Method Get
                # Write-Host "Found $($assignments.value.Count) assignments" -ForegroundColor Green
            } catch {
                # Write-Host "Failed to fetch assignments: $($_.Exception.Message)" -ForegroundColor Red
                continue
            }

            if (-not $assignments.value -or $assignments.value.Count -eq 0) {
                # Write-Host "No assignments found for policy $($policy.PolicyId)" -ForegroundColor Yellow
                continue
            }

            $outputPath = Join-Path $assignmentsPath "$($policy.PolicyId)_assignment.json"
            $assignments.value | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputPath -Encoding utf8

            foreach ($assignment in $assignments.value) {
                $assignmentId = $assignment.id
                $policyId     = $assignment.sourceId
                $groupId      = $assignment.target.groupId
                $exportedDate = Get-Date

                $command = $connection.CreateCommand()
                $command.CommandText = @"
INSERT INTO policyassignments (
    AssignmentId, PolicyId, GroupId, ExportedDate
) VALUES (
    @AssignmentId, @PolicyId, @GroupId, @ExportedDate
)
ON DUPLICATE KEY UPDATE
    ExportedDate = VALUES(ExportedDate)
"@

                $command.Parameters.Add("@AssignmentId", [MySql.Data.MySqlClient.MySqlDbType]::VarChar, 100).Value = $assignmentId
                $command.Parameters.Add("@PolicyId",     [MySql.Data.MySqlClient.MySqlDbType]::VarChar, 100).Value = $policyId
                $command.Parameters.Add("@GroupId",      [MySql.Data.MySqlClient.MySqlDbType]::VarChar, 100).Value = $groupId
                $command.Parameters.AddWithValue("@ExportedDate", $exportedDate) | Out-Null

                try {
                    $command.ExecuteNonQuery() | Out-Null
                    # Write-Host "Successfully inserted assignment $assignmentId for policy $policyId" -ForegroundColor Green
                } catch {
                    # Write-Host "Failed to insert assignment $assignmentId for policy $policyId : $($_.Exception.Message)" -ForegroundColor Red
                    # Continue
                }
            }
        }

        $connection.Close()
        return $true
    }
    catch {
        return $false
    }
}
