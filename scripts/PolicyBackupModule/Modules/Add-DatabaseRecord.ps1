function Add-DatabaseRecord {
    param (
        [Parameter(Mandatory = $true)]
        [string]$PolicyID,
        [Parameter(Mandatory = $true)]
        [string]$BackupPath,
        [Parameter(Mandatory = $true)]
        [string]$AssignmentFile,
        [Parameter(Mandatory = $true)]
        [string]$Environment, 
        [Parameter(Mandatory = $true)]
        [string]$PolicyVersion, 
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config
    )

    # Establish DB connection
    $connection = Get-DatabaseConnection -Config $Config

    # Define the query with parameters
    $query = @"
INSERT INTO policybackups (PolicyID, Environment, BackupTime, BackupFilePath, AssignmentFile, CreatedBy, Reason, PolicyVersion) 
VALUES (@PolicyID, @Environment, NOW(), @BackupPath, @AssignmentFile, 'XLR ADMIN', 'Backup Policy', @PolicyVersion)
"@

    try {
        $command = $connection.CreateCommand()
        $command.CommandText = $query

        # Add parameters to avoid SQL injection
        $command.Parameters.Add((New-Object MySql.Data.MySqlClient.MySqlParameter("@PolicyID", [MySql.Data.MySqlClient.MySqlDbType]::VarChar, 255))).Value = $PolicyID
        $command.Parameters.Add((New-Object MySql.Data.MySqlClient.MySqlParameter("@Environment", [MySql.Data.MySqlClient.MySqlDbType]::VarChar, 255))).Value = $Environment
        $command.Parameters.Add((New-Object MySql.Data.MySqlClient.MySqlParameter("@BackupPath", [MySql.Data.MySqlClient.MySqlDbType]::VarChar, 255))).Value = $BackupPath
        $command.Parameters.Add((New-Object MySql.Data.MySqlClient.MySqlParameter("@PolicyVersion", [MySql.Data.MySqlClient.MySqlDbType]::VarChar, 255))).Value = $PolicyVersion
        $command.Parameters.Add((New-Object MySql.Data.MySqlClient.MySqlParameter("@AssignmentFile", [MySql.Data.MySqlClient.MySqlDbType]::Text))).Value = $AssignmentFile

        $command.ExecuteNonQuery()
    }
    catch {
        Write-Host "Error inserting record into database: $_" -ForegroundColor Red
    }
    finally {
        if ($connection.State -eq 'Open') {
            $connection.Close()
        }
    }
}
