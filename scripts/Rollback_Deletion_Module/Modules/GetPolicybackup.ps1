function GetBackupDetails {

    param (
        [Parameter(Mandatory)][string]$PolicyIds,   # Comma-separated Policy GUIDs
        [Parameter(Mandatory)][PSCustomObject]$Config
    )

    $connection = $null
    $results = @()

    try {
        # Establish the DB connection
        $connection = Get-DatabaseConnection -Config $Config
        $command = $connection.CreateCommand()

        # Split comma-separated PolicyIds
        $policyIdArray = $PolicyIds -split ',' | ForEach-Object { $_.Trim() }

        foreach ($policyGuid in $policyIdArray) {
            $command.Parameters.Clear()

            # Step 1: Get PolicyID from policies table
            $queryPolicy = @"
SELECT PolicyID, PolicyGuid, PolicyName, PolicyType
FROM policies
WHERE PolicyGuid = @PolicyGuid
  AND Is_Deleted = "True"
  AND ActionType = "Export Policy"
ORDER BY LastUpdatedTime DESC
LIMIT 1;

"@
            $command.CommandText = $queryPolicy
            $command.Parameters.AddWithValue("@PolicyGuid", $policyGuid) | Out-Null

            $reader = $command.ExecuteReader()
            if (-not $reader.Read()) {
                # No matching policy found
                $reader.Close()
                $results += [PSCustomObject]@{
                    PolicyGuid = $policyGuid
                    Status     = "Not Found"
                    Message    = "Policy with GUID '$policyGuid' not found or marked deleted."
                }
                continue
            }

            # Extract PolicyID and details
            $policyRecord = @{}
            for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                $policyRecord[$reader.GetName($i)] = $reader[$i]
            }
            $policyId = $policyRecord["PolicyID"]
            $reader.Close()

            # Step 2: Get BackupFilePath and AssignmentFile from policybackups
            $command.Parameters.Clear()
            $queryBackup = @"
SELECT 
    LEFT(BackupFilePath, 256) AS BackupFilePath,
    LEFT(AssignmentFile, 256) AS AssignmentFile
FROM policybackups
WHERE PolicyID = @PolicyID
ORDER BY BackupTime DESC;
"@
            $command.CommandText = $queryBackup
            $command.Parameters.AddWithValue("@PolicyID", $policyId) | Out-Null

            $reader = $command.ExecuteReader()

            $backups = @()
            while ($reader.Read()) {
                $backupRow = @{
                    BackupFilePath = $reader["BackupFilePath"]
                    AssignmentFile = $reader["AssignmentFile"]
                }
                $backups += [PSCustomObject]$backupRow
            }
            $reader.Close()

            # Combine policy and its backup data
            $results += [PSCustomObject]@{
                PolicyGuid   = $policyGuid
                PolicyID     = $policyId
                PolicyName   = $policyRecord["PolicyName"]
                PolicyType   = $policyRecord["PolicyType"]
                Backups      = $backups
                Status       = "Found"
            }
        }
    }
    catch {
        Write-Warning "Error querying policies: $($_.Exception.Message)"
        return
    }
    finally {
        if ($connection -and $connection.State -eq 'Open') {
            $connection.Close()
        }
    }

    # -------- FORMAT OUTPUT --------
    if ($results) {
        $found    = $results | Where-Object { $_.Status -eq "Found" }
        $notFound = $results | Where-Object { $_.Status -eq "Not Found" }

        if ($found) {
            Write-Host "Policies Found" -ForegroundColor Green
            foreach ($p in $found) {
                Write-Host "- $($p.PolicyGuid)  (PolicyID: $($p.PolicyID))" -ForegroundColor Cyan
                Write-Host "    Name : $($p.PolicyName)"
                Write-Host "    Type : $($p.PolicyType)"
                Write-Host "    Backup Files:" -ForegroundColor DarkGray
                if ($p.Backups.Count -gt 0) {
                    foreach ($b in $p.Backups) {
                        Write-Host "       BackupFilePath: $($b.BackupFilePath)"
                        Write-Host "       AssignmentFile: $($b.AssignmentFile)"
                        Write-Host ""
                    }
                } else {
                    Write-Host "       None"
                }
                Write-Host ""
            }
        }

        if ($notFound) {
            Write-Host "`nPolicies Not Found" -ForegroundColor Red
            foreach ($nf in $notFound) {
                Write-Host "- $($nf.PolicyGuid)" -ForegroundColor Yellow
            }
        }
    }
}
