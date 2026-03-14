. "$PSScriptRoot\Get-DatabaseConnection.ps1"

function Update-PolicyToIntune {
    param (
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][string]$ScopeTags,
        [Parameter(Mandatory)][psobject]$PolicyJson,
        [Parameter(Mandatory)][psobject]$PolicyType,
        [Parameter(Mandatory)][PSCustomObject]$Config,
        [Parameter(Mandatory)][PSCustomObject]$PolicyId,
        [Parameter(Mandatory)][PSCustomObject]$WorkFlowID,
        [Parameter(Mandatory)][PSCustomObject]$Destination,
        [Parameter(Mandatory)][PSCustomObject]$ExportGitPath,
        [Parameter(Mandatory)][PSCustomObject]$WorkFlowTaskID,
        [Parameter(Mandatory)][PSCustomObject]$PolicyName,
        [Parameter(Mandatory)][PSCustomObject]$Source,
        # [Parameter(Mandatory)][PSCustomObject]$PolicyRowId,
        [Parameter(Mandatory)][PSCustomObject]$Action,
        # [Parameter(Mandatory)][string]$ExistingPolicyGuidinSource,
        [Parameter(Mandatory)][PSCustomObject]$policyVersion
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
        $method = "PATCH"
        $operation = "updated"

        if ($Destination -eq "Prod") {
            $TenantID = $Config.Destination.Prod.tenantId
        }
        else {
            $TenantID = $Config.Destination.ADT.tenantId
        }
        if ($Source -eq "Prod") {
            $SourceTenantID = $Config.Destination.Prod.tenantId
        }
        else {
            $SourceTenantID = $Config.Destination.ADT.tenantId
        }

        if ($PolicyJson.'@odata.context') {
            $odataContext = $PolicyJson.'@odata.context'
            if ($odataContext -match 'microsoft\.com/([^/]+)/\$metadata') {
                $version = $matches[1]
            } else {
                $version = 'beta'
            }

            if ($odataContext -match '#deviceManagement/([^/]+)/') {
                $resource = $matches[1]
                $resource = $resource -replace '\(.*\)', ''
                if ($resource -in @('configurationPolicies', 'deviceConfigurations','deviceCompliancePolicies')) {
                    $extractedResource = $resource
                } else {
                    $extractedResource = $default_endpoint
                }
            } else {
                $extractedResource = $default_endpoint
            }
        }

        if ($policyType -eq "Compliance Policy") {
            # if ($ExistingPolicyGuidinSource -ne "False") {
                $uri = $Config.ImportPolicyEndpoints.complianceUpdate.Replace("{version}", $version).Replace("{resource}", $resource).Replace("{id}", $PolicyId)
                $scheduledActions = $PolicyJson.scheduledActionsForRule
                $PolicyJson.PSObject.Properties.Remove("scheduledActionsForRule") | Out-Null
                if ($PolicyJson.PSObject.Properties.Name -contains 'deviceManagementApplicabilityRuleOsEdition') {
                    $PolicyJson.PSObject.Properties.Remove('deviceManagementApplicabilityRuleOsEdition') | Out-Null
                }
                $PolicyJson.PSObject.Properties.Remove('id') | Out-Null
                $PolicyJson.PSObject.Properties.Remove('createdDateTime') | Out-Null
                $PolicyJson.PSObject.Properties.Remove('lastModifiedDateTime') | Out-Null
                if ($PolicyJson.PSObject.Properties.Name -contains 'supportsScopeTags') {
                    $PolicyJson.PSObject.Properties.Remove('supportsScopeTags') | Out-Null
                }
            # } else {
            #     $uri = $Config.ImportPolicyEndpoints.compliance.Replace("{version}", $version).Replace("{resource}", $resource)
            # }
        }
        elseif ($policyType -eq "Configuration Policy") {
            # if ($ExistingPolicyGuidinSource -ne "False") {
                $method = "PUT"
                $uri = $Config.ImportPolicyEndpoints.configurationUpdate.Replace("{version}", $version).Replace("{resource}", $resource).Replace("{id}", $PolicyId)
                if ($PolicyJson.'@odata.type' -in @("#microsoft.graph.windows10EndpointProtectionConfiguration", "#microsoft.graph.windows10CustomConfiguration", "#microsoft.graph.windows10GeneralConfiguration", "#microsoft.graph.windowsKioskConfiguration", "#microsoft.graph.windowsHealthMonitoringConfiguration", "#microsoft.graph.windows10ImportedPFXCertificateProfile", "#microsoft.graph.windows81SCEPCertificateProfile", "#microsoft.graph.windows81TrustedRootCertificate")) {
                $method = "PATCH" 
                }
        

                if ($PolicyJson.PSObject.Properties.Name -contains 'deviceManagementApplicabilityRuleOsEdition') {
                    $PolicyJson.PSObject.Properties.Remove('deviceManagementApplicabilityRuleOsEdition') | Out-Null
                }
                $PolicyJson.PSObject.Properties.Remove('id') | Out-Null
                $PolicyJson.PSObject.Properties.Remove('createdDateTime') | Out-Null
                $PolicyJson.PSObject.Properties.Remove('lastModifiedDateTime') | Out-Null
                if ($PolicyJson.PSObject.Properties.Name -contains 'supportsScopeTags') {
                    $PolicyJson.PSObject.Properties.Remove('supportsScopeTags') | Out-Null
                }


                
            # } else {
            #     $uri = $Config.ImportPolicyEndpoints.configuration.Replace("{version}", $version).Replace("{resource}", $resource)
            # }
        }
        elseif ($policyType -eq "Administrative Templates") {
            # if ($ExistingPolicyGuidinSource -ne "False") {
                $method = "PATCH"
                $uri = $Config.ImportPolicyEndpoints.administrativeTemplatesUpdate.Replace("{version}", $version).Replace("{resource}", $resource).Replace("{id}", $PolicyId)
                if ($PolicyJson.PSObject.Properties.Name -contains 'deviceManagementApplicabilityRuleOsEdition') {
                    $PolicyJson.PSObject.Properties.Remove('deviceManagementApplicabilityRuleOsEdition') | Out-Null
                }
                $PolicyJson.PSObject.Properties.Remove('id') | Out-Null
                $PolicyJson.PSObject.Properties.Remove('createdDateTime') | Out-Null
                $PolicyJson.PSObject.Properties.Remove('lastModifiedDateTime') | Out-Null
                if ($PolicyJson.PSObject.Properties.Name -contains 'supportsScopeTags') {
                    $PolicyJson.PSObject.Properties.Remove('supportsScopeTags') | Out-Null
                }
            # } else {
            #     $uri = $Config.ImportPolicyEndpoints.administrativeTemplates.Replace("{version}", $version).Replace("{resource}", $resource)
            # }
        }
        else {
            $result.ErrorMessage = "`nUnknown PolicyType '$policyType' for policy ID `$PolicyId` while updating"
            return $result
        }

        $serializedJson = $PolicyJson | ConvertTo-Json -Depth 100

        $response = Invoke-RestMethod -Method $method -Uri $uri -Headers $headers -Body $serializedJson

        if ($Action -eq "Update Policy") {
            # Write-Host "Debug: Before prefix - PolicyName = $PolicyName"
            $PolicyName = "CaC-" + $PolicyName
            # Write-Host "Debug: After prefix - PolicyName = $PolicyName"
            # Write-Host "Debug: PolicyJson.displayName exists = $($PolicyJson.PSObject.Properties.Name -contains 'displayName')"
            # if ($PolicyJson.PSObject.Properties.Name -contains 'displayName') {
            #     Write-Host "Debug: Before update - PolicyJson.displayName = $($PolicyJson.displayName)"
            #     $PolicyJson.displayName = $PolicyName
            #     Write-Host "Debug: After update - PolicyJson.displayName = $($PolicyJson.displayName)"
            # }
        # if ($Action -eq "Update Policy") {
        #     # Write-Host "Debug: Action is Update Policy"
        #     # Write-Host "Debug: Original PolicyName = $PolicyName"
        #     if ($PolicyJson.PSObject.Properties.Name -contains 'displayName') {
        #         Write-Host "Debug: PolicyJson.displayName exists = $($PolicyJson.displayName)"
        #     } else {
        #         Write-Host "Debug: PolicyJson.displayName does not exist"
        #     }}
        if ($Action -eq "Update Policy") {
            # if ($ExistingPolicyGuidinSource -eq "False") {
            # $response_policy_id = $response.id
            # } else {
            $response_policy_id = $PolicyID
            # }
            $response = [PSCustomObject]@{
                id = $response_policy_id
                policyname   = $PolicyName
                policytype = $policyType
                baseID = $PolicyId
                uri = $uri
            }
            $connection = $null
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
    @ScopeTags
)
"@
            $insertCommand.Parameters.AddWithValue("@PolicyGuid", $response_policy_id) | Out-Null
            $insertCommand.Parameters.AddWithValue("@PolicyName", $PolicyName) | Out-Null
            $insertCommand.Parameters.AddWithValue("@PolicyType", $policyType) | Out-Null
            $insertCommand.Parameters.AddWithValue("@TenantID", $TenantID) | Out-Null
            $insertCommand.Parameters.AddWithValue("@Environment", $Destination) | Out-Null
            $insertCommand.Parameters.AddWithValue("@Version", $policyVersion) | Out-Null
            $insertCommand.Parameters.AddWithValue("@IntunePolicyVersion", "1") | Out-Null
            $insertCommand.Parameters.AddWithValue("@LastModifiedBy", "Script") | Out-Null
            $insertCommand.Parameters.AddWithValue("@GitPath", $ExportGitPath) | Out-Null
            $insertCommand.Parameters.AddWithValue("@XLRTaskID", $WorkFlowTaskID) | Out-Null
            $insertCommand.Parameters.AddWithValue("@WorkflowID", $WorkFlowID) | Out-Null
            $insertCommand.Parameters.AddWithValue("@ActionType", 'Update Policy') | Out-Null
            $insertCommand.Parameters.AddWithValue("@ScopeTags", $ScopeTags) | Out-Null
            $rowsAffected = $insertCommand.ExecuteNonQuery()
            if ($rowsAffected -gt 0) {
                $getIdCommand = $connection.CreateCommand()
                $getIdCommand.CommandText = "SELECT LAST_INSERT_ID();"
                $insertedId = $getIdCommand.ExecuteScalar()
                $insertCommandPolicyFlow = $connection.CreateCommand()
                $insertCommandPolicyFlow.CommandText = @"
INSERT INTO unified_release_management.policyflow (
    SourcePolicyID,
    SourceTenantID,
    DestinationPolicyID,
    DestinationTenantID
) VALUES (
    @SourcePolicyID,
    @SourceTenantID,
    @DestinationPolicyID,
    @DestinationTenantID
)
"@
                $insertCommandPolicyFlow.Parameters.AddWithValue("@SourcePolicyID", $PolicyRowId) | Out-Null
                $insertCommandPolicyFlow.Parameters.AddWithValue("@SourceTenantID", $SourceTenantID) | Out-Null
                $insertCommandPolicyFlow.Parameters.AddWithValue("@DestinationPolicyID", $insertedId) | Out-Null
                $insertCommandPolicyFlow.Parameters.AddWithValue("@DestinationTenantID", $TenantID) | Out-Null
                $rowsAffectedPolicyFlow = $insertCommandPolicyFlow.ExecuteNonQuery()
                if ($rowsAffectedPolicyFlow -gt 0) {
                    $result.Success  = $true
                    $result.Response = $response
                    return $result
                }
            } else {
                $result.ErrorMessage = "`nInsert failed. No rows affected for policy ID `$PolicyId` . uri - $uri "
            }
        }
    }}
    catch {
        $result.ErrorMessage = "`nPolicy update failed: $($_.Exception.Message) .  uri - $uri"
        if ($_.Exception.Response -ne $null) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $result.ErrorMessage += "`n" + $reader.ReadToEnd()
        }
        return $result
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
