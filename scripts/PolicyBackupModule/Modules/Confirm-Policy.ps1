function Confirm-Policy {
    param (
        [Parameter(Mandatory = $true)]
        [string]$PolicyGuid,
        [Parameter(Mandatory = $true)]
        [string]$XLRTaskID,
        [Parameter(Mandatory = $true)]
        [string]$WorkflowID,
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config
    )

    try {
        # Establish DB connection
        $connection = Get-DatabaseConnection -Config $Config

        # SQL query with MySQL parameter placeholders (use ? instead of @)
        $query = @"
            SELECT PolicyID, PolicyGuid, PolicyName, PolicyType, PolicySubType, Environment, Version
            FROM policies
            WHERE PolicyGuid = ?PolicyGuid
              AND WorkflowID = ?WorkflowID
              AND ActionType = 'Export Policy'
            ORDER BY LastUpdatedTime DESC
            LIMIT 1
"@
        $command = $connection.CreateCommand()
        $command.CommandText = $query

        # Define parameters
        $parameters = @{
            "?PolicyGuid" = $PolicyGuid
            "?WorkflowID" = $WorkflowID
        }

        # Bind parameters
        foreach ($name in $parameters.Keys) {
            $param = $command.CreateParameter()
            $param.ParameterName = $name
            $param.Value = $parameters[$name]
            $command.Parameters.Add($param) | Out-Null
        }

        # Debugging output
        Write-Verbose "Executing query: $($command.CommandText)"
        foreach ($p in $command.Parameters) {
            Write-Verbose "Param $($p.ParameterName) = $($p.Value)"
        }

        # Execute query
        # Write-Host "SQL Query with parameters replaced:"
        # Write-Host (Get-SqlCommandWithParametersReplaced -Command $command)
        $reader = $command.ExecuteReader()
        try {
            if ($reader.HasRows) {
                $reader.Read()
                return [PSCustomObject]@{
                    PolicyID      = $reader["PolicyID"]
                    PolicyGuid    = $reader["PolicyGuid"]
                    PolicyName    = $reader["PolicyName"]
                    PolicyType    = $reader["PolicyType"]
                    PolicySubType = $reader["PolicySubType"]
                    Environment   = $reader["Environment"]
                    Version       = $reader["Version"]
                }
            } else {
                Write-Verbose "No policy found for PolicyGuid=$PolicyGuid, XLRTaskID=$XLRTaskID, WorkflowID=$WorkflowID"
                return $null
            }
        }
        finally {
            if ($reader) { $reader.Close() }
            if ($connection) { $connection.Close() }
        }
    } catch {
        Write-Error "Error in Confirm-Policy: $($_.Exception.Message)"
        try {
            if ($reader) { $reader.Close() }
            if ($connection) { $connection.Close() }
        } catch {}
        return $null
    }
}

function Get-SqlCommandWithParametersReplaced {
    param(
        [System.Data.Common.DbCommand]$Command
    )
    
    $query = $Command.CommandText

    foreach ($param in $Command.Parameters) {
        # Get parameter name and value
        $paramName = $param.ParameterName
        $paramValue = $param.Value

        # Format value for SQL (add quotes if string, handle NULL)
        if ($null -eq $paramValue) {
            $replacement = "NULL"
        }
        elseif ($paramValue -is [string]) {
            # Escape single quotes by doubling them
            $escapedValue = $paramValue.Replace("'", "''")
            $replacement = "'$escapedValue'"
        }
        elseif ($paramValue -is [DateTime]) {
            $replacement = "'$($paramValue.ToString("yyyy-MM-dd HH:mm:ss"))'"
        }
        else {
            $replacement = $paramValue.ToString()
        }

        # Replace all occurrences of the parameter in the query text
        $query = $query -replace [regex]::Escape($paramName), $replacement
    }

    return $query
}
