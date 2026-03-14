# Function: Store-PolicyInDatabase
# Description: Stores policy metadata in a MySQL database.
# Parameters:
#   - Policies (array, Mandatory): Array of policy objects to store.
#   - Config (PSCustomObject, Mandatory): Configuration object containing database connection details and TenantId.

function Store-PolicyInDatabase {
    param (
        [Parameter(Mandatory = $true)][array]$Policies,
        [Parameter(Mandatory = $true)][PSCustomObject]$Config,
        [Parameter(Mandatory = $true)][string]$WorkFlowTaskID,
        [Parameter(Mandatory = $true)][string]$WorkFlowID,
        [Parameter(Mandatory = $true)][string]$Source
    )

    if (-not $Policies -or -not $Config -or -not $WorkFlowTaskID -or -not $WorkFlowID -or -not $Source) {
        return $false
    }

    try {
        $connectionString = "Server=$($Config.Database.Server);Port=$($Config.Database.Port);Database=$($Config.Database.DatabaseName);Uid=$($Config.Database.Username);Pwd=$($Config.Database.Password);SslMode=Required;"

        switch ($Source) {
            "ADT" {
                $TenantId = $Config.Source.ADT.tenantId
            }
            "Prod" {
                $TenantId = $Config.Source.Prod.tenantId
            }
            default {
                return $false
            }
        }

        [void][System.Reflection.Assembly]::LoadWithPartialName("MySql.Data")

        $connection = New-Object MySql.Data.MySqlClient.MySqlConnection
        $connection.ConnectionString = $connectionString
        $connection.Open()

        foreach ($policy in $Policies) {
            if (-not $policy.DisplayName -or -not $policy.PolicyTypeFull -or -not $policy.PolicyId) {
                continue
            }

            $policySubType = $null
            if ($policy.PolicyTypeFull -like "*Compliance Policy*") {
                $policySubType = $null
            }
            elseif ($policy.PolicyTypeFull -like "*Configuration Policy*") {
                if ($policy.PSObject.Properties.Name -contains "templateReference") {
                    $templateRef = $policy.templateReference
                    if ($templateRef -and $templateRef.PSObject.Properties.Name -contains "templateDisplayName" -and $templateRef.templateDisplayName) {
                        $policySubType = $templateRef.templateDisplayName
                    } else {
                        $policySubType = "Setting Catalogue"
                    }
                } else {
                    $policySubType = "Setting Catalogue"
                }
            }

            $checkQuery = "SELECT Version FROM Policies WHERE PolicyGuid = @PolicyGuid"
            $checkCommand = $connection.CreateCommand()
            $checkCommand.CommandText = $checkQuery
            $checkCommand.Parameters.AddWithValue("@PolicyGuid", $policy.PolicyId) | Out-Null

            $existingVersion = $checkCommand.ExecuteScalar()

            if ($existingVersion) {
                if ($existingVersion -match '^v(\d+)\.(\d+)\.(\d+)$') {
                    $major = [int]$matches[1]
                    $minor = [int]$matches[2]
                    $patch = [int]$matches[3] + 1
                    $Version = "v$major.$minor.$patch"
                } else {
                    $Version = "v1.0.0"
                }
            } else {
                $Version = "v1.0.0"
            }

            $query = @"
INSERT INTO Policies (
    PolicyGuid, PolicyName, PolicyType, TenantID, Environment,
    Version, IntunePolicyVersion, LastUpdatedTime, LastModifiedBy,
    ActionType, XLRTaskID, WorkflowID, PolicySubType
) VALUES (
    @PolicyGuid, @PolicyName, @PolicyType, @TenantID, @Environment,
    @Version, @IntunePolicyVersion, @LastUpdatedTime, @LastModifiedBy,
    @ActionType, @XLRTaskID, @WorkflowID, @PolicySubType
)
ON DUPLICATE KEY UPDATE
    PolicyName = @PolicyName,
    PolicyType = @PolicyType,
    TenantID = @TenantID,
    Environment = @Environment,
    Version = @Version,
    IntunePolicyVersion = @IntunePolicyVersion,
    LastUpdatedTime = @LastUpdatedTime,
    LastModifiedBy = @LastModifiedBy,
    ActionType = @ActionType,
    XLRTaskID = @XLRTaskID,
    WorkflowID = @WorkflowID,
    PolicySubType = @PolicySubType
"@

            $command = $connection.CreateCommand()
            $command.CommandText = $query

            $command.Parameters.AddWithValue("@PolicyGuid", $policy.PolicyId) | Out-Null
            $command.Parameters.AddWithValue("@PolicyName", $policy.DisplayName) | Out-Null
            $command.Parameters.AddWithValue("@PolicyType", $policy.PolicyTypeFull) | Out-Null
            $command.Parameters.AddWithValue("@TenantID", $TenantId) | Out-Null
            $command.Parameters.AddWithValue("@Environment", $Source) | Out-Null
            $command.Parameters.AddWithValue("@Version", $Version) | Out-Null
            $command.Parameters.AddWithValue("@IntunePolicyVersion", 1) | Out-Null
            $command.Parameters.AddWithValue("@LastUpdatedTime", (Get-Date -Format "yyyy-MM-dd HH:mm:ss")) | Out-Null
            $command.Parameters.AddWithValue("@LastModifiedBy", "Script") | Out-Null
            $command.Parameters.AddWithValue("@ActionType", "Export Policy") | Out-Null
            $command.Parameters.AddWithValue("@WorkFlowTaskID", $WorkFlowTaskID) | Out-Null
            $command.Parameters.AddWithValue("@PolicySubType", $policySubType) | Out-Null
            $command.Parameters.AddWithValue("@XLRTaskID", $WorkFlowTaskID) | Out-Null
            $command.Parameters.AddWithValue("@WorkflowID", $WorkFlowID) | Out-Null

            $command.ExecuteNonQuery() | Out-Null
        }

        $connection.Close()
        return $true
    }
    catch {
        return $false
    }
}



