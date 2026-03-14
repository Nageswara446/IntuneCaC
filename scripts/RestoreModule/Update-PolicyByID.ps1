function Update-PolicyByID {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet("ADT", "Prod")]
        [string]$Environment,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config,

        [Parameter(Mandatory = $true)]
        [string]$PolicyID,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Compliance Policy", "Configuration Policy")]
        [string]$PolicyType,

        [Parameter(Mandatory = $true)]
        [string]$AccessToken,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$PolicyBody
    )

    function Get-GraphUrl {
        param (
            [string]$PolicyType,
            [string]$PolicyID
        )
        switch ($PolicyType) {
            "Compliance Policy"     { return "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies/$PolicyID" }
            "Configuration Policy"  { return "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$PolicyID" }
        }
    }

    $headers = @{
        "Authorization" = "Bearer $AccessToken"
        "Content-Type"  = "application/json"
    }

    try {
        $url = Get-GraphUrl -PolicyType $PolicyType -PolicyID $PolicyID
        $body = $PolicyBody | ConvertTo-Json -Depth 10 -Compress
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method PATCH -Body $body -ErrorAction Stop
        # Write-Host "API Response:" -ForegroundColor Green
        # $response | ConvertTo-Json -Depth 10 | Write-Output
        return $response
    }
    catch {
        Write-Warning "Error updating policy: $($_.Exception.Message)"
        return $null
    }
}
