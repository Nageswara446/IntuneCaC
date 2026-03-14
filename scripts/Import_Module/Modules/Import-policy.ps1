. "$PSScriptRoot\Get-DatabaseConnection.ps1"

function Import-PolicyToIntune {
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
        [Parameter(Mandatory)][PSCustomObject]$PolicyRowId,
        [Parameter(Mandatory)][PSCustomObject]$Action,
        [Parameter(Mandatory)][string]$ExistingPolicyGuidinSource,
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
        $method = "POST"
        $operation="created"
        if ($Action -eq "Create New Policy") {
            $Action = "Create New Policy"
        }elseif ($Action -eq "Update Policy") {
            $Action = "Update Policy"
        }
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
        #Write-Host "policyType: $policyType" -ForegroundColor Cyan
        if ($policyType -eq "Compliance Policy") {
            $default_endpoint = 'deviceCompliancePolicies'
        }
        if ($policyType -eq "Configuration Policy") {
            $default_endpoint = 'deviceConfigurations'
        }
        if ($PolicyJson.'@odata.context') {
            $odataContext = $PolicyJson.'@odata.context'
            if ($odataContext -match 'microsoft\.com/([^/]+)/\$metadata') {
                $version = $matches[1]
            } else {
                $version = 'beta'
            }

            # Extract resource (the part after '#deviceManagement/' and before next '/')
            if ($odataContext -match '#deviceManagement/([^/]+)/') {
                $resource = $matches[1]

                # Remove any parentheses and content inside them, e.g. (settings())
                $resource = $resource -replace '\(.*\)', ''

                # Now check if resource is one of the two you want
                if ($resource -in @('configurationPolicies', 'deviceConfigurations','deviceCompliancePolicies')) {
                    # Valid resource found
                    $extractedResource = $resource
                } else {
                    $extractedResource = $default_endpoint
                }
            } else {
                $extractedResource = $default_endpoint
            }

            #Host $uri -ForegroundColor Cyan
        }

        if ($policyType -eq "Compliance Policy") {
            if ($Action -eq "Update Policy") {
                #Write-Host $Action -ForegroundColor Cyan
                $scheduledAction = @{
                    ruleName = "PasswordRequired"
                    scheduledActionConfigurations = @(
                        @{
                            "@odata.type"      = "#microsoft.graph.deviceComplianceActionItem"
                            actionType         = "block"
                            gracePeriodHours   = 0
                        }
                    )
                }

                # Add scheduledActionsForRule back into the policy JSON
                $PolicyJson | Add-Member -MemberType NoteProperty -Name "scheduledActionsForRule" -Value @($scheduledAction)
        
                if ($ExistingPolicyGuidinSource -ne "False") {
                    $uri = $Config.ImportPolicyEndpoints.complianceUpdate.Replace("{version}", $version).Replace("{resource}", $resource).Replace("{id}", $ExistingPolicyGuidinSource)
                    $method = "PATCH"
                    $scheduledActions = $PolicyJson.scheduledActionsForRule
                    $PolicyJson.PSObject.Properties.Remove("scheduledActionsForRule")
                    if ($PolicyJson.PSObject.Properties.Name -contains 'deviceManagementApplicabilityRuleOsEdition') {
                        $PolicyJson.PSObject.Properties.Remove('deviceManagementApplicabilityRuleOsEdition') | Out-Null
                    }
                    $PolicyJson.PSObject.Properties.Remove('id') | Out-Null
                    $PolicyJson.PSObject.Properties.Remove('createdDateTime') | Out-Null
                    $PolicyJson.PSObject.Properties.Remove('lastModifiedDateTime') | Out-Null
                    if ($PolicyJson.PSObject.Properties.Name -contains 'supportsScopeTags') {
                        $PolicyJson.PSObject.Properties.Remove('supportsScopeTags') | Out-Null
                    }

                }else{
                    $uri = $Config.ImportPolicyEndpoints.compliance.Replace("{version}", $version).Replace("{resource}", $resource)
                }
                $operation="updated"
            }else{
                
                $uri = $Config.ImportPolicyEndpoints.compliance.Replace("{version}", $version).Replace("{resource}", $resource)
                #Write-Host $uri -ForegroundColor Cyan
                
            }
            #Write-Host "policyType: $uri" -ForegroundColor Cyan
        }
        elseif ($policyType -eq "Configuration Policy") {
            if ($Action -eq "Update Policy") {
                
                if ($ExistingPolicyGuidinSource -ne "False") {
                    $method = "PUT"
                    $uri = $Config.ImportPolicyEndpoints.configurationUpdate.Replace("{version}", $version).Replace("{resource}", $resource).Replace("{id}", $ExistingPolicyGuidinSource)
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

                }else{
                    $uri = $Config.ImportPolicyEndpoints.configuration.Replace("{version}", $version).Replace("{resource}", $resource)
                }
                 $operation="updated"

            }else{
                $uri = $Config.ImportPolicyEndpoints.configuration.Replace("{version}", $version).Replace("{resource}", $resource)
                #Write-Host $uri -ForegroundColor Cyan
            }

           # Write-Host "tract $ExistingPolicyGuidinSource $method $uri"
        }
        else {
            $result.ErrorMessage = "`nUnknown PolicyType '$policyType' for policy ID `$PolicyId` while importing"
            return $result
        }
        # Serialize the updated policy JSON (without scheduledActionsForRule for Compliance Policy)
        

        if ($Action -eq "Create New Policy" -and $policyType -eq "Compliance Policy" ) {
            $scheduledAction = @{
                ruleName = "PasswordRequired"
                scheduledActionConfigurations = @(
                    @{
                        "@odata.type"      = "#microsoft.graph.deviceComplianceActionItem"
                        actionType         = "block"
                        gracePeriodHours   = 0
                    }
                )
            }

            # Add scheduledActionsForRule back into the policy JSON
            $PolicyJson | Add-Member -MemberType NoteProperty -Name "scheduledActionsForRule" -Value @($scheduledAction)
        }

        
        $serializedJson = $PolicyJson | ConvertTo-Json -Depth 100
       # Write-Host "`nSerialized JSON to send (first 500 chars):"
       # Write-Host $serializedJson -ForegroundColor Cyan
        #Write-Host "$method ExistingPolicyGuidinSource- $ExistingPolicyGuidinSource" -ForegroundColor Cyan

        $response = Invoke-RestMethod -Method $method -Uri $uri -Headers $headers -Body $serializedJson
        #Write-Host "ExistingPolicyGuidinSource - $($ExistingPolicyGuidinSource)" -ForegroundColor Green
        if ($Action -eq "Update Policy" ){
            if ($ExistingPolicyGuidinSource -eq "False") {
                $response_policy_id = $response.id
            }else{
                $response_policy_id = $ExistingPolicyGuidinSource
            }
		#Write-Host "$response_policy_id" -ForegroundColor Cyan
            $response = [PSCustomObject]@{
                id = $response_policy_id
                policyname   = $PolicyName
                policytype = $policyType
                baseID = $PolicyId
                uri = $uri
            }
            $connection = $null
            $connection = Get-DatabaseConnection -Config $Config

            # 3. INSERT if record does not exist
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
            #Write-Host "SQL Query with parameters replaced:"
            #Write-Host (Get-SqlCommandWithParametersReplaced -Command $insertCommand)
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
                # Add parameters (replace with actual values)
            

                $insertCommandPolicyFlow.Parameters.AddWithValue("@SourcePolicyID", $PolicyRowId) | Out-Null
                $insertCommandPolicyFlow.Parameters.AddWithValue("@SourceTenantID", $SourceTenantID) | Out-Null
                $insertCommandPolicyFlow.Parameters.AddWithValue("@DestinationPolicyID", $insertedId) | Out-Null
                $insertCommandPolicyFlow.Parameters.AddWithValue("@DestinationTenantID", $TenantID) | Out-Null

                $rowsAffectedPolicyFlow = $insertCommandPolicyFlow.ExecuteNonQuery() 
                if ($rowsAffectedPolicyFlow -gt 0) {
                    $result.Success  = $true
                    $result.Response = $response
                    #Write-Host "Policy inserted into database." -ForegroundColor Green
                    return $result
                }

                
            } else {
                $result.ErrorMessage = "`nInsert failed. No rows affected for policy ID `$PolicyId` . uri - $uri "
            }

            Write-Host "Record inserted successfully."


        }
       
        #Write-Host "Policy $($operation) with ID: $($response.id)" -ForegroundColor Green

        # Insert into database if success
        if ($response -and $response.id -and $Action -eq "Create New Policy" ) {
            #Write-Host "DB IMPORT STARTER:"
            $PolicyGUID = $response.id
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
            # Add parameters (replace with actual values)
           

            $insertCommand.Parameters.AddWithValue("@PolicyGuid", $PolicyGUID) | Out-Null
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
            $insertCommand.Parameters.AddWithValue("@ActionType", $Action) | Out-Null
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
                # Add parameters (replace with actual values)
            

                $insertCommandPolicyFlow.Parameters.AddWithValue("@SourcePolicyID", $PolicyRowId) | Out-Null
                $insertCommandPolicyFlow.Parameters.AddWithValue("@SourceTenantID", $SourceTenantID) | Out-Null
                $insertCommandPolicyFlow.Parameters.AddWithValue("@DestinationPolicyID", $insertedId) | Out-Null
                $insertCommandPolicyFlow.Parameters.AddWithValue("@DestinationTenantID", $TenantID) | Out-Null

                $rowsAffectedPolicyFlow = $insertCommandPolicyFlow.ExecuteNonQuery() 
                if ($rowsAffectedPolicyFlow -gt 0) {
                    $result.Success  = $true
                    $augmentedResponse = [PSCustomObject]@{
                        id     = $response.id
                        policyname   = $PolicyName
                        policytype = $policyType
			baseID = $PolicyId
   			uri = $uri
                    }
                    
                    $result.Response = $augmentedResponse
                    #Write-Host "Policy inserted into database." -ForegroundColor Green
                     return $result
                }

                
            } else {
                $result.ErrorMessage = "`nInsert failed. No rows affected for policy ID `$PolicyId` .  uri - $uri "
            }
           
            
        }
        
    }
    catch {
        $result.ErrorMessage = "`nPolicy creation failed: $($_.Exception.Message) .  uri - $uri"

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
        # Get parameter name and value
        $paramName = $param.ParameterName
        $paramValue = $param.Value

        # Format value for SQL (add quotes if string, handle NULL)
        if ($null -eq $paramValue) {
            $replacement = "NULL"
        }
        elseif ($paramValue -is [string]) {
            # Escape single quotes by doubling them
            $escapedValue = $paramValue.Replace("'", "''")
            $replacement = "'$escapedValue'"
        }
        elseif ($paramValue -is [DateTime]) {
            $replacement = "'$($paramValue.ToString("yyyy-MM-dd HH:mm:ss"))'"
        }
        else {
            $replacement = $paramValue.ToString()
        }

        # Replace all occurrences of the parameter in the query text
        $query = $query -replace [regex]::Escape($paramName), $replacement
    }

    return $query
}
