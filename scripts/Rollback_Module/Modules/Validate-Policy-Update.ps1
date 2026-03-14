. (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath "..\..\Modules\Common\Get-DatabaseConnection.ps1"))
 
function Validate-Policy-Before-Update {
    param (
        [Parameter(Mandatory)][string]$PolicyId,
        [Parameter(Mandatory)][PSCustomObject]$Config,
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Action
    )

    $connection = $null
    try {

        $connection = Get-DatabaseConnection -Config $Config
        $command = $connection.CreateCommand()

        if ($Action -eq "Update Policy") {
            $query ="SELECT *
                    FROM unified_release_management.policies p
                    JOIN unified_release_management.policyflow pf
                    ON p.PolicyID = pf.DestinationPolicyID
                    WHERE p.PolicyGuid = @PolicyId
                    AND p.ActionType IN ('Create New Policy')
                     ORDER BY p.LastUpdatedTime DESC LIMIT 1"

            $command.CommandText = $query
            $command.Parameters.AddWithValue("@PolicyId", $PolicyId) | Out-Null

            $reader = $command.ExecuteReader()

            if ($reader.Read()) {
                $policyGuid = $reader["PolicyGuid"]
                $policysourceid = $reader["SourcePolicyID"]
                $reader.Close()

                # Second query: select * where policysourceid equals PolicyID in policies table
                $secondQuery = "SELECT * FROM unified_release_management.policies WHERE PolicyID = @PolicySourceId"
                $secondCommand = $connection.CreateCommand()
                $secondCommand.CommandText = $secondQuery
                $secondCommand.Parameters.AddWithValue("@PolicySourceId", $policysourceid) | Out-Null
                $secondReader = $secondCommand.ExecuteReader()
                # Write-Host (Get-SqlCommandWithParametersReplaced -Command $secondCommand)

                if ($secondReader.Read()) {
                    $result = @{
                        PolicyGuid = $secondReader["PolicyGuid"]
                        PolicyRowId = $secondReader["PolicyID"]
                        PolicyName = $secondReader["PolicyName"]
                        PolicyType = $secondReader["PolicyType"]
                        PolicyVersion = $secondReader["Version"]
                        GitPath = $secondReader["GitPath"]
                        existingPolicyGuidinSource = $secondReader["PolicyGuid"]
                    }

                    $secondReader.Close()

                    # Third query: select PolicyGuid, GitPath from policies where PolicyGuid matches, latest record
                    $thirdConnection = Get-DatabaseConnection -Config $Config
                    try {
                        $thirdQuery = "SELECT PolicyGuid, GitPath, PolicyType, PolicyName, Version FROM unified_release_management.policies WHERE PolicyGuid = @PolicyGuid ORDER BY LastUpdatedTime DESC LIMIT 1"
                        $thirdCommand = $thirdConnection.CreateCommand()
                        $thirdCommand.CommandText = $thirdQuery
                        $thirdCommand.Parameters.AddWithValue("@PolicyGuid", $result.PolicyGuid) | Out-Null
                        $thirdReader = $thirdCommand.ExecuteReader()
                        # Write-Host (Get-SqlCommandWithParametersReplaced -Command $thirdCommand)

                        if ($thirdReader.Read()) {
                            # Write-Host "====== Latest Record for PolicyGuid ======" -ForegroundColor Green
                            $latestResult = @{
                                PolicyGuid = $thirdReader["PolicyGuid"]
                                GitPath = $thirdReader["GitPath"]
                                PolicyType = $thirdReader["PolicyType"]
                                PolicyName = $thirdReader["PolicyName"]
                                PolicyVersion = $thirdReader["Version"]
                            }
                            return $latestResult
                        } else {
                            Write-Host "No latest record found for PolicyGuid: $($result.PolicyGuid)"
                            return $null
                        }
                    }
                    finally {
                        $thirdReader.Close()
                        $thirdConnection.Close()
                    }
                }

                 else {
                    $secondReader.Close()
                    return $null
                }
            } else {
                $reader.Close()
                return $null
            }
        } else {
            return $null
        }
    }
    catch {
        Write-Warning "Error querying policy `${PolicyId}`: $($_.Exception.Message)"
        return $null
    }
    finally {
        if ($connection -and $connection.State -eq 'Open') {
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
