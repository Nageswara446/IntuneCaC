# Function to validate the policy ID in the database
function Confirm-Policy {
    param (
        [Parameter(Mandatory = $true)]
        [string]$PolicyID,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config
    )

    try {
        # Establish DB connection
        $connection = Get-DatabaseConnection -Config $Config

        # Use parameterized query to prevent SQL injection
        $query = "SELECT * FROM policies WHERE PolicyGuid = @PolicyID"
        $command = $connection.CreateCommand()
        $command.CommandText = $query

        # Add parameter to prevent SQL injection
        $param = $command.CreateParameter()
        $param.ParameterName = "@PolicyID"
        $param.Value = $PolicyID
        $command.Parameters.Add($param) | Out-Null

        # Execute query
        $reader = $command.ExecuteReader()

        if ($reader.HasRows) {
            $reader.Read()
            $PolicyDetails = [PSCustomObject]@{
                PolicyGuid   = $reader["PolicyGuid"]
                PolicyName   = $reader["PolicyName"]
                PolicyType   = $reader["PolicyType"]
                PolicySubType = $reader["PolicySubType"]
                Environment  = $reader["Environment"]
            }

            # Cleanup
            $reader.Close()
            $connection.Close()
            return $PolicyDetails
        } else {
            $reader.Close()
            $connection.Close()
            # Write-Host "DB Connection Closed"
            return $null
        }
    } catch {
        Write-Host "Error connecting to the database or executing query: $_"
        try { $reader?.Close(); $connection?.Close() } catch {}
        return $null
    }
}
