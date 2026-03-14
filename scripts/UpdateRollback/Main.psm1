function Rollback-UpdatePolicy {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [hashtable]$Configuration,

        [Parameter(Mandatory)]
        [string]$XLRIDReleaseTag,

        [Parameter(Mandatory)]
        [string]$XLRIDReleaseTagValue,

        [Parameter(Mandatory)]
        [string]$WorkFlowID,

        [Parameter(Mandatory)]
        [string]$WorkFlowTaskID
    )

    # Path to your JSON config file
    $configPath = "$PSScriptRoot\rollback-config.json"
    # Read and convert JSON file into PowerShell object
    $jsonConfig = Get-Content -Raw -Path $configPath | ConvertFrom-Json
    
    $jsonConfig.Git.GitPAT = $Configuration.'TU-GITPAT'
   
    # Write the updated config back to file (preserves formatting)
    $jsonConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath

    if (-not (Test-Path $configPath)) {
        throw "Missing config file at $configPath"
    }
    $Config = Get-Content -Raw -Path $configPath | ConvertFrom-Json

    # Load modules
    . "$PSScriptRoot\FetchReleasePolicy.ps1"
    

    # Convert input to array
    $policyIdArray = $PolicyIDs -split ',' | ForEach-Object { $_.Trim() }
    # Variables to handle success, errors
    $releasePath = @()
    $errorsList = @()
    $importedPolicies = @()
    $comparePolicies = @()
    $failedImportedPolicies = @()

    # Looping Policies
    foreach ($policyId in $policyIdArray) {
        
        # Check policy in database using Validate-Policy.ps1 module
        $releaseRecord = Get-GitHubReleaseJson -PolicyId $policyId -Config $Config -WorkFlowTaskID $WorkFlowTaskID -WorkFlowID $WorkFlowID -Destination $Destination
        Write-Output $releaseRecord
        

    }

    if ($releasePath.Count -gt 0) {
        Write-Host "`nRelease not found for IDs:" -ForegroundColor Yellow
        $releasePath | ForEach-Object { Write-Host "- $_" }
    }
    

}
