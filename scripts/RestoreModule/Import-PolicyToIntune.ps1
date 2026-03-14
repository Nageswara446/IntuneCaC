function Import-PolicyToIntune {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$AccessToken,
        [Parameter(Mandatory)][psobject]$PolicyJson,
        [Parameter(Mandatory)][string]$PolicyType,
        [Parameter(Mandatory)][PSCustomObject]$Config,
        [Parameter(Mandatory)][string]$Environment,
        [Parameter()][int]$TimeoutSec = 60,
        [Parameter()][switch]$DebugPayload
    )

    $result = [PSCustomObject]@{
        Success      = $false
        Response     = $null
        ErrorMessage = ""
    }

    try {
        # Ensure JSON is an object
        if ($PolicyJson -is [string]) {
            try {
                $PolicyJson = $PolicyJson | ConvertFrom-Json -ErrorAction Stop
                Write-Output "[DEBUG] PolicyJson successfully converted from string"
            } catch {
                $result.ErrorMessage = "PolicyJson could not be parsed as JSON. Raw input length: $($PolicyJson.Length)"
                return $result
            }
        }

        # Validate
        if (-not $PolicyJson -or $PolicyJson.PSObject.Properties.Count -eq 0) {
            $result.ErrorMessage = "PolicyJson is empty or malformed. Skipping API call."
            return $result
        }
        
        # # Default endpoints based on PolicyType
        switch ($PolicyType) {
            "Compliance Policy"    { $defaultEndpoint = "deviceCompliancePolicies" }
            "Configuration Policy" { $defaultEndpoint = "deviceConfigurations" }
            default {
                $result.ErrorMessage = "Unknown PolicyType '$PolicyType' for policy importing"
                return $result
            }
        }

        # Extract version and resource from @odata.context if available
        $version = "beta"
        $resource = $defaultEndpoint
        if ($PolicyJson.'@odata.context') {
            $odataContext = $PolicyJson.'@odata.context'
            
            if ($odataContext -match 'microsoft\.com/([^/]+)/\$metadata') {
                $version = $matches[1]
            }

            if ($odataContext -match '#deviceManagement/([^/]+)/') {
                $extractedResource = $matches[1] -replace '\(.*\)', ''
                if ($extractedResource -in @('configurationPolicies', 'deviceConfigurations','deviceCompliancePolicies')) {
                    $resource = $extractedResource
                }
            }
        }

        # # Build URI
        $uri = switch ($PolicyType) {
            "Compliance Policy"    { $Config.ImportPolicyEndpoints.compliance.Replace("{version}", $version).Replace("{resource}", $resource) }
            "Configuration Policy" { $Config.ImportPolicyEndpoints.configuration.Replace("{version}", $version).Replace("{resource}", $resource) }
        }

        Write-Output "Import URL: $uri"

        # # Add scheduledActionsForRule only for compliance policies
        if ($PolicyType -eq "Compliance Policy" -and -not $PolicyJson.scheduledActionsForRule) {
            $PolicyJson | Add-Member -MemberType NoteProperty -Name "scheduledActionsForRule" -Value @(
                @{
                    ruleName = "PasswordRequired"
                    scheduledActionConfigurations = @(
                        @{
                            "@odata.type"    = "#microsoft.graph.deviceComplianceActionItem"
                            actionType       = "block"
                            gracePeriodHours = 0
                        }
                    )
                }
            ) -Force
        }

        # Remove system-generated fields
        $policyJson.PSObject.Properties.Remove('id')
        $policyJson.PSObject.Properties.Remove('createdDateTime')
        $policyJson.PSObject.Properties.Remove('lastModifiedDateTime')

        # # Serialize JSON
        $serializedJson = $PolicyJson | ConvertTo-Json -Depth 20 -Compress
        
        # Prepare headers
        $headers = @{
            "Authorization" = "Bearer $AccessToken"
            "Content-Type"  = "application/json"
        }

        # Call Graph API with timeout
        try {
            $response = Invoke-RestMethod -Method POST -Uri $uri -Headers $headers -Body $serializedJson -TimeoutSec $TimeoutSec
        } catch {
            $result.ErrorMessage = "API call failed: $($_.Exception.Message)"
            if ($_.Exception.Response) {
                try {
                    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                    $result.ErrorMessage += "`n" + $reader.ReadToEnd()
                } catch {}
            }
            return $result
        }

        # # Success check
        if ($response -and $response.id) {
            $result.Success  = $true
            $result.Response = $response
        } else {
            $result.ErrorMessage = "API call completed but no 'id' returned."
        }

        return $result
    }
    catch {
        $result.ErrorMessage = "Policy creation failed: $($_.Exception.Message)"
        return $result
    }
}
