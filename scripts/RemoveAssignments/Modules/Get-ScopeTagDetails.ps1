function Get-ScopeTagDetails {
    param($Headers)
    $Uri = "https://graph.microsoft.com/beta/deviceManagement/roleScopeTags"
    try {
        $response = Invoke-RestMethod -Uri $Uri -Headers $Headers -Method GET
    } catch {
        throw "Failed to get scope tags: $_"
    }
    $details = @{}
    foreach ($tag in $response.value) {
        $details[$tag.id] = @{
            DisplayName = $tag.displayName
            Description = $tag.description
        }
    }
    return $details
}
