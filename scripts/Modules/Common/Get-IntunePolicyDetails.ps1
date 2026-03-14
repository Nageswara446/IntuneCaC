function Get-IntunePolicyDetails {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PolicyId,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers
    )

    # Possible endpoints
    $endpoints = @(
        @{ Type = "Compliance Policy"; Url = "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies/$PolicyId"; PolicyType = "deviceCompliancePolicies"; GraphURL = "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies" },
        @{ Type = "Configuration Policy"; Url = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$PolicyId"; PolicyType = "deviceConfigurations"; GraphURL = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations" },
        @{ Type = "Configuration Policy"; Url = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$PolicyId"; PolicyType = "configurationPolicies"; GraphURL = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies" }
    )

    foreach ($endpoint in $endpoints) {
        try {
            $response = Invoke-RestMethod -Uri $endpoint.Url -Headers $Headers -Method GET -ErrorAction Stop

            # Return structured object with JSON and URL
            return [PSCustomObject]@{
                Type        = $endpoint.Type
                Name        = if ($response.PSObject.Properties.Name -contains 'displayName' -and $response.displayName) {
                                $response.displayName
                            } elseif ($response.PSObject.Properties.Name -contains 'name' -and $response.name) {
                                $response.name
                            } else {
                                "N/A"
                            }
                Id          = $response.id
                PolicyType  = $endpoint.PolicyType
                GraphUrl    = $endpoint.GraphURL
                # RawJson     = ($response | ConvertTo-Json -Depth 10 -Compress)
            }
        }
        catch {
            # If first endpoint fails, try the next
            continue
        }
    }

    Write-Output "Policy ID '$PolicyId' was not found as a Compliance or Configuration policy."
}
