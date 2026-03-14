function GetPolicyDetails {
    param (
        [Parameter(Mandatory)][string]$PolicyIds,   # Comma-separated IDs
        [Parameter(Mandatory)][PSCustomObject]$Config
    )

    $connection = $null
    $results = @()

    try {
        # Establish the DB connection
        $connection = Get-DatabaseConnection -Config $Config
        $command = $connection.CreateCommand()

        # Split PolicyIds into array
        $policyIdArray = $PolicyIds -split ',' | ForEach-Object { $_.Trim() }

        foreach ($policyId in $policyIdArray) {
            $command.Parameters.Clear()

            # Query latest record for each policy
            $query = @"
SELECT PolicyGuid, PolicyName, PolicyType
FROM policies 
WHERE PolicyGuid = @PolicyId 
AND Is_Deleted = "False"
ORDER BY LastUpdatedTime DESC 
LIMIT 1;
"@
            $command.CommandText = $query
            $command.Parameters.AddWithValue("@PolicyId", $policyId) | Out-Null

            $reader = $command.ExecuteReader()

            if ($reader.Read()) {
                $row = @{ PolicyGuid = $policyId }
                for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                    $columnName = $reader.GetName($i)
                    $row[$columnName] = $reader[$i]
                }
                $results += [PSCustomObject]$row
            }
            else {
                # Return a "not found" object for missing/deleted policy
                $results += [PSCustomObject]@{
                    PolicyGuid = $policyId
                    Status     = "Not Found"
                    Message    = "Policy with ID '$policyId' does not exist or is marked as deleted."
                }
            }
            $reader.Close()
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
        $found    = $results | Where-Object { $_.Status -ne "Not Found" }
        $notFound = $results | Where-Object { $_.Status -eq "Not Found" }

        if ($found) {
            Write-Host "Policy Found" -ForegroundColor Green
            foreach ($policy in $found) {
                Write-Host "- $($policy.PolicyGuid)" -ForegroundColor Cyan
                foreach ($prop in $policy.PSObject.Properties | Where-Object { $_.Name -notin @("PolicyGuid","Status","Message") }) {
                    Write-Host "    $($prop.Name): $($prop.Value)"
                }
            }
        }

        if ($notFound) {
            if ($found) { Write-Host "" }  # line break between sections if both exist
            Write-Host "Policy Not Found" -ForegroundColor Red
            foreach ($nf in $notFound) {
                Write-Host "- $($nf.PolicyGuid)" -ForegroundColor Yellow
            }
        }
    }
}
