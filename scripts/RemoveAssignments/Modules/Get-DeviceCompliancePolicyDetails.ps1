function Get-DeviceCompliancePolicyDetails {
    param($DeviceCompliancePolicy, $ScopeTags, $Headers)
    $Uri = "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies/$($DeviceCompliancePolicy.id)"
    try { $response = Invoke-RestMethod -Uri $Uri -Headers $Headers -Method GET }
    catch { throw "Failed to fetch Compliance Policy details: $_" }

    $scopeTagNames = foreach ($tagId in $response.roleScopeTagIds) {
        if ($ScopeTags.ContainsKey($tagId)) { $ScopeTags[$tagId].DisplayName }
    }
    [PSCustomObject]@{
        Type        = "Compliance Policy"
        Name        = $DeviceCompliancePolicy.displayName
        Id          = $DeviceCompliancePolicy.id
        ScopeTags   = $scopeTagNames -join ', '
        PolicyType  = "deviceCompliancePolicies"
    }
}