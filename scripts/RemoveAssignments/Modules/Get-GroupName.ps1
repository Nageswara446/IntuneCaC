function Get-GroupName {
    param([string]$GroupId, $Headers)
    if (-not $GroupId) { return "" }
    try {
        $uri = "https://graph.microsoft.com/v1.0/groups/$GroupId"
        $resp = Invoke-RestMethod -Uri $uri -Headers $Headers -Method GET
        return $resp.displayName
    } catch {
        return "Unknown Group ($GroupId)"
    }
}
