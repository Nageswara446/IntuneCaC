# Determine the root path (one level up from RestoreModule folder)
$moduleRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$commonPath = Join-Path $moduleRoot "..\Modules\Common" | Resolve-Path

# Import the required scripts
$commonScripts = @(
    "Get-DatabaseConnection.ps1",
    "Auth.ps1",
    "Get-IntunePolicyDetails.ps1"
)

foreach ($script in $commonScripts) {
    $fullPath = Join-Path $commonPath $script
    if (Test-Path $fullPath) {
        . $fullPath
        Write-Output "Imported $script"
    }
    else {
        Write-Error "Required script $script not found at $fullPath"
    }
}

# Import Restore Module Scripts
$requiredScripts = @(
    "Policy-Assignment.ps1"
)

foreach ($script in $requiredScripts) {
    $fullPath = Join-Path $PSScriptRoot $script
    if (Test-Path $fullPath) {
        . $fullPath
        Write-Output "Imported $script"
    }
    else {
        Write-Error "Required $script not found at $fullPath"
    }
}

function Set-IntunePolicyAssignment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Environment,  # ADT or Prod

        [Parameter(Mandatory = $true)]
        [string[]]$PolicyIDs,

        [hashtable[]]$IncludeGroupNames,            # AAD Group display names for inclusion

        [string[]]$ExcludeGroupNames,            # AAD Group display names for exclusion

        [string[]]$ScopeTagNames,                # Scope tag display names

        [hashtable[]]$Filters,                  # Array of filters @{name="filterName"; mode="include/exclude"}
        [Parameter(Mandatory = $false)]
        [hashtable]$Configuration
    )

    try {
        # Step 1: Read credentials/config
        $configPath = "$PSScriptRoot\config.json"
        if (-not (Test-Path $configPath)) { throw "Config file not found at $configPath" }

        $jsonConfig = Get-Content -Raw -Path $configPath | ConvertFrom-Json
        # Write-Output "Loaded config.json successfully" $jsonConfig

        # Update with passed-in Configuration values
        $jsonConfig.Source.ADT.tenantId     = $Configuration.'ADT-TenantID'
        $jsonConfig.Source.ADT.clientSecret = $Configuration.'ADT-ClientSecret'
        $jsonConfig.Source.ADT.clientId     = $Configuration.'ADT-ClientID'

        $jsonConfig.Source.Prod.tenantId     = $Configuration.'Prod-TenantID'
        $jsonConfig.Source.Prod.clientSecret = $Configuration.'Prod-ClientSecret'
        $jsonConfig.Source.Prod.clientId     = $Configuration.'Prod-ClientID'

        $jsonConfig.Git.GitPAT = $Configuration.'TU-GITPAT'

        # Save back
        $jsonConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath
        # $jsonConfig
        # $config = $jsonConfig
        
        if (-not (Test-Path $configPath)) { throw "Config file not found at $configPath" }
        $config = Get-Content -Path $configPath | ConvertFrom-Json
        # Write-Output $config

        # Step 2: Authenticate
        $AccessToken = Get-AccessToken -Environment $Environment -Config $config
        if (-not $AccessToken) { throw "Authentication failed." }

        # Step 3: Connect to DB
        $connection = Get-DatabaseConnection -Config $config
        if (-not $connection) { throw "DB Connection failed." }

        $Headers = @{
            "Authorization" = "Bearer $AccessToken"
            "Content-Type"  = "application/json"
        }
        # Convert to array of quoted strings
        $ExcludeGroupNames = $ExcludeGroupNames -split '\s*,\s*'
        # Write-Output $ExcludeGroupNames
        $PolicyIDs = $PolicyIDs -split '\s*,\s*'
        # Write-Output $PolicyIDs
        foreach ($PolicyId in $PolicyIDs) {
            Write-Output "Starting Policy assignment process..."
            Write-Output "Environment: $Environment"
            Write-Output "Policy ID: $PolicyId"

            $PolicyDetail = Get-IntunePolicyDetails -Headers $Headers -PolicyId $PolicyId

            # Write-Output $PolicyDetail.GraphUrl

            $AssignmentOutput = Assign-IntunePolicy -Headers $Headers -PolicyId $PolicyId -IncludeGroupNames $IncludeGroupNames -ExcludeGroupNames $ExcludeGroupNames -ScopeTagNames $ScopeTagNames -uri $PolicyDetail.GraphUrl
            Write-Output $AssignmentOutput
        }
    } 
    catch {
        Write-Error "Error during assignment: $_"
    }
}

# Export the function
Export-ModuleMember -Function Set-IntunePolicyAssignment