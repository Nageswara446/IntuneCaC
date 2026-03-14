# ------------------- Function: Export-IntunePolicyByIdOrName -------------------
# Parameters:
#   - string $AccessToken: Access token for Microsoft Graph API
#   - string $SearchValue: Policy ID (GUID) to fetch
#   - hashtable $Endpoints: Hashtable of endpoint configurations

 
function Search-IntunePolicyByIdOrName {
    param (
        [string]$AccessToken,
        [string]$SearchValue,
        [hashtable]$Endpoints
    )

    $result = [PSCustomObject]@{
        Success      = $false
        Response     = @()
        ErrorMessage = ""
    }

    # Validate GUID
    if (-not ($SearchValue -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')) {
        $result.ErrorMessage = "Invalid GUID: '$SearchValue'"
        return $result
    }

    $headers = @{ Authorization = "Bearer $AccessToken" }
    $matched = $false
    $policiesToValidate = @()

    foreach ($endpointName in $Endpoints.Keys) {
        $endpoint = $Endpoints[$endpointName]
        $uri = if ($endpointName -eq "SettingsCatalog") {
            "$($endpoint.Url)/$SearchValue/?`$expand=settings"
        } else {
            "$($endpoint.Url)/$SearchValue"
        }
        try {
            $policy = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get

            # Check if policy found and has required properties
            if (-not $policy.id -or (-not $policy.displayName -and -not $policy.name)) {
                # Policy not found in this endpoint, just continue silently
                continue
            }

            $policyName = if ($policy.displayName) { $policy.displayName } else { $policy.name }
            $matched = $true

            $policiesToValidate += [PSCustomObject]@{
                DisplayName    = $policyName
                PolicyType     = $endpoint.PolicyType
                PolicyTypeFull = $endpoint.PolicyTypeFull
                PolicyId       = $policy.id
                PolicyCategory = $endpoint.PolicyCategory
                DeleteURL = $uri
            }
            #$policiesToValidate | Out-String | Write-Host

            break # Exit after first match
        }
        catch {
            # Optional: Capture error message but don't print
            # $result.ErrorMessage += "Error querying $endpointName: $($_.Exception.Message); "
            # Or ignore silently
        }
    }

    if ($matched) {
        $result.Success = $true
        $result.Response = $policiesToValidate
    }
    else {
        $result.Success = $false
        $result.ErrorMessage = "No matching policy found for ID '$SearchValue'"
    }

    return $result
}
