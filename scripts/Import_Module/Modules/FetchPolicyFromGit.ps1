function Fetch-PolicyFromGit {
    param (
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][PSCustomObject]$Config,
        [Parameter(Mandatory)][psobject]$PolicyType,
        [Parameter(Mandatory)][psobject]$PolicyId,
        [Parameter(Mandatory)][psobject]$ExportGitPath,
        [Parameter(Mandatory)][string]$ExistingPolicyinSource,
        [Parameter(Mandatory)][string]$gitpath,
        [Parameter(Mandatory)][PSCustomObject]$ScopeTags
    )

    $result = [PSCustomObject]@{
        Success      = $false
        Response     = $null
        ErrorMessage = ""
        releaseURL = ""
    }
    $releaseURL = $null
    
    try {
        # Validate required values
        if ([string]::IsNullOrWhiteSpace($gitpath)) {
            $result.ErrorMessage = "No changes in the policy. Git Release is not created."
            return $result
        }

        if (-not $Config -or -not $Config.Git) {
            $result.ErrorMessage = "Git configuration is missing."
            return $result
        }

        if (-not $Config.Git.GitPAT -or -not $Config.Git.repoOwner -or -not $Config.Git.repoName -or -not $Config.Git.rawUrl) {
            $result.ErrorMessage = "Incomplete Git configuration. One or more required fields (GitPAT, repoOwner, repoName, rawUrl) are missing."
            return $result
        }
        

        $ReleaseVersion = $null
        $PolicyGuid = $null

        if ($gitpath -match 'releases/download/(Release-[^/]+)') {
            $ReleaseVersion = $matches[1]
        } else {
            $result.ErrorMessage = "Release version not found in gitpath."
            return $result
        }

        if ($gitpath -match '/([0-9a-fA-F\-]{36})\.json$') {
            $PolicyGuid = $matches[1]
        } else {
            $result.ErrorMessage = "Policy GUID not found in gitpath."
            return $result
        }

        if ($PolicyGuid -ne $PolicyId) {
            $result.ErrorMessage = "`n Not Found in release - $($PolicyId)"
            return $result
        }

        # Prepare GitHub API URL
        $Token        = $Config.Git.GitPAT
        $RepoOwner    = $Config.Git.repoOwner
        $RepoName     = $Config.Git.repoName
        $ApiBaseUrl   = $Config.Git.rawUrl
        $TagName      = $ReleaseVersion
        $AssetName    = "$PolicyGuid.json"
        #$releaseUrl   = "$ApiBaseUrl/api/v3/repos/$RepoOwner/$RepoName/releases/tags/$TagName"
        $GitReleaseURL = $Config.Git.ReleaseUrl
        $releaseURL = $GitReleaseURL.Replace("{RepoOwner}", $RepoOwner).Replace("{RepoName}", $RepoName).Replace("{TagName}", $TagName)

        $headers = @{
            Authorization = "token $Token"
            Accept        = "application/json"
            "User-Agent"  = "MyPowerShellScript/1.0"
        }

        # Fetch release
        try {
            $release = Invoke-RestMethod -Uri $releaseUrl -Headers $headers -Method Get 
        } catch {
            $result.ErrorMessage = "Failed to fetch release info from GitHub. $($_.Exception.Message)"
            return $result
        }

        if (-not $release.assets) {
            $result.ErrorMessage = "No assets found in release: $TagName"
            return $result
        }

        $asset = $release.assets | Where-Object { $_.name -eq $AssetName }

        if (-not $asset) {
            $result.ErrorMessage = "`n Asset ID not found for $($PolicyId)"
            return $result
        }

        $assetId = $asset.id
        #$assetDownloadUrl = "$ApiBaseUrl/api/v3/repos/$RepoOwner/$RepoName/releases/assets/$assetId"
        $GitAssetReleaseURL = $Config.Git.ReleaseAssetUrl
        $assetDownloadUrl = $GitAssetReleaseURL.Replace("{RepoOwner}", $RepoOwner).Replace("{RepoName}", $RepoName).Replace("{assetId}", $assetId)

        $downloadHeaders = @{
            Authorization = "token $Token"
            Accept        = "application/octet-stream"
            "User-Agent"  = "MyPowerShellScript/1.0"
        }

        # Download and parse JSON
        # Define a temporary file path
        $DownloadPath = "C:\URM\release-export"
        $outputFile = Join-Path -Path $DownloadPath -ChildPath $AssetName

        # Download the asset to temp file
        try {
            Invoke-WebRequest -Uri $assetDownloadUrl -Headers $downloadHeaders -Method Get -OutFile $outputFile
        } catch {
            $result.ErrorMessage = "Failed to download policy JSON from GitHub. $($_.Exception.Message)"
            return $result
        }

        # Read and parse the file
        try {
            $rawJsonString = Get-Content -Path $outputFile -Raw
            $policyJson = $rawJsonString | ConvertFrom-Json
        } catch {
            $result.ErrorMessage = "Downloaded JSON is invalid or not in correct format. $($_.Exception.Message)"
            return $result
        }
        

        if ($ExistingPolicyinSource -eq "False") { 
            $policyJson.PSObject.Properties.Remove('id') | Out-Null
            $policyJson.PSObject.Properties.Remove('createdDateTime') | Out-Null
            $policyJson.PSObject.Properties.Remove('lastModifiedDateTime') | Out-Null
            if ($policyJson.PSObject.Properties.Name -contains 'supportsScopeTags') {
                $policyJson.PSObject.Properties.Remove('supportsScopeTags') | Out-Null
            }
            if ($policyJson.PSObject.Properties.Name -contains 'deviceManagementApplicabilityRuleOsEdition') {
                $policyJson.PSObject.Properties.Remove('deviceManagementApplicabilityRuleOsEdition') | Out-Null
            }
            

        }
        

        if (-not $policyJson.PSObject.Properties['displayName'] -and -not $policyJson.PSObject.Properties['name']) {
            $result.ErrorMessage = "Invalid JSON structure for Policy ID $($PolicyGuid). Missing required 'displayName' or 'name'."
            return $result
        }
        #get scope tags data
        # Fetch tag IDs
        $odataContext = $policyJson.PSObject.Properties['@odata.context'].Value
            if ($odataContext -match 'microsoft\.com/([^/]+)/\$metadata') {
                $version = $matches[1]
            } else {
                $version = 'beta'
            }
        $roleScopeTagsArray = @()
           
        if ($ScopeTags.Success -and -not [string]::IsNullOrWhiteSpace($ScopeTags.ScopeTags)) {
            if ($ScopeTags.ScopeTags.Contains(",")) {
                $roleScopeTagsArray = $ScopeTags.ScopeTags -split "," | ForEach-Object {
                    $_.Trim() -replace "`r`n", ""
                }
            } else {
                $roleScopeTagsArray = @($ScopeTags.ScopeTags.Trim() -replace "`r`n", "")
            }
            $policyJson.roleScopeTagIds = $roleScopeTagsArray
        } else {
            if ($policyJson.PSObject.Properties.Name -contains 'roleScopeTagIds') {
                $policyJson.PSObject.Properties.Remove('roleScopeTagIds') | Out-Null
            }
        }
        
        #$policyJson | ConvertTo-Json -Depth 10
        $result = [PSCustomObject]@{
            Success  = $true
            Response = $policyJson
            ErrorMessage = ""
            releaseURL = $releaseURL
            roleScopeTags = $roleScopeTagsArray
        }
        return $result
        
    }
    catch {
        $result.ErrorMessage = "Policy fetch failed: $($_.Exception.Message)"
        if ($_.Exception.Response -ne $null) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $result.ErrorMessage += "`n" + $reader.ReadToEnd()
        }
        return $result
    }
}


function Get-IntuneScopeTagId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory = $false)][hashtable]$Configuration,
        [Parameter(Mandatory)][string]$ScopeTags
    )
. "C:\URM\WPS_INTUNE_CaC\scripts\Modules\Common\Auth.ps1" -Force -Verbose
    # Path to your JSON config file
    $configPath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath "..\..\Modules\Common\config.json")


    # Read and convert JSON file into PowerShell object
    $jsonConfig = Get-Content -Raw -Path $configPath | ConvertFrom-Json

    # Replace the tenantId under Destination -> ADT with the one from $config
    $jsonConfig.Destination.ADT.tenantId = $Configuration.'ADT-TenantID'
    $jsonConfig.Destination.ADT.clientSecret = $ConConfigurationfig.'ADT-ClientSecret'
    $jsonConfig.Destination.ADT.clientId = $Configuration.'ADT-ClientID'
    $jsonConfig.Destination.Prod.tenantId = $Configuration.'Prod-TenantID'
    $jsonConfig.Destination.Prod.clientSecret = $Configuration.'Prod-ClientSecret'
    $jsonConfig.Destination.Prod.clientId = $Configuration.'Prod-ClientID'
    $jsonConfig.Source.ADT.tenantId = $Configuration.'ADT-TenantID'
    $jsonConfig.Source.ADT.clientSecret = $Configuration.'ADT-ClientSecret'
    $jsonConfig.Source.ADT.clientId = $Configuration.'ADT-ClientID'
    $jsonConfig.Source.Prod.tenantId = $Configuration.'Prod-TenantID'
    $jsonConfig.Source.Prod.clientSecret = $Configuration.'Prod-ClientSecret'
    $jsonConfig.Source.Prod.clientId = $Configuration.'Prod-ClientID'
   
    # Write the updated config back to file (preserves formatting)
    $jsonConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath

    if (-not (Test-Path $configPath)) {
        return [PSCustomObject]@{
            Success      = $false
            ErrorMessage = "Missing config file at loc $configPath"
            ScopeTags    = @()
        }
    }
    $Config = Get-Content -Raw -Path $configPath | ConvertFrom-Json

    # Convert string array to PowerShell array
    $ScopeTagArray = $ScopeTags -replace "'", '"' | ConvertFrom-Json

    $token = Get-AccessToken -Environment $Destination -Config $Config

    $headers = @{
            "Authorization" = "Bearer $token"
            "Content-Type"  = "application/json"
        }

    # Fetch all role scope tags
    $url = "https://graph.microsoft.com/beta/deviceManagement/roleScopeTags"
    $response = Invoke-RestMethod -Uri $url -Headers $headers -Method GET
    if (-not $response.value) {
        return [PSCustomObject]@{
            Success      = $false
            ErrorMessage = "No scope tags found in the response."
            ScopeTags    = @()
        }
    }
    $allTags = $response.value

    # Match provided names to IDs
    $results = @{}
    foreach ($tagName in $ScopeTagArray) {
        $match = $allTags | Where-Object { $_.displayName -eq $tagName }
        if ($match) {
            $results[$tagName] = $match.id
        }
    }

    $resultsArray = $results.Values | ForEach-Object { $_.ToString() }
    # Create the array format manually
    $arrayFormatted = ($resultsArray -join ",") 

    # Format the result as an object with Success flag and ScopeTags array
    return [PSCustomObject]@{
        Success   = $true
        ScopeTags = $arrayFormatted
        ErrorMessage = ""
    }

}
