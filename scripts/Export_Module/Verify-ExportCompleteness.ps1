# Function: Verify-ExportCompleteness
# Description: Verifies that all expected policy and assignment files exist and are stored in the database.
# Parameters:
#   - Policies (array, Mandatory): Array of policy objects to verify.
#   - BaseExportPath (string, Mandatory): Path to the directory containing policy JSON files.
#   - AssignmentsPath (string, Mandatory): Path to the directory containing assignment JSON files.
#   - Config (PSCustomObject, Mandatory): Configuration object containing database connection details and TenantId.

function Verify-ExportCompleteness {
    param (
        [Parameter(Mandatory=$true)][array]$Policies,
        [Parameter(Mandatory=$true)][string]$BaseExportPath,
        [Parameter(Mandatory=$true)][string]$AssignmentsPath,
        [Parameter(Mandatory=$true)][PSCustomObject]$Config
    )

    try {
        if (-not $Policies) {
            return $false
        }
        $isComplete = $true
        foreach ($policy in $Policies) {
            $policyFile = Join-Path $BaseExportPath "$($policy.PolicyId).json"
            $assignmentFile = Join-Path $AssignmentsPath "$($policy.PolicyId)_assignment.json"
            if (-not (Test-Path $policyFile)) {
                $isComplete = $false
            }
            if (-not (Test-Path $assignmentFile)) {
                $isComplete = $false
            }
        }
        if (-not (Validate-PolicyJson -BaseExportPath $BaseExportPath -AssignmentsPath $AssignmentsPath)) {
            $isComplete = $false
        }
        $connectionString = "Server=$($Config.Database.Server);Port=$($Config.Database.Port);Database=$($Config.Database.DatabaseName);Uid=$($Config.Database.Username);Pwd=$($Config.Database.Password);SslMode=Required;"
        $connection = New-Object MySql.Data.MySqlClient.MySqlConnection
        $connection.ConnectionString = $connectionString
        $connection.Open()
        foreach ($policy in $Policies) {
            $query = "SELECT COUNT(*) FROM Policies WHERE PolicyGuid = @PolicyGuid"
            $command = New-Object MySql.Data.MySqlClient.MySqlCommand
            $command.Connection = $connection
            $command.CommandText = $query
            $command.Parameters.AddWithValue("@PolicyGuid", $policy.PolicyId) | Out-Null
            $count = $command.ExecuteScalar()
            if ($count -eq 0) {
                $isComplete = $false
            }
        }
        $connection.Close()
        return $isComplete
    }
    catch {
        return $false
    }
}