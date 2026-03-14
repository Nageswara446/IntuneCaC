. "$PSScriptRoot\..\Modules\Common\Get-DatabaseConnection.ps1"
function Get-GitHubReleaseJson {
    
    param (
	[Parameter(Mandatory)][PSCustomObject]$Configuration,
        [Parameter(Mandatory)][string]$rollbackData,
        [Parameter(Mandatory)][string]$WorkFlowID,
        [Parameter(Mandatory)][string]$ReleaseOwner,
        [Parameter(Mandatory)][string]$WorkFlowTaskID

    )
    $connection = $null
    $result = [PSCustomObject]@{
        Success      = $false
        Response     = $null
        ErrorMessage = ""
    }

    $VerbosePreference = 'SilentlyContinue'
    $WarningPreference = 'SilentlyContinue'
    $InformationPreference = 'SilentlyContinue'
    . "C:\URM\WPS_INTUNE_CaC\scripts\Import_Module\Modules\Auth.ps1"

    try {
        $configPath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath "..\Modules\Common\config.json")
        # Read and convert JSON file into PowerShell object
        $jsonConfig = Get-Content -Raw -Path $configPath | ConvertFrom-Json

        # Replace the tenantId under Destination -> ADT with the one from $config
        $jsonConfig.Destination.ADT.tenantId = $Configuration.'ADT-TenantID'
        $jsonConfig.Destination.ADT.clientSecret = $Configuration.'ADT-ClientSecret'
        $jsonConfig.Destination.ADT.clientId = $Configuration.'ADT-ClientID'
        $jsonConfig.Destination.Prod.tenantId = $Configuration.'Prod-TenantID'
        $jsonConfig.Destination.Prod.clientSecret = $Configuration.'Prod-ClientSecret'
        $jsonConfig.Destination.Prod.clientId = $Configuration.'Prod-ClientID'
        $jsonConfig.Source.ADT.tenantId = $Configuration.'ADT-TenantID'
        $jsonConfig.Source.ADT.clientSecret = $Configuration.'ADT-ClientSecret'
        $jsonConfig.Source.ADT.clientId = $Configuration.'ADT-ClientID'
        $jsonConfig.Source.Prod.tenantId = $Configuration.'Prod-TenantID'
        $jsonConfig.Source.Prod.clientSecret = $Configuration.'Prod-ClientSecret'
        $jsonConfig.Source.Prod.clientId = $Configuration.'Prod-ClientID'
        $jsonConfig.Git.GitPAT = $Configuration.'TU-GITPAT'
    
        # Write the updated config back to file (preserves formatting)
        $jsonConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath

        if (-not (Test-Path $configPath)) {
            throw "Missing config file at $configPath"
        }
        $Config = Get-Content -Raw -Path $configPath | ConvertFrom-Json
        
        # Split into lines and trim whitespace
        $lines = $rollbackData -split "`n" | ForEach-Object { $_.Trim() }
        $existsLine = $lines | Where-Object { $_ -match 'Exists\s*:' }
    #Write-Host "existsLine $existsLine"
        # Initialize array variable outside the if block
        $extractedEntries = @()

        # Use regex to extract content after 'Exists :'
        if ($existsLine -match 'Exists\s*:\s*(.*)') {
            $afterExists = $matches[1]

            # Split by semicolon
            $entries = $afterExists -split ';'

            # Store non-empty trimmed entries in the variable
            $extractedEntries = $entries | Where-Object { $_.Trim() }
        }
        #Write-Host "extractedEntries $extractedEntries"
        # Step 3: Split on ';' to get each pair (ignore empty entries)
        $pairs = $extractedEntries -split ';' | Where-Object { $_.Trim() -ne '' }
	    #Write-Host  $pairs 
        foreach ($pair in $pairs) {
            try {
                $parts = $pair -split '\s* - \s*'  # Split on " - " with optional surrounding spaces

                if ($parts.Length -ne 6) {
                    $result.ErrorMessage += "Skipping invalid entry format: '$pair'`n"
                    continue
                }

                $guid = $parts[0].Trim()
                $path = $parts[1].Trim()
                $env = $parts[2].Trim()
                $policyType = $parts[3].Trim()
                $rollback_workflowid = $parts[4].Trim()
                $release_git = $parts[5].Trim()
                $TaskID = $WorkFlowTaskID
                $Action = "Update Policy"
                Write-Host "Processing policy at path: $path"

                if (-not (Test-Path $path)) {
                    $result.ErrorMessage += "File not found at $path for policy $guid. Skipping.`n"
                    continue
                }

                $connection = Get-DatabaseConnection -Config $Config
                $command = $connection.CreateCommand()
                $command.CommandText = @"
                    SELECT *
                    FROM policies p
                    JOIN policyflow pf ON p.PolicyID = pf.DestinationPolicyID
                    WHERE p.PolicyGuid = @PolicyId
                    AND p.WorkflowID = @WorkFlowID
                    AND Is_Deleted = 'False'
                    AND p.ActionType IN ('Create New Policy', 'Update Policy')
"@
                $command.Parameters.AddWithValue("@PolicyId", $guid) | Out-Null
                $command.Parameters.AddWithValue("@WorkFlowID", $rollback_workflowid) | Out-Null

                #Write-Host "SQL Query with parameters replaced:"
                #Write-Host (Get-SqlCommandWithParametersReplaced -Command $command)

                $reader = $command.ExecuteReader()
                if (-not $reader.Read()) {
                    $reader.Close()
                    $result.ErrorMessage += "No record found in DB for Policy ID $guid with workflow $rollback_workflowid.`n"
                    continue
                }

                # Extract data from reader
                $readerPolicyId = $reader["PolicyGuid"]
                $readerPolicyRowId = $reader["PolicyID"]
                $readerPolicyName = $reader["PolicyName"]
                $readerPolicyType = $reader["PolicyType"]
                $readerPolicyVersion = $reader["Version"]
                $readerDestination = $reader["Environment"]
                $readerTenantID = $reader["TenantID"]
                $readerIntunePolicyVersion = $reader["IntunePolicyVersion"]
                $readerSourcePolicyID = $reader["SourcePolicyID"]
                $readerDestinationPolicyID = $reader["DestinationPolicyID"]
                $readerSourceTenantID = $reader["SourceTenantID"]
                $readerDestinationTenantID = $reader["DestinationTenantID"]
                $readerScopeTag = $reader["ScopeTags"]
                $reader.Close()

                $default_endpoint = if ($readerPolicyType -eq "Compliance Policy") {
                    'deviceCompliancePolicies'
                } elseif ($readerPolicyType -eq "Configuration Policy") {
                    'deviceConfigurations'
                } else {
                    $result.ErrorMessage += "Unknown policy type '$readerPolicyType' for Policy ID $guid. Skipping.`n"
                    continue
                }

                $token = Get-AccessToken -Environment $readerDestination -Config $Config
                $headers = @{
                    "Authorization" = "Bearer $token"
                    "Content-Type"  = "application/json"
                }

                $backupPolicy = Get-Content $path -Raw | ConvertFrom-Json

                $version = 'beta'
                $resource = $default_endpoint
                if ($backupPolicy.'@odata.context' -match 'microsoft\.com/([^/]+)/\$metadata') {
                    $version = $matches[1]
                }
                if ($backupPolicy.'@odata.context' -match '#deviceManagement/([^/]+)/') {
                    $temp = $matches[1] -replace '\(.*\)', ''
                    if ($temp -in @('configurationPolicies', 'deviceConfigurations','deviceCompliancePolicies')) {
                        $resource = $temp
                    }
                }

                # Define the additional description string
		$additionalDescription = "Rollback applied with git release path - $release_git . XL Release ID - $WorkFlowID"
		
		# Maximum allowed length for description
		$maxLength = 1000
		
		# Ensure existing description is a string (not null)
		if (-not $backupPolicy.description) {
		    $backupPolicy.description = ""
		}
		
		# Calculate available space for original description after adding additional content and newline
		# Subtract 1 for the newline character
		$availableLength = $maxLength - $additionalDescription.Length - 1
		
		if ($backupPolicy.description.Length -gt $availableLength) {
		    # Truncate existing description from the end to fit within the limit
		    $truncatedDescription = $backupPolicy.description.Substring(0, $availableLength)
		} else {
		    $truncatedDescription = $backupPolicy.description
		}
		
		# Prepend the additional description at the start with a newline
		$backupPolicy.description = $additionalDescription + "`n" + $truncatedDescription


                if ($readerPolicyType -eq "Compliance Policy") {
                    $uri = $Config.ImportPolicyEndpoints.complianceUpdate.Replace("{version}", $version).Replace("{resource}", $resource).Replace("{id}", $guid)
                    $method = "PATCH"
                    $backupPolicy.PSObject.Properties.Remove("scheduledActionsForRule")
                    $assignuri = $Config.ImportPolicyEndpoints.complianceAssign.Replace("{version}", $version).Replace("{resource}", $resource).Replace("{id}", $guid)

                   
                    if ($backupPolicy.PSObject.Properties.Name -contains 'deviceManagementApplicabilityRuleOsEdition') {
                        $backupPolicy.PSObject.Properties.Remove('deviceManagementApplicabilityRuleOsEdition') | Out-Null
                    }

                    $backupPolicy.PSObject.Properties.Remove('id') | Out-Null
                    $backupPolicy.PSObject.Properties.Remove('createdDateTime') | Out-Null
                    $backupPolicy.PSObject.Properties.Remove('lastModifiedDateTime') | Out-Null
                    if ($backupPolicy.PSObject.Properties.Name -contains 'supportsScopeTags') {
                        $backupPolicy.PSObject.Properties.Remove('supportsScopeTags') | Out-Null
                    }


                } elseif ($readerPolicyType -eq "Configuration Policy") {
                    $uri = $Config.ImportPolicyEndpoints.configurationUpdate.Replace("{version}", $version).Replace("{resource}", $resource).Replace("{id}", $guid)
                    $method = "PUT"
                    if ($backupPolicy.'@odata.type' -in @("#microsoft.graph.windows10EndpointProtectionConfiguration", "#microsoft.graph.windows10CustomConfiguration", "#microsoft.graph.windows10GeneralConfiguration", "#microsoft.graph.windowsKioskConfiguration", "#microsoft.graph.windowsHealthMonitoringConfiguration", "#microsoft.graph.windows10ImportedPFXCertificateProfile", "#microsoft.graph.windows81SCEPCertificateProfile", "#microsoft.graph.windows81TrustedRootCertificate")) {
                        $method = "PATCH" 
                    }

                    if ($backupPolicy.PSObject.Properties.Name -contains 'deviceManagementApplicabilityRuleOsEdition') {
                        $backupPolicy.PSObject.Properties.Remove('deviceManagementApplicabilityRuleOsEdition') | Out-Null
                    }
                    $backupPolicy.PSObject.Properties.Remove('id') | Out-Null
                    $backupPolicy.PSObject.Properties.Remove('createdDateTime') | Out-Null
                    $backupPolicy.PSObject.Properties.Remove('lastModifiedDateTime') | Out-Null
                    if ($backupPolicy.PSObject.Properties.Name -contains 'supportsScopeTags') {
                        $backupPolicy.PSObject.Properties.Remove('supportsScopeTags') | Out-Null
                    }

                    $assignuri = $Config.ImportPolicyEndpoints.configurationAssign.Replace("{version}", $version).Replace("{resource}", $resource).Replace("{id}", $guid)

                }
                #Write-Host "assignuri: $assignuri"
                #Write-Host "uri $uri $method"
                $serializedJson = $backupPolicy | ConvertTo-Json -Depth 100
                #Write-Host "serializedJson $serializedJson"
               
                $response = Invoke-RestMethod -Method $method -Uri $uri -Headers $headers -Body $serializedJson
                #Write-Host "response $response"
                # INSERT into DB
                $insertCommand = $connection.CreateCommand()
                $insertCommand.CommandText = @"
                    INSERT INTO unified_release_management.policies (
                        PolicyGuid, PolicyName, PolicyType, TenantID, Environment,
                        Version, IntunePolicyVersion, LastModifiedBy, GitPath,
                        XLRTaskID, WorkflowID, ActionType, Rollback, ScopeTags
                    ) VALUES (
                        @PolicyGuid, @PolicyName, @PolicyType, @TenantID, @Environment,
                        @Version, @IntunePolicyVersion, @LastModifiedBy, @GitPath,
                        @XLRTaskID, @WorkflowID, @ActionType, @Rollback, @ScopeTags
                    )
"@
                $insertCommand.Parameters.AddWithValue("@PolicyGuid", $guid) | Out-Null
                $insertCommand.Parameters.AddWithValue("@PolicyName", $readerPolicyName) | Out-Null
                $insertCommand.Parameters.AddWithValue("@PolicyType", $readerPolicyType) | Out-Null
                $insertCommand.Parameters.AddWithValue("@TenantID", $readerTenantID) | Out-Null
                $insertCommand.Parameters.AddWithValue("@Environment", $readerDestination) | Out-Null
                $insertCommand.Parameters.AddWithValue("@Version", $readerPolicyVersion) | Out-Null
                $insertCommand.Parameters.AddWithValue("@IntunePolicyVersion", $readerIntunePolicyVersion) | Out-Null
                $insertCommand.Parameters.AddWithValue("@LastModifiedBy", $readerLastModifiedBy) | Out-Null
                $insertCommand.Parameters.AddWithValue("@GitPath", $release_git) | Out-Null
                $insertCommand.Parameters.AddWithValue("@XLRTaskID", $TaskID) | Out-Null
                $insertCommand.Parameters.AddWithValue("@WorkflowID", $WorkFlowID) | Out-Null
                $insertCommand.Parameters.AddWithValue("@ActionType", 'Update Policy') | Out-Null
                $insertCommand.Parameters.AddWithValue("@Rollback", 'True') | Out-Null
                $insertCommand.Parameters.AddWithValue("@ScopeTags", $readerScopeTag) | Out-Null
                #Write-Host "SQL Query with parameters replaced:1"
                #Write-Host (Get-SqlCommandWithParametersReplaced -Command $insertCommand)
                $rowsAffected = $insertCommand.ExecuteNonQuery()
                if ($rowsAffected -gt 0) {
                    $insertCommandPolicyFlow = $connection.CreateCommand()
                    $insertCommandPolicyFlow.CommandText = @"
                        INSERT INTO unified_release_management.policyflow (
                            SourcePolicyID, SourceTenantID,
                            DestinationPolicyID, DestinationTenantID
                        ) VALUES (
                            @SourcePolicyID, @SourceTenantID,
                            @DestinationPolicyID, @DestinationTenantID
                        )
"@
                    $insertCommandPolicyFlow.Parameters.AddWithValue("@SourcePolicyID", $readerSourcePolicyID) | Out-Null
                    $insertCommandPolicyFlow.Parameters.AddWithValue("@SourceTenantID", $readerSourceTenantID) | Out-Null
                    $insertCommandPolicyFlow.Parameters.AddWithValue("@DestinationPolicyID", $readerDestinationPolicyID) | Out-Null
                    $insertCommandPolicyFlow.Parameters.AddWithValue("@DestinationTenantID", $readerDestinationTenantID) | Out-Null
                    #Write-Host "SQL Query with parameters replaced:2"
                    #Write-Host (Get-SqlCommandWithParametersReplaced -Command $insertCommandPolicyFlow)
                    $rowAffectedPolicyFlow = $insertCommandPolicyFlow.ExecuteNonQuery()
                    if ($rowAffectedPolicyFlow -gt 0) {
                        $insertCommandRollbackData = $connection.CreateCommand()
                        $insertCommandRollbackData.CommandText = @"
                            INSERT INTO unified_release_management.rollbackrequests (
                                PolicyID, RequestedBy,
                                Status, RollbackTargetFile, RollBackType, RollbackOperation, ReleaseID
                            ) VALUES (
                                @PolicyID, @RequestedBy,
                                @Status, @RollbackTargetFile, @RollBackType, @RollbackOperation, @ReleaseID
                            )
"@
                        $insertCommandRollbackData.Parameters.AddWithValue("@PolicyID", $guid) | Out-Null
                        $insertCommandRollbackData.Parameters.AddWithValue("@RequestedBy", $ReleaseOwner) | Out-Null
                        $insertCommandRollbackData.Parameters.AddWithValue("@Status", 'Completed') | Out-Null
                        $insertCommandRollbackData.Parameters.AddWithValue("@RollbackTargetFile", $release_git) | Out-Null
                        $insertCommandRollbackData.Parameters.AddWithValue("@RollBackType", 'Policy') | Out-Null
                        $insertCommandRollbackData.Parameters.AddWithValue("@RollbackOperation", 'Rollback Update Policy') | Out-Null
                        $insertCommandRollbackData.Parameters.AddWithValue("@ReleaseID", $WorkFlowID) | Out-Null
                        #Write-Host "SQL Query with parameters replaced:2"
                        #Write-Host (Get-SqlCommandWithParametersReplaced -Command $insertCommandRollbackData)
                        $insertCommandRollbackData.ExecuteNonQuery()
                    }


                    # Update result
                    
                    #$result.Message +="Inserted: For policy $guid.`n"
                    if ($null -eq $result.Response) {
                        $result.Response = @()
                    }

                    # Get directory, filename without extension, and extension
                    $directory = Split-Path $path
                    $assignmentfilename = [System.IO.Path]::GetFileNameWithoutExtension($path)
                    $extension = [System.IO.Path]::GetExtension($path)

                    # Construct new file name
                    $newassignmentfilenameFilename = "${assignmentfilename}_assignment$extension"
                    $newPathAssignment = Join-Path $directory $newassignmentfilenameFilename
                    # Output new path (optional)
                    #Write-Output "Modified path: $newPathAssignment"

                    # Check if the file exists
                    if (Test-Path $newPathAssignment) {
                        #Write-Output "File exists: $newPathAssignment"
                        $assignments = Get-Content $newPathAssignment -Raw | ConvertFrom-Json
                        if ($assignments) {
                            # Convert to JSON body
                            # Normalize assignments if they come from a policy export (strip id/source/etc.)
                            $cleanAssignments = foreach ($a in $assignments) {
                                [PSCustomObject]@{
                                    target = $a.target
                                }
                            }

                            $assignmentbody = @{ assignments = $cleanAssignments } | ConvertTo-Json -Depth 10 -Compress

                            #Write-Host "Assignments JSON Body:"
                            #Write-Host $assignmentbody

                            # ===== Call Graph API =====
                            $assignmentresponse = Invoke-RestMethod -Method POST -Uri $assignuri -Headers @{
                                "Authorization" = "Bearer $token"
                                "Content-Type"  = "application/json"
                            } -Body $assignmentbody

                            #Write-Host "Assignments applied successfully!"
                            $assignmentresponse
                        }

                        
                    }
                    $result.Success = $true
                    $result.Response += "Rollback Completed in $readerDestination for $readerPolicyType- $($readerPolicyName) ( Policy GUID - $guid).`n"

                } else {
                    $result.ErrorMessage += "Insert failed: No rows affected for policy $guid.`n"
                }

            } catch {
                $result.ErrorMessage += "Error processing policy $($guid): $($_.Exception.Message)`n"
                if ($_.Exception.Response -ne $null) {
                    try {
                        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                        $result.ErrorMessage += $reader.ReadToEnd() + "`n"
                    } catch {
                        $result.ErrorMessage += "Failed to read error response stream.`n"
                    }
                }
                continue
            }
        }



    } catch {
        $result.ErrorMessage = "Failed to get release or download asset: $($_.Exception.Message)"
        if ($_.Exception.Response -ne $null) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $result.ErrorMessage += "`n" + $reader.ReadToEnd()
        }
        return $result
    }
    finally {
        if ($connection -and $connection.State -eq 'Open') {
            $connection.Close()
            #Write-Host "Closed DB connection"
        }
    }

    return $result
}

#$jsonContent = Get-GitHubReleaseJson

# Print some content from the JSON
#$jsonContent | ConvertTo-Json -Depth 5

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
