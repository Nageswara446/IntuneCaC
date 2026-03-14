function Export-IntunePolicyByIdOrName {
    param (
        [string]$AccessToken,
        [string[]]$SearchValues,
        [hashtable]$Endpoints,
        [string]$TempExportPath,
        [Parameter(Mandatory=$true)][PSCustomObject]$Config
    )

    if (-not $AccessToken -or -not $Endpoints -or -not $TempExportPath -or -not $Config) {
        return $null
    }

    if (-not (Test-Path $TempExportPath)) {
        New-Item -Path $TempExportPath -ItemType Directory -ErrorAction Stop | Out-Null
    }

    $headers = @{ Authorization = "Bearer $AccessToken" }
    $PlatformFilter = $Config.PlatformFilter
    if (-not $PlatformFilter) {
        return $null
    }
    $PlatformFilter = $PlatformFilter.ToLower()

    $allValidatedPolicies = @()

    foreach ($SearchValue in $SearchValues) {
        if ($SearchValue -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
            continue
        }

        $found = $false

        foreach ($endpointName in @("SettingsCatalog","Compliance","Configuration")) {
            if (-not $Endpoints.ContainsKey($endpointName)) { continue }
            $endpoint = $Endpoints[$endpointName]

            $uri = switch ($endpointName) {
                "SettingsCatalog" { "$($endpoint.Url)/$SearchValue/?`$expand=settings" }
                "Compliance"      { "$($endpoint.Url)/$SearchValue" }
                "Configuration"   { "$($endpoint.Url)/$SearchValue" }
            }
            try {
                $policy = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -ErrorAction Stop

                if (-not $policy.id) {
                    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [WARN] Endpoint [$endpointName] returned no ID for $SearchValue" -ForegroundColor Yellow
                    continue
                }

                # --------- PLATFORM VALIDATION ---------
                $odataTypeStr = if ($policy.'@odata.type') { ($policy.'@odata.type' | ForEach-Object { $_.ToLower() }) -join "" } else { "" }
                $platformsStr = if ($policy.platforms) { ($policy.platforms -join ',' | ForEach-Object { $_.ToLower() }) } else { "" }
                $isPlatformMatch = $false

                if ($endpointName -eq "Compliance" -and $odataTypeStr.Contains($PlatformFilter)) {
                    $isPlatformMatch = $true
                } elseif (($endpointName -eq "SettingsCatalog") -or ($endpoint.PolicyCategory -eq "Configuration")) {
                    if ($odataTypeStr.Contains($PlatformFilter) -or $platformsStr.Contains($PlatformFilter)) {
                        $isPlatformMatch = $true
                    }
                }

                if (-not $isPlatformMatch) {
                    continue
                }

                # --------- EXPORT JSON ---------
                $policyName = if ($policy.displayName) { $policy.displayName } elseif ($policy.name) { $policy.name } else { "UnnamedPolicy" }
                $outputPath = Join-Path $TempExportPath "$($policy.id).json"
                # $outputPath = "C:\Users\HCL0733\OneDrive - Allianz\Desktop\WPS_INTUNE_CaC\PolicyU.json"
                $policy | ConvertTo-Json -Depth 99 | Out-File -FilePath $outputPath -Encoding utf8

                $allValidatedPolicies += [PSCustomObject]@{
                    DisplayName       = $policyName
                    PolicyType        = $endpoint.PolicyType
                    PolicyTypeFull    = $endpoint.PolicyTypeFull
                    PolicyId          = $policy.id
                    PolicyCategory    = $endpoint.PolicyCategory
                    TemplateReference = $policy.templateReference
                }

                $found = $true
                break  
            }
            catch {
                $statusCode = $null
                if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                    $statusCode = $_.Exception.Response.StatusCode.Value__
                }

                if ($statusCode -in 400, 404) {
                    continue
                } else {
                    continue
                }
            }
        }
    }

    if ($allValidatedPolicies.Count -eq 0) {
        return $null
    }

    return $policy
}
