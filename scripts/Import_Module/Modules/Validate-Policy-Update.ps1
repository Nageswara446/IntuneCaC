
Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath "..\..\Modules\Common\Get-DatabaseConnection.ps1")
#. "$PSScriptRoot\Get-DatabaseConnection.ps1"
 
function Validate-Policy-Before-Update {
    param (
        [Parameter(Mandatory)][string]$PolicyId,
        [Parameter(Mandatory)][PSCustomObject]$Config,
        [Parameter(Mandatory)][PSCustomObject]$Source,
        [Parameter(Mandatory)][PSCustomObject]$Action

    )
 
    $connection = $null
    try {
        
        $connection = Get-DatabaseConnection -Config $Config
        $command = $connection.CreateCommand()
        if ($Action -eq "Update Policy") {
            $query =  "SELECT *
                    FROM unified_release_management.policies p
                    JOIN unified_release_management.policyflow pf
                    ON p.PolicyID = pf.DestinationPolicyID
                    WHERE p.PolicyGuid = @PolicyId
                    AND p.ActionType IN ('Create New Policy','Update Policy')
                    AND p.Environment = @Source ORDER BY p.LastUpdatedTime DESC LIMIT 1"

            $command.CommandText = $query
            $command.Parameters.AddWithValue("@PolicyId", $PolicyId) | Out-Null
            $command.Parameters.AddWithValue("@Source", $Source) | Out-Null
           # Write-Host (Get-SqlCommandWithParametersReplaced -Command $command)
        }

        $reader = $command.ExecuteReader()
        if ($reader.Read()) {
            $result = @{
                PolicyId   = $reader["PolicyGuid"]
                PolicyRowId   = $reader["PolicyID"]
                PolicyName = $reader["PolicyName"]
                PolicyType = $reader["PolicyType"]
                PolicyVersion = $reader["Version"]
                GitPath = $reader["GitPath"]
            }
            #Write-Host "PolicyId----- - TEST : $($reader["SourcePolicyID"])" -ForegroundColor Cyan
            $DestinationPolicyID = $reader["SourcePolicyID"]
            #Write-Host $DestinationPolicyID
            $reader.Close()
            if ($Action -eq "Update Policy"){
                $destintion_policyguid_command = $connection.CreateCommand()
                $destintion_policyguid_query =  "SELECT *
                    FROM unified_release_management.policies
                    WHERE PolicyID = @PolicyId"

                $destintion_policyguid_command.CommandText = $destintion_policyguid_query
                $destintion_policyguid_command.Parameters.AddWithValue("@PolicyId", $DestinationPolicyID ) | Out-Null
                #Write-Host (Get-SqlCommandWithParametersReplaced -Command $destintion_policyguid_command)
                $destintion_policyguid_reader = $destintion_policyguid_command.ExecuteReader()
                if ($destintion_policyguid_reader.Read()) {
                    $result["existingPolicyGuidinSource"] = $destintion_policyguid_reader["PolicyGuid"]
                   # Write-Host "destintion_policyguid_reader" $destintion_policyguid_reader["PolicyGuid"]
                }else{
                    $result["existingPolicyGuidinSource"] = "False"
                   
                }
                
               # Write-Host "PolicyId - TEST11 : $($destintion_policyguid_reader["PolicyGuid"])" -ForegroundColor Cyan

            }
           # Write-Warning ("RESULT:`n" + ($result | Format-List | Out-String))
            return $result
        } else {
            # Write-Warning "NO RESULT"
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
