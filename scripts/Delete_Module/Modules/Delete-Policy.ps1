. "$PSScriptRoot\..\..\Modules\Common\Get-DatabaseConnection.ps1"

function Delete-PolicyFromIntune {
    param (
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][psobject]$PolicyType,
        [Parameter(Mandatory)][PSCustomObject]$Config,
        [Parameter(Mandatory)][PSCustomObject]$PolicyId, 
        [Parameter(Mandatory)][PSCustomObject]$WorkFlowID,
        [Parameter(Mandatory)][PSCustomObject]$Destination,
        [Parameter(Mandatory)][PSCustomObject]$WorkFlowTaskID,
        [Parameter(Mandatory)][PSCustomObject]$Action,
        [Parameter(Mandatory)][PSCustomObject]$Endpoints,
        [Parameter(Mandatory)][PSCustomObject]$PolicyName
    )

    $result = [PSCustomObject]@{
        Success      = $false
        Response     = $null
        ErrorMessage = ""
    }
    $headers = @{ Authorization = "Bearer $Token" }
    $deleted = $false
    $inserted = $false
    $updated = $false
    $policiesToDelete = @()
    $method = 'DELETE'

    if ($Endpoints -like "*`$expand=settings") {
        # Remove '?$expand=settings' from the end of the URL
        $uri = $Endpoints -replace "\?\`\$expand=settings", ""   
    }
    $uri = $Endpoints

    if ($PolicyType -eq "DCP") {
        $PolicyType = "Configuration Policy"
    } elseif ($PolicyType -eq "CMP") {
        $PolicyType = "Compliance Policy"
    }

    if ($Destination -eq "Prod") {
        $TenantID = $Config.Prod.tenantId
    }
    else {
        $TenantID = $Config.ADT.tenantId
    }
    
    try {
        $policy = Invoke-RestMethod -Method $method -Uri $uri -Headers $headers
        $policy | Out-String | Write-Host
        $deleted = $true
        $policiesToDelete += [PSCustomObject]@{
            PolicyId = $PolicyId
        }

        if ($deleted) {
            # Insert into database
            $connection = Get-DatabaseConnection -Config $Config
            $insertCommand = $connection.CreateCommand()
            $insertCommand.CommandText = @"
            INSERT INTO unified_release_management.policies (
                PolicyGuid,
                PolicyName,
                PolicyType,
                TenantID,
                Environment,
                Version,
                IntunePolicyVersion,
                LastModifiedBy,
                XLRTaskID,
                WorkflowID,
                ActionType
            ) VALUES (
                @PolicyGuid,
                @PolicyName,
                @PolicyType,
                @TenantID,
                @Environment,
                @Version,
                @IntunePolicyVersion,
                @LastModifiedBy,
                @XLRTaskID,
                @WorkflowID,
                @ActionType
            )
"@
            $insertCommand.Parameters.AddWithValue("@PolicyGuid", $PolicyId) | Out-Null
            $insertCommand.Parameters.AddWithValue("@PolicyName", $PolicyName) | Out-Null
            $insertCommand.Parameters.AddWithValue("@PolicyType", $PolicyType) | Out-Null
            $insertCommand.Parameters.AddWithValue("@TenantID", $TenantID) | Out-Null
            $insertCommand.Parameters.AddWithValue("@Environment", $Destination) | Out-Null
            $insertCommand.Parameters.AddWithValue("@Version", "v1.0.0") | Out-Null
            $insertCommand.Parameters.AddWithValue("@IntunePolicyVersion", "1") | Out-Null
            $insertCommand.Parameters.AddWithValue("@LastModifiedBy", "Script") | Out-Null
            $insertCommand.Parameters.AddWithValue("@XLRTaskID", $WorkFlowTaskID) | Out-Null
            $insertCommand.Parameters.AddWithValue("@WorkflowID", $WorkFlowID) | Out-Null
            $insertCommand.Parameters.AddWithValue("@ActionType", 'Delete Policy') | Out-Null

            $rowsAffected = $insertCommand.ExecuteNonQuery()
            if ($rowsAffected -gt 0) {
                $inserted = $true
            } else {
                $result.ErrorMessage = "Insert failed. No rows affected for policy ID `$PolicyId`."
            }

            # --- NEW OPERATION: Update Is_Deleted flag ---
            $updateCommand = $connection.CreateCommand()
            $updateCommand.CommandText = "UPDATE unified_release_management.policies SET Is_Deleted = TRUE WHERE PolicyGuid = @PolicyGuid"
            $updateCommand.Parameters.AddWithValue("@PolicyGuid", $PolicyId) | Out-Null

            $updateRows = $updateCommand.ExecuteNonQuery()
            if ($updateRows -gt 0) {
                $updated = $true
            } else {
                Write-Warning "No rows updated for PolicyGuid=$PolicyId when setting Is_Deleted."
            }

            $connection.Close()
        }
    }
    catch {
        Write-Warning "Failed to delete policy from ${uri}: $($_.Exception.Message)"
    }

    if ($deleted -and $inserted -and $updated) {
        $result.Success = $true
        $result.Response = $policiesToDelete
    }
    else {
        $result.Success = $false
        if (-not $deleted) { $result.ErrorMessage = "Policy deletion failed for ID '$PolicyId'" }
        elseif (-not $inserted) { $result.ErrorMessage = "Database insert failed for ID '$PolicyId'" }
        elseif (-not $updated) { $result.ErrorMessage = "Is_Deleted update failed for ID '$PolicyId'" }
    }

    return $result
}

function Get-SqlCommandWithParametersReplaced {
    param(
        [System.Data.Common.DbCommand]$Command
    )
    
    $query = $Command.CommandText

    foreach ($param in $Command.Parameters) {
        $paramName = $param.ParameterName
        $paramValue = $param.Value

        if ($null -eq $paramValue) {
            $replacement = "NULL"
        }
        elseif ($paramValue -is [string]) {
            $escapedValue = $paramValue.Replace("'", "''")
            $replacement = "'$escapedValue'"
        }
        elseif ($paramValue -is [DateTime]) {
            $replacement = "'$($paramValue.ToString("yyyy-MM-dd HH:mm:ss"))'"
        }
        else {
            $replacement = $paramValue.ToString()
        }

        $query = $query -replace [regex]::Escape($paramName), $replacement
    }

    return $query
}
