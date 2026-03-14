<#
.SYNOPSIS
    Export Policy Module - Integrates rollback module functionality.

.DESCRIPTION
    This module provides comprehensive policy export functionality by combining
    configuration import, authentication, and policy export into a single interface.

.FUNCTIONALITY
    - Imports configuration from rollback-policy-config.json
    - Authenticates with Microsoft Graph API
    - Exports individual Intune policies
    - Returns structured policy data

.NOTES
    Author: Workplace Services Team
    Version: 1.0.0

.REQUIRED MODULES
    MySql.Data (for database connections)
    Microsoft.Graph (implicit via REST API)
#>

# Import configuration file first
$configPath = Join-Path $PSScriptRoot "rollback-policy-config.json"
if (Test-Path $configPath) {
    $RollbackConfig = Get-Content -Raw -Path $configPath | ConvertFrom-Json
    # Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Successfully loaded rollback-policy-config.json"
} else {
    throw [System.IO.FileNotFoundException]::new("Configuration file not found: $configPath")
}

# Import required helper functions from Rollback_Module
$runbookScripts = @(
    "/Get-AccessToken.ps1",
    "/Export-IntunePolicyByIdOrName.ps1"
)

foreach ($script in $runbookScripts) {
    $scriptPath = Join-Path $PSScriptRoot $script
    if (Test-Path $scriptPath) {
        . $scriptPath
        # Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Imported: $(Split-Path $script -Leaf)"
    } else {
        throw [System.IO.FileNotFoundException]::new("Required script not found: $scriptPath")
    }
}

<#
.SYNOPSIS
    Exports Intune policy data with integrated authentication and configuration.

.DESCRIPTION
    This function combines configuration loading, Microsoft Graph authentication,
    and policy export operations into a single call. It returns the raw policy
    data from Microsoft's Graph API.

.PARAMETER PolicyId
    The GUID of the Intune policy to export.

.PARAMETER Source
    The environment to query: "ADT" or "Prod".

.OUTPUTS
    [PSCustomObject[]] Raw policy data from Microsoft Graph API.

.EXAMPLE
    $policyData = Export-IntunePolicy -PolicyId "12345678-1234-1234-1234-123456789ABC" -Source "ADT"

    Returns policy data object with all Microsoft Graph properties.

.EXAMPLE
    $policies = "12345678-1234-1234-1234-123456789ABC", "98765432-4321-4321-4321-987654321ABC" |
        ForEach-Object {
            Export-IntunePolicy -PolicyId $_ -Source "ADT"
        }

    Export multiple policies using pipeline.
#>
function Export-IntunePolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true,
                   HelpMessage = "Intune Policy GUID to export")]
        [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
        [string]$PolicyId,

        [Parameter(Mandatory = $true,
                   HelpMessage = "Target environment: ADT or Prod")]
        [ValidateSet("ADT", "Prod")]
        [string]$Source
    )

    try {
        # Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Starting policy export for: $PolicyId from $Source"

        # Step 1: Get Access Token using Rollback_Module authentication function
        # Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Authenticating with Microsoft Graph..."
        $AccessToken = Get-AccessToken -Config $RollbackConfig -Source $Source

        if (-not $AccessToken) {
            throw [System.Security.Authentication.SecurityException]::new("Failed to obtain access token")
        }

        # Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Authentication successful"

        # # Step 2: Export policy using Rollback_Module export function
        # Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Exporting policy data..."

        $endpointsHashtable = @{}
        foreach ($key in $RollbackConfig.GraphApi.Endpoints.PSObject.Properties.Name) {
            $endpointsHashtable[$key] = $RollbackConfig.GraphApi.Endpoints.$key
        }
        $TempExportPath = "C:\Users\HCL0733\OneDrive - Allianz\Desktop\WPS_INTUNE_CaC\scripts\Rollback_Module"
        $PolicyData = Export-IntunePolicyByIdOrName -AccessToken $AccessToken `
                                                  -SearchValue $PolicyId `
                                                  -Endpoints $endpointsHashtable `
                                                  -TempExportPath $TempExportPath `
                                                  -Config $RollbackConfig
        return $PolicyData

    } catch {
        # Write-Error "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Export policy failed: $($_.Exception.Message)"
        throw $_
    }
}

<#
.SYNOPSIS
    Exports policy data with formatted summary output.

.DESCRIPTION
    Extended version that includes summary formatting of the exported policy data.

.PARAMETER PolicyId
    The GUID of the Intune policy to export.

.PARAMETER Source
    The environment to query: "ADT" or "Prod".

.OUTPUTS
    [hashtable] Policy summary with raw data + formatted information.

.EXAMPLE
    $result = Export-PolicyWithDetails -PolicyId "12345678-1234-1234-1234-123456789ABC" -Source "ADT"

    Returns:
    @{
        RawData = $microsoftGraphPolicyObject
        Summary = @{
            PolicyGuid = "12345678-1234-1234-1234-123456789ABC"
            DisplayName = "Windows Defender Settings"
            PolicyType = "deviceConfiguration"
            Environment = "ADT"
        }
    }
#>
function Export-PolicyWithDetails {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
        [string]$PolicyId,

        [Parameter(Mandatory = $true)]
        [ValidateSet("ADT", "Prod")]
        [string]$Source
    )

    $policyData = Export-IntunePolicy -PolicyId $PolicyId -Source $Source

    if ($policyData -and $policyData.Count -gt 0) {
        $policy = $policyData[0]

        $summary = @{
            PolicyGuid  = $policy.id
            DisplayName = $policy.displayName
            Description = $policy.description
            PolicyType  = $policy.'@odata.type'
            CreatedDate = $policy.createdDateTime
            ModifiedDate = $policy.modifiedDateTime
            Owner      = $policy.owner
            SourceEnvironment = $Source
            ExportTimestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }

        return @{
            RawData = $policyData
            Summary = $summary
        }
    }

    return $null
}

# Export the main functions
Export-ModuleMember -Function @(
    'Export-IntunePolicy',
    'Export-PolicyWithDetails'
)

# Export the loaded configuration for external access
New-Variable -Name 'RollbackPolicyConfig' -Value $RollbackConfig -Scope Script -Force

# Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Export-Policy module loaded successfully"