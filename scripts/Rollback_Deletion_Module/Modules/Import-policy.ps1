. "$PSScriptRoot\Get-DatabaseConnection.ps1"

function Import-PolicyToIntune {
    param (
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][psobject]$PolicyJson,
        [Parameter(Mandatory)][PSCustomObject]$Config,
        [Parameter(Mandatory)][PSCustomObject]$WorkFlowID,
        [Parameter(Mandatory)][PSCustomObject]$WorkFlowTaskID,
        [Parameter(Mandatory)][PSCustomObject]$Destination,
        [Parameter(Mandatory)][string]$PolicyName,
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Action = "Create New Policy",
        [Parameter(Mandatory)][string]$ScopeTags,
        [Parameter(Mandatory)][PSCustomObject]$GitPath
    )

    $result = [PSCustomObject]@{
        Success      = $false
        Response     = $null
        ErrorMessage = ""
    }

    try {
    if (-not $PolicyJson -or $PolicyJson.PSObject.Properties.Count -eq 0) {
        $result.ErrorMessage = "`nPolicyJson is empty or malformed. Skipping API call."
        return $result
    }

    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
    }

    # Determine endpoint based on policy type
    $policyType = if ($PolicyJson.'@odata.type' -match "CompliancePolicy") { "Compliance Policy" } else { "Configuration Policy" }
    # Write-Host "DEBUG: PolicyType: $policyType" -ForegroundColor Yellow
    $default_endpoint = if ($policyType -eq "Compliance Policy") { 'deviceCompliancePolicies' } else { 'deviceConfigurations' }

    $odataContext = $PolicyJson.'@odata.context'
    $version = 'beta'
    $resource = $default_endpoint
    if ($odataContext -match 'microsoft\.com/([^/]+)/\$metadata') { $version = $matches[1] }
    if ($odataContext -match '#deviceManagement/([^/]+)/') { $resource = $matches[1] -replace '\(.*\)', '' }

    # Debug logging
    # Write-Host "DEBUG: Version: $version, Resource: $resource" -ForegroundColor Yellow

    # Set URI for creating new policy
    $uri = if ($policyType -eq "Compliance Policy") {
        $Config.ImportPolicyEndpoints.compliance.Replace("{version}", $version).Replace("{resource}", $resource)
    } else {
        $Config.ImportPolicyEndpoints.configuration.Replace("{version}", $version).Replace("{resource}", $resource)
    }

    # Add scheduled action for Compliance Policy
    if ($policyType -eq "Compliance Policy") {
        $scheduledAction = @{
            ruleName = "PasswordRequired"
            scheduledActionConfigurations = @(
                @{
                    "@odata.type"    = "#microsoft.graph.deviceComplianceActionItem"
                    actionType       = "block"
                    gracePeriodHours = 0
                }
            )
        }
        $PolicyJson | Add-Member -MemberType NoteProperty -Name "scheduledActionsForRule" -Value @($scheduledAction)
        # Write-Host "DEBUG: Added scheduledActionsForRule for compliance policy" -ForegroundColor Yellow
    }

    # Exclude read-only properties that shouldn't be sent in creation requests
    $excludedProperties = @('id', 'createdDateTime', 'lastModifiedDateTime', 'version', 'supportsScopeTags', 'creationSource', 'priorityMetaData')
    $cleanedPolicyJson = $PolicyJson | Select-Object -Property * -ExcludeProperty $excludedProperties

    # Serialize JSON and call Intune API
    $serializedJson = $cleanedPolicyJson | ConvertTo-Json -Depth 100

    # Debug logging
    # Write-Host "DEBUG: URI: $uri" -ForegroundColor Yellow
    # Write-Host "DEBUG: Serialized JSON first 500 chars: $($serializedJson.Substring(0, [Math]::Min(500, $serializedJson.Length)))" -ForegroundColor Yellow

    $response = Invoke-RestMethod -Method "POST" -Uri $uri -Headers $headers -Body $serializedJson

    # Insert policy into database
    $PolicyGUID = $response.id
    $connection = Get-DatabaseConnection -Config $Config
    $insertCommand = $connection.CreateCommand()
    $insertCommand.CommandText = @"
 INSERT INTO unified_release_management.policies (
 PolicyGuid,
 PolicyName,
 PolicyType,
 TenantID,
 Environment,
 Version,
 IntunePolicyVersion,
 LastModifiedBy,
 GitPath,
 XLRTaskID,
 WorkflowID,
 ActionType,
 Rollback,
 ScopeTags
 ) VALUES (
 @PolicyGuid,
 @PolicyName,
 @PolicyType,
 @TenantID,
 @Environment,
 @Version,
 @IntunePolicyVersion,
 @LastModifiedBy,
 @GitPath,
 @XLRTaskID,
 @WorkflowID,
 @ActionType,
 @Rollback,
 @ScopeTags
 )
"@

    $TenantID = if ($Destination -eq "Prod") { $Config.Destination.Prod.tenantId } else { $Config.Destination.ADT.tenantId }

    $insertCommand.Parameters.AddWithValue("@PolicyGuid", $PolicyGUID) | Out-Null
    $insertCommand.Parameters.AddWithValue("@PolicyName", $PolicyName) | Out-Null
    $insertCommand.Parameters.AddWithValue("@PolicyType", $policyType) | Out-Null
    $insertCommand.Parameters.AddWithValue("@TenantID", $TenantID) | Out-Null
    $insertCommand.Parameters.AddWithValue("@Environment", $Destination) | Out-Null
    $insertCommand.Parameters.AddWithValue("@Version", "v1.0.0") | Out-Null
    $insertCommand.Parameters.AddWithValue("@IntunePolicyVersion", "1") | Out-Null
    $insertCommand.Parameters.AddWithValue("@LastModifiedBy", "Script") | Out-Null
    $insertCommand.Parameters.AddWithValue("@GitPath", "https://github.developer.allianz.io/WorkplaceServices/WPS_INTUNE_CaC.git/$GitPath") | Out-Null
    $insertCommand.Parameters.AddWithValue("@XLRTaskID", $WorkFlowTaskID) | Out-Null
    $insertCommand.Parameters.AddWithValue("@WorkflowID", $WorkFlowID) | Out-Null
    $insertCommand.Parameters.AddWithValue("@ActionType", $Action) | Out-Null
    $insertCommand.Parameters.AddWithValue("@Rollback", "True") | Out-Null
    $insertCommand.Parameters.AddWithValue("@ScopeTags", $ScopeTags) | Out-Null

    $rowsAffected = $insertCommand.ExecuteNonQuery()

    if ($rowsAffected -gt 0) {
        $result.Success  = $true
        $result.Response = [PSCustomObject]@{
            id         = $PolicyGUID
            policyname = $PolicyName
            policytype = $policyType
            uri        = $uri
        }
    } else {
        $result.ErrorMessage = "`nInsert failed. No rows affected for policy $PolicyName. uri - $uri"
    }

    return $result

    } catch {
        $result.ErrorMessage = "`nPolicy creation failed: $($_.Exception.Message) . uri - $uri"
        # Write-Host "Full exception details: $($_.Exception | Out-String)" -ForegroundColor Red
        if ($_.Exception -is [System.Net.WebException] -and $_.Exception.Response) {
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $errorBody = $reader.ReadToEnd()
                Write-Host "API Error Response Body: $errorBody" -ForegroundColor Red
            } catch { }
        }
        return $result
    }
}

