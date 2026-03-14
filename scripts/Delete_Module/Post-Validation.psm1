# ------------------- Module: Search-IntunePolicyByIdOrName -------------------
# Description:
#   Provides functionality to search Intune policies by ID or name
#   using Microsoft Graph API and formats the output.

# Import required modules and functions
. "$PSScriptRoot\..\Modules\Common\Auth.ps1"
. "$PSScriptRoot\Modules\Search-IntunePolicyByIdOrName.ps1"

function Search-IntunePolicyByIdOrName {
    param (
        [Parameter(Mandatory)]
        [ValidateSet("ADT", "Prod", "Dev")]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$SearchValue,  # multiple comma-separated IDs

        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )

    $result = [PSCustomObject]@{
        Success       = $false
        FoundPolicies = @()
        NotFound      = @()
    }

    # Split multiple search values by comma and trim whitespace
    $searchValues = $SearchValue -split ',' | ForEach-Object { $_.Trim() }

    # ------------------- GET TOKEN -------------------
    $token = Get-AccessToken -Environment $Source -Config $Config
    if (-not $token) {
        $result.NotFound = $searchValues
    } else {
        $headers = @{ Authorization = "Bearer $token" }

        # Set up endpoints hashtable from config
        $endpointsHashtable = @{}
        foreach ($key in $Config.GraphApi.Endpoints.PSObject.Properties.Name) {
            $endpointsHashtable[$key] = $Config.GraphApi.Endpoints.$key
        }

        foreach ($id in $searchValues) {
            # Validate GUID format for each ID
            if (-not ($id -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')) {
                $result.NotFound += [PSCustomObject]@{
                    SearchValue = $id
                    Reason      = "Invalid GUID format"
                }
                continue
            }

            $matched = $false
            foreach ($endpointName in $endpointsHashtable.Keys) {
                $endpoint = $endpointsHashtable[$endpointName]
                $uri = if ($endpointName -eq "SettingsCatalog") {
                    "$($endpoint.Url)/$id/?`$expand=settings"
                } else {
                    "$($endpoint.Url)/$id"
                }

                try {
                    $policy = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get

                    if (-not $policy.id -or (-not $policy.displayName -and -not $policy.name)) {
                        continue
                    }

                    $policyName = if ($policy.displayName) { $policy.displayName } else { $policy.name }
                    $matched = $true

                    $result.FoundPolicies += [PSCustomObject]@{
                        SearchValue    = $id
                        DisplayName    = $policyName
                        PolicyType     = $endpoint.PolicyType
                        PolicyTypeFull = $endpoint.PolicyTypeFull
                        PolicyId       = $policy.id
                        PolicyCategory = $endpoint.PolicyCategory
                        DeleteURL      = $uri
                    }

                    break # Exit endpoint loop on first match
                }
                catch {
                    # Ignore errors for this call
                }
            }

            if (-not $matched) {
                $result.NotFound += [PSCustomObject]@{
                    SearchValue = $id
                    Reason      = "No matching policy found"
                }
            }
        }

        $result.Success = $result.FoundPolicies.Count -gt 0
    }

    # ------------------- FORMAT OUTPUT -------------------
    if ($result.FoundPolicies.Count -gt 0) {
        Write-Host "Policy Found" -ForegroundColor Green
        foreach ($policy in $result.FoundPolicies) {
            Write-Host "- $($policy.PolicyId)"
        }
    }

    if ($result.NotFound.Count -gt 0) {
        Write-Host "`nPolicy Not Found" -ForegroundColor Red
        foreach ($nf in $result.NotFound) {
            Write-Host "- $($nf.SearchValue)"
        }
    }

    # 🔴 Remove the return to avoid printing object dump
    # return $result
}

# Export this function when module is imported
Export-ModuleMember -Function Search-IntunePolicyByIdOrName
