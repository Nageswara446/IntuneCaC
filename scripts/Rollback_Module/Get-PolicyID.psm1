function Get-DatabaseConnection {
    param (
        [Parameter(Mandatory)][PSCustomObject]$Config
    )
 
    try {
        [void][System.Reflection.Assembly]::LoadWithPartialName("MySql.Data")
    } catch {
        throw "Failed to load MySql.Data. Run 'Install-Package MySql.Data' or download from https://dev.mysql.com/downloads/connector/net/"
    }
 
    $connectionString = "Server=$($Config.Database.Server);Port=$($Config.Database.Port);Database=$($Config.Database.DatabaseName);Uid=$($Config.Database.Username);Pwd=$($Config.Database.Password);SslMode=Required;"
 
    $connection = New-Object MySql.Data.MySqlClient.MySqlConnection
    $connection.ConnectionString = $connectionString
 
    try {
        $connection.Open()
        return $connection
    } catch {
        throw ("Failed to connect to DB at {0}:{1} - {2}" -f $Config.Database.Server, $Config.Database.Port, $_.Exception.Message)
    }
}

function Get-PolicyGuidsFromSource {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$PolicyGuidList,  # Accepts comma-separated list
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )

    # Split the input into individual PolicyGuids (trim spaces)
    $policyGuids = $PolicyGuidList -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }

    if ($policyGuids.Count -eq 0) {
        # Write-Warning "No valid PolicyGuid values provided."
        return $null
    }

    $connection = Get-DatabaseConnection -Config $Config
    $finalPolicyGuids = @()

    try {
        foreach ($policyGuid in $policyGuids) {

            # --- First Query: Get SourcePolicyID(s) ---
            $query1 = @"
SELECT SourcePolicyID
FROM unified_release_management.policies p
JOIN unified_release_management.policyflow pf
    ON p.PolicyID = pf.DestinationPolicyID
WHERE p.PolicyGuid = @policyGuid
AND p.ActionType IN ('Create New Policy','Update Policy','Export Policy')
"@

            $command1 = $connection.CreateCommand()
            $command1.CommandText = $query1
            $command1.Parameters.AddWithValue("@policyGuid", $policyGuid) | Out-Null

            $reader1 = $command1.ExecuteReader()
            $sourcePolicyIDs = @()

            while ($reader1.Read()) {
                $sourcePolicyIDs += $reader1["SourcePolicyID"]
            }
            $reader1.Close()

            if ($sourcePolicyIDs.Count -eq 0) {
                # Write-Warning "No SourcePolicyID found for PolicyGuid '$policyGuid'."
                continue
            }

            # --- Second Query: Get PolicyGuid(s) for each SourcePolicyID ---
            foreach ($sourceID in $sourcePolicyIDs) {
                $query2 = "SELECT PolicyGuid FROM unified_release_management.policies WHERE PolicyID = @policyID"
                $command2 = $connection.CreateCommand()
                $command2.CommandText = $query2
                $command2.Parameters.AddWithValue("@policyID", [int]$sourceID) | Out-Null

                $reader2 = $command2.ExecuteReader()
                while ($reader2.Read()) {
                    $finalPolicyGuids += $reader2["PolicyGuid"]
                }
                $reader2.Close()
            }
        }

        $connection.Close()

        if ($finalPolicyGuids.Count -eq 0) {
            # Write-Warning "No PolicyGuids found for the provided PolicyGuid list."
            return $null
        } else {
            # Return unique PolicyGuids
            return $finalPolicyGuids | Sort-Object -Unique
        }

    } catch {
        if ($connection.State -eq 'Open') {
            $connection.Close()
        }
        throw $_
    }
}