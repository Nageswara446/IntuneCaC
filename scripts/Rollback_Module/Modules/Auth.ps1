function Get-AccessToken {
    param (
        [Parameter(Mandatory)][string]$Environment,
        [Parameter(Mandatory)][PSCustomObject]$Config
    )
 
    switch ($Environment) {
        "ADT" {
            $clientId = $Config.Source.ADT.clientId
            $clientSecret = $Config.Source.ADT.clientSecret
            $tenantId = $Config.Source.ADT.tenantId
        }
        "Prod" {
            $clientId = $Config.Source.Prod.clientId
            $clientSecret = $Config.Source.Prod.clientSecret
            $tenantId = $Config.Source.Prod.tenantId
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
