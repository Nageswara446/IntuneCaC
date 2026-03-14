function Get-AllGraphItems {
    param (
        [string]$Uri,
        [hashtable]$Headers
    )

    $results = @()
    do {
        $response = Invoke-RestMethod -Uri $Uri -Headers $Headers -Method GET
        $results += $response.value
        $Uri = $response.'@odata.nextLink'
    } while ($Uri)

    return $results
}