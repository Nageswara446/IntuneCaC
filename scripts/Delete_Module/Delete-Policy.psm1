function Delete-Policy {
    [CmdletBinding()]
    param (
        
        [Parameter(Mandatory)]
        [ValidateSet("ADT", "Prod", "Dev")]
        [string]$Destination,

        [Parameter(Mandatory)]
        [string]$PolicyIDs,

        [Parameter(Mandatory)]
        [ValidateSet("Delete Policy")]
        [string]$Action,

        [Parameter(Mandatory)]
        [string]$WorkFlowID,

        [Parameter(Mandatory)]
        [string]$WorkFlowTaskID,

        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )

    # $configPath = "$PSScriptRoot\delete-policy-config.json"
 
    # if (-not (Test-Path $configPath)) {
    #     throw "Missing config file at $configPath"
    # }
    # $Config = Get-Content -Raw -Path $configPath | ConvertFrom-Json

    # Load modules
    . "$PSScriptRoot\..\Modules\Common\Auth.ps1"
    . "$PSScriptRoot\Modules\Validate-Policy.ps1"
    . "$PSScriptRoot\Modules\Delete-Policy.ps1"
    . "$PSScriptRoot\Modules\Search-IntunePolicyByIdOrName.ps1"

    
    # Convert input to array
    $policyIdArray = $PolicyIDs -split ',' | ForEach-Object { $_.Trim() }

    # Variables to handle success, errors
    $missingPolicies = @()
    $errorsList = @()
    $deletedPolicies = @()

    # Looping Policies
    foreach ($policyId in $policyIdArray) {
        Write-Host "Deleting Policy ID: $policyId" -ForegroundColor Cyan
        # Check policy in database using Validate-Policy.ps1 module
        $token = Get-AccessToken -Environment $Destination -Config $Config
        #Write-Host "token: $token" -ForegroundColor Cyan
       $endpointsHashtable = @{}
        foreach ($key in $Config.GraphApi.Endpoints.PSObject.Properties.Name) {
            $endpointsHashtable[$key] = $Config.GraphApi.Endpoints.$key
        }
        $policies = Search-IntunePolicyByIdOrName -AccessToken $token -SearchValue $policyId -Endpoints $endpointsHashtable
        if (-not $policies.Success) {
            $missingPolicies += "Policy ID does not exist: $($policyId)"
            continue
        } else {
            $policyType = $policies.Response.PolicyType
            $policyName = $policies.Response.DisplayName
            $DeleteURL = $policies.Response.DeleteURL
            Write-Host "DeleteURL: $DeleteURL" -ForegroundColor Cyan
            try {
                $response = Delete-PolicyFromIntune -Action $Action -PolicyType $policyType -Token $token -Config $Config -PolicyId $policyId -WorkFlowID $WorkFlowID -Destination $Destination -WorkFlowTaskID $WorkFlowTaskID -Endpoints $DeleteURL -PolicyName $policyName
                
                if ($response.Success ) {
                    $deletedPolicies += "Policy deleted successfully with ID: $($policyId) having name `"$($policyName)`""
                } else {
                    $errorsList += "Deletion failed for Policy ID $($policyId) : $($response.ErrorMessage)"
                }
            }
            catch {
                $errorsList += "Failed to delete Policy ID $($policyId): $($_.Exception.Message)"
                continue
            }
        }


    }

    if ($missingPolicies.Count -gt 0) {
        Write-Host "`nMissing Policy IDs:" -ForegroundColor Yellow
        $missingPolicies | ForEach-Object { Write-Host "- $_" }
    }
    if ($errorsList.Count -gt 0) {
        Write-Host "`nSummary of Errors:"
        $errorsList | ForEach-Object { Write-Warning $_ }
    }
    if ($deletedPolicies.Count -gt 0) {
        Write-Host "`nDeleted Policies:" -ForegroundColor Green
        $deletedPolicies | ForEach-Object { Write-Host $_ }
    }

}
