. "$PSScriptRoot\Get-DatabaseConnection.ps1"

function Get-PolicyGuidsByXLR {
    param (
        [Parameter(Mandatory)][string]$XLRIDReleaseTag,
        [Parameter(Mandatory)][PSCustomObject]$Config
    )

    $connection = $null
    $policyGuids = @()

    try {
        # Establish DB connection
        $connection = Get-DatabaseConnection -Config $Config
        $command = $connection.CreateCommand()

#         # SQL query to fetch all matching PolicyGuids
#         $query = @"
# SELECT PolicyGuid
# FROM policies
# WHERE XLRTaskID = @XLRTag OR WorkflowID = @XLRTag
# ORDER BY LastUpdatedTime DESC
# "@

        $query = @"
SELECT PolicyGuid
FROM policies
WHERE XLRTaskID = @XLRTag OR WorkflowID = @XLRTag
ORDER BY LastUpdatedTime DESC
LIMIT 1
"@
        $command.CommandText = $query
        $command.Parameters.AddWithValue("@XLRTag", $XLRIDReleaseTag) | Out-Null

        $reader = $command.ExecuteReader()

        while ($reader.Read()) {
            $policyGuids += $reader["PolicyGuid"]
        }

        $reader.Close()

        if ($policyGuids.Count -eq 0) {
            return "Not Found"
        }
    }
    catch {
        Write-Warning "Error querying policy GUIDs: $($_.Exception.Message)"
        return "Not Found"
    }
    finally {
        if ($connection -and $connection.State -eq 'Open') {
            $connection.Close()
        }
    }

    return $policyGuids
}
