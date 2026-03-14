function Get-AccessToken {
    param (
        [Parameter(Mandatory)][string]$Environment,
        [Parameter(Mandatory)][PSCustomObject]$Config
    )
 
    switch ($Environment) {
        "ADT" {
            $clientId = $Config.ADT.clientId
            $clientSecret = $Config.ADT.clientSecret
            $tenantId = $Config.ADT.tenantId
        }
        "Prod" {
            $clientId = $Config.Prod.clientId
            $clientSecret = $Config.Prod.clientSecret
            $tenantId = $Config.Prod.tenantId
        }
    }
 
    $body = @{
        client_id     = $clientId
        scope         = "https://graph.microsoft.com/.default"
        client_secret = $clientSecret
        grant_type    = "client_credentials"
    }
 
    $response = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" -Body $body
    return $response.access_token
}
