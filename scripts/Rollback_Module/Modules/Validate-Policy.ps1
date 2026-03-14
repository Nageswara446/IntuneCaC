
Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath "..\..\Modules\Common\Get-DatabaseConnection.ps1")
 #. "$PSScriptRoot\Get-DatabaseConnection.ps1"
 
function Get-PolicyFromTable {
    param (
        [Parameter(Mandatory)][string]$PolicyId,
        [Parameter(Mandatory)][PSCustomObject]$Config,
        [Parameter(Mandatory)][PSCustomObject]$WorkFlowID,
        [Parameter(Mandatory)][PSCustomObject]$Source,
        [Parameter(Mandatory)][PSCustomObject]$Action,
        [Parameter(Mandatory)][PSCustomObject]$Destination
    )
 
    $connection = $null
    try {
        
        $connection = Get-DatabaseConnection -Config $Config
        $command = $connection.CreateCommand()
        if ($Action -eq "Update Policy" ) {
            $xlr_action = 'Export Policy'
            $query = "SELECT * FROM policies WHERE PolicyGuid = @PolicyId AND ActionType=@xlr_action  AND Environment=@Source"

            
            $command.CommandText = $query
            $command.Parameters.AddWithValue("@PolicyId", $PolicyId) | Out-Null
            # $command.Parameters.AddWithValue("@WorkFlowID", $WorkFlowID) | Out-Null
            $command.Parameters.AddWithValue("@xlr_action", $xlr_action) | Out-Null
            $command.Parameters.AddWithValue("@Source", $Source) | Out-Null
        }

        $reader = $command.ExecuteReader()
        # Write-Host (Get-SqlCommandWithParametersReplaced -Command $command)
        if ($reader.Read()) {
            $result = @{
                PolicyId   = $reader["PolicyGuid"]
                PolicyRowId   = $reader["PolicyID"]
                PolicyName = $reader["PolicyName"]
                PolicyType = $reader["PolicyType"]
                PolicyVersion = $reader["Version"]
                GitPath = $reader["GitPath"]
            }
            # Write-Host "-----------$result"
            $PolicyRowId = $reader["PolicyID"]
            $reader.Close()
            if ($Action -eq "Update Policy"){
                $SourceTenantID=''
                if ($Source -eq "ADT") {
                    $SourceTenantID = $Config.Source.ADT.tenantId
                }
                
                $check_policy_update_query = "SELECT *
                        FROM unified_release_management.policyflow WHERE DestinationPolicyID = @DestinationPolicyID
                        AND SourceTenantID=@SourceTenantID"
                $check_policy_update_command = $connection.CreateCommand()
                $check_policy_update_command.CommandText = $check_policy_update_query
                $check_policy_update_command.Parameters.AddWithValue("@DestinationPolicyID", $PolicyRowId) | Out-Null
                $check_policy_update_command.Parameters.AddWithValue("@SourceTenantID", $SourceTenantID) | Out-Null
                $check_policy_update_reader = $check_policy_update_command.ExecuteReader()
                if ($check_policy_update_reader.Read()) {
                    $result["existingPolicyinSource"] = "Yes"
                } else {
                    $result["existingPolicyinSource"] = "No"
                }
            }
            return $result
        } else {
            
            return $null
        }
    }
    catch {
        #Write-Warning "Error querying policy $PolicyId: $($_.Exception.Message)"
        Write-Warning "Error querying policy `${PolicyId}`: $($_.Exception.Message)"
        return $null
    }
    finally {
        if ($connection -and $connection.State -eq 'Open') {
            $connection.Close()
            #Write-Host "Closed DB connection"
        }
    }
}

function Check-Duplicate-PolicyInDestination {
    param (
        [Parameter(Mandatory)][string]$ProdPolicyName,
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][PSCustomObject]$Config,
        [Parameter(Mandatory)][PSCustomObject]$Destination,
        [Parameter(Mandatory)][PSCustomObject]$policyType
    )

    $connection = $null
    if ($Destination -eq "Prod") {
        $TenantID = $Config.Destination.Prod.tenantId
    }
    else {
        $TenantID = $Config.Destination.ADT.tenantId
    }
    try {
        $connection = Get-DatabaseConnection -Config $Config
        $query = "SELECT * FROM policies WHERE PolicyName = @PolicyName AND PolicyType=@PolicyType AND Environment=@Environment  AND TenantID=@TenantID AND ActionType=@Action AND Is_Deleted='False'"
        $command = $connection.CreateCommand()
        $command.CommandText = $query
        $command.Parameters.AddWithValue("@PolicyName", $ProdPolicyName) | Out-Null
        $command.Parameters.AddWithValue("@PolicyType", $policyType) | Out-Null
        $command.Parameters.AddWithValue("@Environment", $Destination) | Out-Null
        $command.Parameters.AddWithValue("@TenantID", $TenantID) | Out-Null
        $command.Parameters.AddWithValue("@Action", 'Create New Policy') | Out-Null
 
        $reader = $command.ExecuteReader()
        if ($reader.Read()) {
            $result = @{
                PolicyId   = $reader["PolicyGuid"]
                PolicyName = $ProdPolicyName
                PolicyType = $reader["PolicyType"]
            }
            return $result
        } else {
            return $null
        }
    }
    catch {
        #Write-Warning "Error querying policy $PolicyId: $($_.Exception.Message)"
        Write-Warning "Error querying policy `${PolicyId}`: $($_.Exception.Message)"
        return $null
    }
    finally {
        if ($connection -and $connection.State -eq 'Open') {
            $connection.Close()
            #Write-Host "Closed DB connection"
        }
    }
}
