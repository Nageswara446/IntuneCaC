# Function: Get-AccessToken
# Description: Retrieves an access token from Microsoft Graph using client credentials from the configuration.
# Parameters:
#   - Config (PSCustomObject, Mandatory): Configuration object containing TenantId, ClientId, ClientSecret, and TokenEndpoint.
 
# Function: Get-AccessToken
# Description: Retrieves an access token from Microsoft Graph using client credentials from the configuration.

function Get-AccessToken {
    param (
        [Parameter(Mandatory=$true)][PSCustomObject]$Config,
        [Parameter(Mandatory)][string]$Source
    )

    try {
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
            default {
                return $null
            }
        }

        if (-not $ClientId -or -not $ClientSecret -or -not $TenantId) {
            return $null
        }

        $body = @{
            grant_type    = "client_credentials"
            scope         = "https://graph.microsoft.com/.default"
            client_id     = $ClientId
            client_secret = $ClientSecret
        }
        $uri = [string]::Format($Config.GraphApi.TokenEndpoint, $TenantId)
        $response = Invoke-RestMethod -Method Post -Uri $uri -Body $body
        return $response.access_token
    }
    catch {
        return $null
    }
}