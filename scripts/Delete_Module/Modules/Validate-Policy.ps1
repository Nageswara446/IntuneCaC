. "$PSScriptRoot\..\..\Modules\Common\Get-DatabaseConnection.ps1"
 
function Get-PolicyFromTable {
    param (
        [Parameter(Mandatory)][string]$PolicyId,
        [Parameter(Mandatory)][PSCustomObject]$Config,
        [Parameter(Mandatory)][PSCustomObject]$Action,
        [Parameter(Mandatory)][PSCustomObject]$Destination,
        [Parameter(Mandatory)][string]$Token
    )
 
    $connection = $null
    try {
        
        $connection = Get-DatabaseConnection -Config $Config
        $command = $connection.CreateCommand()
        if ($Action -eq "Delete Policy") {
            $query = "SELECT * FROM policies WHERE PolicyGuid = @PolicyId AND ActionType IN ('Create New Policy','Update Policy')  AND Environment=@Destination"
            $command.CommandText = $query
            $command.Parameters.AddWithValue("@PolicyId", $PolicyId) | Out-Null
            $command.Parameters.AddWithValue("@Destination", $Destination) | Out-Null
        }

        $reader = $command.ExecuteReader()
        if ($reader.Read()) {
            $result = @{
                PolicyId   = $reader["PolicyGuid"]
                PolicyRowId   = $reader["PolicyID"]
                PolicyName = $reader["PolicyName"]
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

function Test-IntunePolicyExists {
    param (
        [Parameter(Mandatory)][string]$PolicyId,
        [Parameter(Mandatory)][string]$Token
    )

    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
    }

    $graphBase = "https://graph.microsoft.com/v1.0/deviceManagement"

    # Check Configuration Policies
    $configUrl = "$graphBase/deviceConfigurations/$PolicyId"
    try {
        $configResponse = Invoke-RestMethod -Uri $configUrl -Headers $headers -Method GET -ErrorAction Stop
        if ($configResponse) {
            Write-Host "Policy $PolicyId found in Configuration Policies"
            return $true
        }
    } catch {
        Write-Verbose "Policy $PolicyId not found in Configuration Policies."
    }

    # Check Compliance Policies
    $complianceUrl = "$graphBase/deviceCompliancePolicies/$PolicyId"
    try {
        $complianceResponse = Invoke-RestMethod -Uri $complianceUrl -Headers $headers -Method GET -ErrorAction Stop
        if ($complianceResponse) {
            Write-Host "Policy $PolicyId found in Compliance Policies"
            return $true
        }
    } catch {
        Write-Verbose "Policy $PolicyId not found in Compliance Policies."
    }

    Write-Warning "Policy $PolicyId not found in Intune (neither Configuration nor Compliance)."
    return $false
}



