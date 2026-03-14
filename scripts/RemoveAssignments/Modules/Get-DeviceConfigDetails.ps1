function Get-DeviceConfigDetails {
    param(
        [Parameter(Mandatory = $true)]$DeviceConfig,
        [Parameter(Mandatory = $true)]$ScopeTags,
        [Parameter(Mandatory = $true)]$Headers
    )

    # Default policy type
    $policyType = "deviceConfigurations"
    $response = $null

    # First try: classic device configuration
    $uri1 = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$($DeviceConfig.id)"
    # Second try: settings catalog configuration
    $uri2 = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($DeviceConfig.id)"

    try {
        $response = Invoke-RestMethod -Uri $uri1 -Headers $Headers -Method GET -ErrorAction Stop
        $policyType = "deviceConfigurations"
    }
    catch {
        try {
            $response = Invoke-RestMethod -Uri $uri2 -Headers $Headers -Method GET -ErrorAction Stop
            $policyType = "configurationPolicies"
        }
        catch {
            throw "Failed to fetch Device Config Policy details from both endpoints: $_"
        }
    }

    # Resolve scope tag names
    $scopeTagNames = foreach ($tagId in $response.roleScopeTagIds) {
        if ($ScopeTags.ContainsKey($tagId)) {
            $ScopeTags[$tagId].DisplayName
        }
    }

    # Normalize object
    [PSCustomObject]@{
        Type       = "Configuration Policy"
        Name       = $response.displayName
        Id         = $response.id
        ScopeTags  = $scopeTagNames -join ', '
        PolicyType = $policyType
    }
}
