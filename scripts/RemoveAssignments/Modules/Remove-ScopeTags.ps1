function Remove-ScopeTags {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PolicyId,

        [Parameter(Mandatory = $true)]
        [string]$PolicyType,  # deviceConfigurations or deviceCompliancePolicies

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers   # Contains Authorization bearer token
    )
    
    $Uri = "https://graph.microsoft.com/beta/deviceManagement/$PolicyType/$PolicyId"
    
    try {
        # Fetch the current policy details
        $policyResponse = Invoke-RestMethod -Uri $Uri -Headers $Headers -Method GET
        
        # Debug output
        Write-Host "Raw JSON Response for Policy ID $PolicyId :"
        $policyResponse | ConvertTo-Json -Depth 4 | Write-Host
        
        if ($policyResponse.roleScopeTagIds -and $policyResponse.roleScopeTagIds.Count -gt 0) {
            Write-Host "Current Scope Tags: $($policyResponse.roleScopeTagIds -join ', ')"
            
            # Prepare PATCH body to clear all scope tags (empty array)
            $body = @{
                "roleScopeTagIds" = @()
            }
            
            $jsonBody = $body | ConvertTo-Json -Depth 3
            
            Write-Host "JSON Body for PATCH request:"
            Write-Host $jsonBody
            
            # Send PATCH request to update the policy and remove scope tags
            Invoke-RestMethod -Uri $Uri -Method PATCH -Body $jsonBody -ContentType "application/json" -Headers $Headers
            
            Write-Host "Successfully removed scope tags from Policy ID: $PolicyId"
        } else {
            Write-Host "No scope tags found for Policy ID: $PolicyId"
        }
    } catch {
        Write-Host "Error updating scope tags for Policy ID: $PolicyId. Error: $_"
    }
}
