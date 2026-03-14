# Function: Get-AccessToken
# Description: Retrieves an access token from Microsoft Graph using client credentials from the configuration.
# Parameters:
#   - Config (PSCustomObject, Mandatory): Configuration object containing TenantId, ClientId, ClientSecret, and TokenEndpoint.
 
function Get-AccessToken {
    param (
        [Parameter(Mandatory=$true)][PSCustomObject]$Config,
        [Parameter(Mandatory)][string]$Source
    )

    switch ($Source) {
        "ADT" {
            $ClientId = $Config.Source.ADT.clientId
            $ClientSecret = $Config.Source.ADT.clientSecret
            $TenantId = $Config.Source.ADT.tenantId
        }
        "Prod" {
            $ClientId = $Config.Source.Prod.clientId
            $ClientSecret = $Config.Source.Prod.clientSecret
            $TenantId = $Config.Source.Prod.tenantId
        }
    }
    $body = @{
        grant_type    = "client_credentials"
        scope         = "https://graph.microsoft.com/.default"
        client_id     = $ClientId
        client_secret = $ClientSecret
    }
    $uri = [string]::Format($Config.GraphApi.TokenEndpoint, $TenantId)
    try {
        $response = Invoke-RestMethod -Method Post -Uri $uri -Body $body
        # Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Successfully retrieved access token"
        return $response.access_token
    }
    catch {
        Write-Error "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Failed to retrieve access token: $($_.Exception.Message)"
        throw $_
    }
}