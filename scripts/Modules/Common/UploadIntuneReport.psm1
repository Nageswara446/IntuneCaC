<#
.SYNOPSIS
    Upload Intune HTML Report to SharePoint using Microsoft Graph API and send notification email.

.DESCRIPTION
    This module authenticates to Microsoft Graph, uploads the given HTML report to SharePoint, 
    and returns the uploaded file's SharePoint web URL.
#>
# Function: Get-AccessToken
function Get-AccessToken {
    param (
        [Parameter(Mandatory)][string]$Environment,
        [Parameter(Mandatory)][PSCustomObject]$Config
    )
 
    switch ($Environment) {
        "ADT" {
            $clientId = $Config.SharePoint.ADT.clientId
            $clientSecret = $Config.SharePoint.ADT.clientSecret
            $tenantId = $Config.SharePoint.ADT.tenantId
        }
        "Prod" {
            $clientId = $Config.SharePoint.Prod.clientId
            $clientSecret = $Config.SharePoint.Prod.clientSecret
            $tenantId = $Config.SharePoint.Prod.tenantId
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

# Function: Upload-FileToSharePoint
function Upload-FileToSharePoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Environment,

        [Parameter(Mandatory)]
        [PSCustomObject]$Config,

        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string]$AccessToken
    )

    if (-not (Test-Path $FilePath)) {
        throw "File not found: $FilePath"
    }

    $Headers = @{
        "Authorization" = "Bearer $AccessToken"
        "Content-Type"  = "application/octet-stream"
    }

    # SharePoint configuration
    switch ($Environment) {
        "ADT" {
            $SiteId = $Config.SharePoint.ADT.SiteId
        }
        "Prod" {
            $SiteId = $Config.SharePoint.Prod.SiteId
        }
    }
    $FolderPath = "URM"
    $FileName = [System.IO.Path]::GetFileName($FilePath)

    try {
        $UploadUrl = "https://graph.microsoft.com/v1.0/sites/${SiteId}/drive/root:/${FolderPath}/${FileName}:/content"
        Write-Host "Uploading '$FileName' to SharePoint folder '$FolderPath'..."

        $response = Invoke-RestMethod -Uri $UploadUrl -Headers $Headers -Method PUT -InFile $FilePath

        Write-Host "Upload successful: $($response.webUrl)"
        return $response.webUrl
    }
    catch {
        throw "File upload failed: $($_.Exception.Message)"
    }
}

# ==============================
# Function: Upload-IntuneReport
# ==============================
function Upload-IntuneReport {
    <#
    .SYNOPSIS
        Authenticates and uploads an Intune HTML report to SharePoint.
    .PARAMETER Environment
        Environment name (e.g., 'Prod' or 'ADT') used for authentication.
    .PARAMETER FilePath
        Full path of the HTML report to upload.
    .OUTPUTS
        String - SharePoint web URL of the uploaded file.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Prod", "ADT")]
        [string]$Environment,

        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    # Step 1: Load configuration
    $configPath = Join-Path $PSScriptRoot "config.json"
    if (-not (Test-Path $configPath)) {
        throw "Config file not found at $configPath"
    }

    $config = Get-Content -Raw -Path $configPath | ConvertFrom-Json
    Write-Verbose "Loaded configuration for environment: $Environment"

    # Step 2: Authenticate
    $AccessToken = Get-AccessToken -Environment $Environment -Config $config
    if (-not $AccessToken) {
        throw "Authentication failed for environment: $Environment"
    }

    Write-Verbose "Successfully acquired access token."

    # Step 3: Upload report
    Write-Host "Uploading Intune HTML report..."
    $UploadedLink = Upload-FileToSharePoint -FilePath $FilePath -AccessToken $AccessToken -Environment $Environment -Config $config

    Write-Host "Report uploaded successfully."
    return $UploadedLink
}

Export-ModuleMember -Function Upload-IntuneReport, Upload-FileToSharePoint, Get-AccessToken
