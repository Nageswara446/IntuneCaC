function Add-RollbackRequest {
    param (
        [Parameter(Mandatory = $true)]
        [string]$PolicyID,
        [Parameter(Mandatory = $true)]
        [string]$RequestedBy,
        [Parameter(Mandatory = $true)]
        [string]$Status,
        [Parameter(Mandatory = $true)]
        [string]$ExecutedBy,
        [Parameter(Mandatory = $true)]
        [string]$RollbackTargetFile,
        [Parameter(Mandatory = $false)]
        [string]$Remarks,
        [Parameter(Mandatory = $true)]
        [ValidateSet("Policy","Assignment")]
        [string]$RollBackType,
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config
    )

    # Establish DB connection
    $connection = Get-DatabaseConnection -Config $Config

    # Define the query with parameters
    $query = @"
INSERT INTO rollbackrequests 
(PolicyID, RequestedBy, RequestTime, Status, ExecutedBy, RollbackTargetFile, Remarks, RollBackType) 
VALUES (@PolicyID, @RequestedBy, @RequestTime, @Status, @ExecutedBy, @RollbackTargetFile, @Remarks, @RollBackType)
"@

    try {
        $command = $connection.CreateCommand()
        $command.CommandText = $query

        # Add parameters using AddWithValue
        $CurrentTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

        $command.Parameters.AddWithValue("@PolicyID", $PolicyID) | Out-Null
        $command.Parameters.AddWithValue("@RequestedBy", $RequestedBy) | Out-Null
        $command.Parameters.AddWithValue("@RequestTime", $CurrentTime) | Out-Null
        $command.Parameters.AddWithValue("@Status", $Status) | Out-Null
        $command.Parameters.AddWithValue("@ExecutedBy", $ExecutedBy) | Out-Null
        $command.Parameters.AddWithValue("@RollbackTargetFile", $RollbackTargetFile) | Out-Null
        $command.Parameters.AddWithValue("@Remarks", $Remarks) | Out-Null
        $command.Parameters.AddWithValue("@RollBackType", $RollBackType) | Out-Null

        Write-Host "SQL Query with parameters replaced:"
        Write-Host (Get-SqlCommandWithParametersReplaced -Command $command)

        $command.ExecuteNonQuery()
        Write-Host "Rollback request inserted successfully." -ForegroundColor Green
    }
    catch {
        Write-Host "SQL Query with parameters replaced:"
        Write-Host (Get-SqlCommandWithParametersReplaced -Command $command)
        Write-Host "Error inserting rollback request into database: $_" -ForegroundColor Red
    }
    finally {
        if ($connection.State -eq 'Open') {
            $connection.Close()
        }
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
