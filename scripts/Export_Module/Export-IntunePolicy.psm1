# Module: IntunePolicyExporter
# Description: PowerShell module to export Intune policies, store them in a database, and push to GitHub.

# ------------------- LOGGING FUNCTION -------------------
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = "White"

    switch ($Level.ToUpper()) {
        "INFO"  { $color = "Cyan" }
        "WARN"  { $color = "Yellow" }
        "ERROR" { $color = "Red" }
        "DEBUG" { $color = "Gray" }
    }

    Write-Host "[$timestamp][$Level] $Message" -ForegroundColor $color
}

# Import all helper function scripts (must be in the same folder)
$functionFiles = @(
    "Invoke-WithRetry.ps1",
    "Get-AccessToken.ps1",
    "Export-IntunePolicyByIdOrName.ps1",
    "Export-PolicyAssignments.ps1",
    "Validate-PolicyJson.ps1",
    "Store-PolicyInDatabase.ps1",
    "Verify-ExportCompleteness.ps1",
    "Push-PolicyJsonToGitHub.ps1"
)

foreach ($file in $functionFiles) {
    $filePath = Join-Path $PSScriptRoot $file
    if (Test-Path $filePath) {
        . $filePath
    } else {
        . $filePath
    }
}

# ------------------- Main Function: Export-IntunePolicy -------------------
function Export-IntunePolicy {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string]$PolicySearchValue,
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$WorkFlowID,
        [Parameter(Mandatory = $true)][string]$WorkFlowTaskID,
        [Parameter(Mandatory = $false)][hashtable]$Configuration,
        [Parameter(Mandatory = $false)][string]$OptionalData,
        [Parameter(Mandatory = $false)][string]$changeId
    )

    # ------------------- CONFIG SETUP -------------------
    try {
        if ($Source -eq "Prod") {
            $TenantId     = $Configuration.Source.Prod.tenantId
            $ClientId     = $Configuration.Source.Prod.clientId
            $ClientSecret = $Configuration.Source.Prod.clientSecret
            $BasePath     = "windows10orlater/Prod_Tenant/Prod/policies"
        } else {
            $TenantId     = $Configuration.Source.ADT.tenantId
            $ClientId     = $Configuration.Source.ADT.clientId
            $ClientSecret = $Configuration.Source.ADT.clientSecret
            $BasePath     = "windows10orlater/ADT_Tenant/policies"
        }

        $configPath = "$PSScriptRoot\export-policy-config.json"
        $jsonConfig = Get-Content -Raw -Path $configPath | ConvertFrom-Json

        # Overwrite config values with workflow input
        $jsonConfig.Source.ADT.tenantId      = $Configuration.'ADT-TenantID'
        $jsonConfig.Source.ADT.clientSecret  = $Configuration.'ADT-ClientSecret'
        $jsonConfig.Source.ADT.clientId      = $Configuration.'ADT-ClientID'
        $jsonConfig.Source.Prod.tenantId     = $Configuration.'Prod-TenantID'
        $jsonConfig.Source.Prod.clientSecret = $Configuration.'Prod-ClientSecret'
        $jsonConfig.Source.Prod.clientId     = $Configuration.'Prod-ClientID'
        $jsonConfig.BaseRepoPath             = $BasePath
        $jsonConfig.Git.GitPAT               = $Configuration.'TU-GITPAT'

        $jsonConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath
    }
    catch {
        return
    }

    if (-not (Test-Path $configPath)) {
        return
    }

    $Config    = Get-Content -Raw -Path $configPath | ConvertFrom-Json
    $GitHubPAT = $Config.Git.GitPAT

    # ------------------- POLICY ID EXTRACTION -------------------
    if ($null -ne $OptionalData -and $OptionalData -ne '') {
        $pattern = '(?is)imported\s+successfully\s+with\s+ID:\s*([a-f0-9\-]{36})'
    
        $matches = [regex]::Matches($OptionalData, $pattern)
    
        $imported_policy = ($matches | ForEach-Object { $_.Groups[1].Value }) -join ','
    
        $PolicySearchValue = $imported_policy
    }

    $policyIds          = $PolicySearchValue -split ',' | ForEach-Object { $_.Trim() }
    $successfulPolicies = @()
    $failedPolicies     = @()

    $invalidIds = $policyIds | Where-Object { $_ -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' }
    if ($invalidIds.Count -gt 0) {
        $failedPolicies += $invalidIds
        $policyIds = $policyIds | Where-Object { $_ -notin $invalidIds }
    }

    if (-not $Config.GraphApi.Endpoints) {
        $failedPolicies += $policyIds
        return
    }

    $endpointsHashtable = @{ }
    foreach ($key in $Config.GraphApi.Endpoints.PSObject.Properties.Name) {
        $endpointsHashtable[$key] = $Config.GraphApi.Endpoints.$key
    }

    $timestampId    = Get-Date -Format "yyyyMMddHHmmss"
    $tempExportPath = ".\TempExport_$timestampId"

    try {
        # ------------------- GET TOKEN -------------------
        $token = Invoke-WithRetry -Action {
            Get-AccessToken -Config $Config -Source $Source
        } -ActionName "Get Access Token"

        # ------------------- EXPORT POLICIES -------------------
        foreach ($policyId in $policyIds) {
            $exported = Invoke-WithRetry -Action {
                Export-IntunePolicyByIdOrName -AccessToken $token -SearchValues $policyId -Endpoints $endpointsHashtable -TempExportPath $tempExportPath -Config $Config
            } -ActionName "Export Intune Policy ($policyId)"

            if ($exported) {
                $successfulPolicies += $exported
            } else {
                $failedPolicies += $policyId
            }
        }

        # ------------------- EXPORT ASSIGNMENTS -------------------
        if ($successfulPolicies) {
            $assignments = Invoke-WithRetry -Action {
                Export-PolicyAssignments -AccessToken $token -Policies $successfulPolicies -AssignmentEndpointBase $Config.GraphApi.AssignmentEndpointBase -TempExportPath $tempExportPath -Config $Config
            } -ActionName "Export Policy Assignments"

            # ------------------- STORE IN DATABASE -------------------
            $dbSuccess = Invoke-WithRetry -Action {
                Store-PolicyInDatabase -Policies $successfulPolicies -Config $Config -WorkFlowTaskID $WorkFlowTaskID -WorkFlowID $WorkFlowID -Source $Source
            } -ActionName "Store Policy in Database"

            if ($dbSuccess) {
                $finalExportPath = ".\PolicyExport_$timestampId"
                if (Test-Path $finalExportPath) {
                    Remove-Item -Path $finalExportPath -Recurse -Force
                }
                Move-Item -Path $tempExportPath -Destination $finalExportPath

                # ------------------- PUSH TO GITHUB -------------------
                $gitSuccess = Invoke-WithRetry -Action {
                    Push-PolicyJsonToGitHub -GitHubPAT $GitHubPAT -Policies $successfulPolicies -BaseExportPath $finalExportPath -AssignmentsPath "$finalExportPath\Assignments" -Config $Config -changeId $changeId -WorkFlowTaskID $WorkFlowTaskID -WorkFlowID $WorkFlowID
                } -ActionName "Push Policy to GitHub"

                if ($gitSuccess) {
                    try {
                        # Build the MySQL connection string
                        $connectionString = "Server=$($Config.Database.Server);Port=$($Config.Database.Port);Database=$($Config.Database.DatabaseName);Uid=$($Config.Database.Username);Pwd=$($Config.Database.Password);SslMode=Required;Charset=utf8mb4;"
                        # Load MySQL assembly and open connection
                        [void][System.Reflection.Assembly]::LoadWithPartialName("MySql.Data")
                        $connection = New-Object MySql.Data.MySqlClient.MySqlConnection
                        $connection.ConnectionString = $connectionString
                        $connection.Open()
                        foreach ($policy in $successfulPolicies) {
                            # try {
                            # --- First query: Fetch GitPath ---
                            $query = "SELECT GitPath
                            FROM Policies
                            WHERE PolicyGuid = @PolicyGuid
                            AND GitPath IS NOT NULL
                            ORDER BY LastUpdatedTime DESC
                            LIMIT 1;
                            "
                            # $query = "SELECT GitPath FROM Policies WHERE PolicyGuid = @PolicyGuid ORDER BY LastUpdatedTime DESC LIMIT 1 OFFSET 1"
                            $command = $connection.CreateCommand()
                            $command.CommandText = $query
                            $command.Parameters.AddWithValue("@PolicyGuid", $policy.PolicyId) | Out-Null
                            $command.Parameters.AddWithValue("@WorkFlowID", $WorkFlowID) | Out-Null
                            $command.Parameters.AddWithValue("@XLRTaskID", $WorkFlowTaskID) | Out-Null
                            # Write-Host "SQL Query with parameters replaced:"
                            # Write-Host (Get-SqlCommandWithParametersReplaced -Command $command)
                            $gitPath = $command.ExecuteScalar()
                            if ($gitPath) {
                                $policy | Add-Member -NotePropertyName GitPath -NotePropertyValue $gitPath -Force

                                # --- Second query: Check for NULL GitPaths for the same PolicyGuid ---
                                $checkQuery = "SELECT * FROM Policies WHERE PolicyGuid = @PolicyGuid AND GitPath IS NULL"
                                $checkCommand = $connection.CreateCommand()
                                $checkCommand.CommandText = $checkQuery
                                $checkCommand.Parameters.AddWithValue("@PolicyGuid", $policy.PolicyId) | Out-Null

                                $checkResult = $checkCommand.ExecuteReader()
                                $hasNulls = $checkResult.HasRows
                                $checkResult.Close()   # MUST close before next command

                                if ($hasNulls) {
                                    $updateQuery = "UPDATE Policies SET GitPath = @GitPath WHERE PolicyGuid = @PolicyGuid AND GitPath IS NULL"
                                    $updateCommand = $connection.CreateCommand()
                                    $updateCommand.CommandText = $updateQuery
                                    $updateCommand.Parameters.AddWithValue("@GitPath", $gitPath) | Out-Null
                                    $updateCommand.Parameters.AddWithValue("@PolicyGuid", $policy.PolicyId) | Out-Null

                                    $rowsUpdated = $updateCommand.ExecuteNonQuery()
                                    
                                }
                            } else {
                                Write-Host "No GitPath found in database for $($policy.PolicyId)."
                            }
                            # }
                            # catch {
                            #     Write-Host "Error processing PolicyGuid $($policy.PolicyId): $($_.Exception.Message)"
                            #     continue
                            # }
                        }

                        $connection.Close()
                    }
                    catch {
                        Write-Error "An error occurred while accessing the database: $($_.Exception.Message)"
                        if ($connection.State -eq 'Open') {
                            $connection.Close()
                        }
                    }



                } else {
                    $failedPolicies += $successfulPolicies | ForEach-Object { $_.PolicyId }
                    $successfulPolicies = @()
                }
            } else {
                $failedPolicies += $successfulPolicies | ForEach-Object { $_.PolicyId }
                $successfulPolicies = @()
                if (Test-Path $tempExportPath) {
                    Remove-Item -Path $tempExportPath -Recurse -Force
                }
            }
        }
    } catch {
        $failedPolicies += $policyIds | Where-Object { $_ -notin ($successfulPolicies | ForEach-Object { $_.PolicyId }) }
        if (Test-Path $tempExportPath) {
            Remove-Item -Path $tempExportPath -Recurse -Force
        }
    }

    # ------------------- FINAL OUTPUT -------------------
    Write-Host "`n========== Export Summary ==========" -ForegroundColor Yellow

    if ($successfulPolicies.Count -gt 0) {
        Write-Host "`nExported Policies:" -ForegroundColor Green
        $successfulPolicies | ForEach-Object {
            Write-Host "- Exported Successfully: $($_.PolicyId) - GitPath: $($_.GitPath)" -ForegroundColor Green
        }
    }

    if ($failedPolicies.Count -gt 0) {
        Write-Host "`nFailed to export Policy:" -ForegroundColor Magenta
        $failedPolicies | ForEach-Object {
            Write-Host "- Export failed: $_" -ForegroundColor Magenta
        }
    }

    Write-Host "=====================================" -ForegroundColor Yellow
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
        } elseif ($paramValue -is [string]) {
            $escapedValue = $paramValue.Replace("'", "''")
            $replacement = "'$escapedValue'"
        } elseif ($paramValue -is [DateTime]) {
            $replacement = "'$($paramValue.ToString("yyyy-MM-dd HH:mm:ss"))'"
        } else {
            $replacement = $paramValue.ToString()
        }

        $query = $query -replace [regex]::Escape($paramName), $replacement
    }

    return $query
}

# Export all module functions
Export-ModuleMember -Function Export-IntunePolicy, Invoke-WithRetry, Get-AccessToken, Export-IntunePolicyByIdOrName, Export-PolicyAssignments, Validate-PolicyJson, Store-PolicyInDatabase, Verify-ExportCompleteness, Push-PolicyJsonToGitHub, Write-Log
