. "$PSScriptRoot\Get-DatabaseConnection.ps1"
function XLRWorkflow-Record {
    param (
        [Parameter(Mandatory)][string]$XLRWorkflowID,
        [Parameter(Mandatory)][string]$ChangeID,
        [Parameter(Mandatory)][string]$TriggerBy,
        [Parameter(Mandatory)][string]$Environment,
        [Parameter(Mandatory)][string]$StartTime,
        [Parameter()][string]$EndTime,
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][string]$Remark
    )

    $result = [PSCustomObject]@{
        Success      = $false
        Response     = $null
        ErrorMessage = ""
    }

    
    try {

        # Path to your JSON config file
        $configPath = "$PSScriptRoot\config.json"

        if (-not (Test-Path $configPath)) {
            throw "Missing config file at $configPath"
        }
        $Config = Get-Content -Raw -Path $configPath | ConvertFrom-Json

	
        $connection = $null
        $connection = Get-DatabaseConnection -Config $Config
        $insertCommand = $connection.CreateCommand()
        $insertCommand.CommandText = @"
        INSERT INTO unified_release_management.workflowexecutions (
            WorkflowName,
            ChangeID,
            TriggeredBy,
            Environment,
            StartTime,
            EndTime,
            Status,
            Remarks
        ) VALUES (
            @WorkflowName,
            @ChangeID,
            @TriggeredBy,
            @Environment,
            @StartTime,
            @EndTime,
            @Status,
            @Remarks
        )
"@
        $insertCommand.Parameters.AddWithValue("@WorkflowName", $XLRWorkflowID) | Out-Null
        $insertCommand.Parameters.AddWithValue("@ChangeID", $ChangeID) | Out-Null
        $insertCommand.Parameters.AddWithValue("@TriggeredBy", $TriggerBy) | Out-Null
        $insertCommand.Parameters.AddWithValue("@Environment", $Environment) | Out-Null
        $insertCommand.Parameters.AddWithValue("@StartTime", $StartTime) | Out-Null
        $insertCommand.Parameters.AddWithValue("@EndTime", $EndTime) | Out-Null
        $insertCommand.Parameters.AddWithValue("@Status", $Status) | Out-Null
        $insertCommand.Parameters.AddWithValue("@Remarks", $Remark) | Out-Null
        #Write-Host "SQL Query with parameters replaced:"
        #Write-Host (Get-SqlCommandWithParametersReplaced -Command $insertCommand)
        $rowsAffected = $insertCommand.ExecuteNonQuery()
        if ($rowsAffected -gt 0) {
            $result.Success  = $true
            $result.Response = 'Record Inserted'
            return $result
        }
        
    }
    catch {
        $result.ErrorMessage = " Insert failed. No rows affected."
        return $result
    }
}


function XLRWorkflowUpdate-Record {
    param (
        [Parameter(Mandatory)][string]$XLRWorkflowID,
        [Parameter()][string]$EndTime,
        [Parameter()][string]$Status
    )

    $result = [PSCustomObject]@{
        Success      = $false
        Response     = $null
        ErrorMessage = ""
    }

    
    try {

        # Path to your JSON config file
        $configPath = "$PSScriptRoot\config.json"

        if (-not (Test-Path $configPath)) {
            throw "Missing config file at $configPath"
        }
        $Config = Get-Content -Raw -Path $configPath | ConvertFrom-Json

        $connection = $null
        $connection = Get-DatabaseConnection -Config $Config

        $updateCommand = $connection.CreateCommand()
        $updateCommand.CommandText = @"
        UPDATE unified_release_management.workflowexecutions
        SET
            EndTime = @EndTime,
            Status = @Status
        WHERE
            WorkflowName = @WorkflowName
"@

        $updateCommand.Parameters.AddWithValue("@Status", $Status) | Out-Null
        $updateCommand.Parameters.AddWithValue("@EndTime", $EndTime) | Out-Null
        $updateCommand.Parameters.AddWithValue("@WorkflowName", $XLRWorkflowID) | Out-Null
        
        $rowsAffected = $updateCommand.ExecuteNonQuery()
        if ($rowsAffected -gt 0) {
            $result.Success  = $true
            $result.Response = 'Record updated'
            return $result
        }
        
    }
    catch {
        $result.ErrorMessage = " Insert failed. No rows affected."
        return $result
    }
}

function XLRWorkflowTask-Record {
    param (
        [Parameter(Mandatory)][string]$XLRWorkflowID,
        [Parameter(Mandatory)][string]$XLRWorkflowTaskID,
        [Parameter(Mandatory)][string]$TaskName,
        [Parameter(Mandatory)][string]$TaskType,
        [Parameter(Mandatory)][string]$SequenceNumber,
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][string]$StartTime,
        [Parameter()][string]$EndTime,
        [Parameter(Mandatory)][string]$ExecutedBy,
        [Parameter(Mandatory)][string]$Remarks,
        [Parameter(Mandatory)][string]$RelatedPolicyID
    )

    $result = [PSCustomObject]@{
        Success      = $false
        Response     = $null
        ErrorMessage = ""
    }

    
    try {

        # Path to your JSON config file
        $configPath = "$PSScriptRoot\config.json"

        if (-not (Test-Path $configPath)) {
            throw "Missing config file at $configPath"
        }
        $Config = Get-Content -Raw -Path $configPath | ConvertFrom-Json
        $connection = $null
        $connection = Get-DatabaseConnection -Config $Config
        $insertCommand = $connection.CreateCommand()
        $insertCommand.CommandText = @"
        INSERT INTO unified_release_management.workflowtasks (
            XLRTaskID,
            WorkflowExecutionID,
            TaskName,
            TaskType,
            SequenceNumber,
            Status,
            StartTime,
            EndTime,
            ExecutedBy,
            Remarks,
            RelatedPolicyID
        ) VALUES (
            @XLRTaskID,
            @WorkflowExecutionID,
            @TaskName,
            @TaskType,
            @SequenceNumber,
            @Status,
            @StartTime,
            @EndTime,
            @ExecutedBy,
            @Remarks,
            @RelatedPolicyID
        )
"@
        $insertCommand.Parameters.AddWithValue("@XLRTaskID", $XLRWorkflowTaskID) | Out-Null
        $insertCommand.Parameters.AddWithValue("@WorkflowExecutionID", $XLRWorkflowID) | Out-Null
        $insertCommand.Parameters.AddWithValue("@TaskName", $TaskName) | Out-Null
        $insertCommand.Parameters.AddWithValue("@TaskType", $TaskType) | Out-Null
        $insertCommand.Parameters.AddWithValue("@SequenceNumber", $SequenceNumber) | Out-Null
        $insertCommand.Parameters.AddWithValue("@Status", $Status) | Out-Null
        $insertCommand.Parameters.AddWithValue("@StartTime", $StartTime) | Out-Null
        $insertCommand.Parameters.AddWithValue("@EndTime", $EndTime) | Out-Null
        $insertCommand.Parameters.AddWithValue("@ExecutedBy", $ExecutedBy) | Out-Null
        $insertCommand.Parameters.AddWithValue("@Remarks", $Remarks) | Out-Null
        $insertCommand.Parameters.AddWithValue("@RelatedPolicyID", $RelatedPolicyID) | Out-Null
        #Write-Host "SQL Query with parameters replaced:"
        #Write-Host (Get-SqlCommandWithParametersReplaced -Command $insertCommand)
        
        $rowsAffected = $insertCommand.ExecuteNonQuery()
        if ($rowsAffected -gt 0) {
            $result.Success  = $true
            $result.Response = 'Record Inserted'
            return $result
        }
        
    }
    catch {
        $result.ErrorMessage = " Insert failed. No rows affected."
        return $result
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
