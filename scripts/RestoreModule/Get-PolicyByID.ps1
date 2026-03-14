function Get-PolicyByID {
    <#
    .SYNOPSIS
        Validate if a policy exists in Intune by PolicyID.

    .DESCRIPTION
        This function checks if a Compliance or Configuration policy exists in Microsoft Intune 
        using Microsoft Graph API. If found, returns the policy JSON; otherwise returns null.

    .PARAMETER Environment
        The environment name: ADT or Prod.

    .PARAMETER Config
        A PSCustomObject containing environment-specific configuration (like API URLs if needed).

    .PARAMETER PolicyID
        The ID of the policy to validate.

    .PARAMETER PolicyType
        The type of policy (Compliance | Configuration).

    .PARAMETER AccessToken
        The Microsoft Graph API access token.

    .EXAMPLE
        Get-PolicyByID -Environment "ADT" -Config $myConfig -PolicyID "xxxx-xxxx" -PolicyType "Compliance" -AccessToken $token
    #>

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
        [string]$AccessToken
    )

    function Get-GraphUrl {
        param (
            [string]$PolicyType,
            [string]$PolicyID
        )

        switch ($PolicyType) {
            "Compliance Policy"     { return "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies/$PolicyID" }
            "Configuration Policy"  { return "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$PolicyID" }
            default { throw "Unsupported PolicyType: $PolicyType" }
        }
    }

    try {
        Write-Verbose "Environment: $Environment"
        Write-Verbose "PolicyType: $PolicyType"
        Write-Verbose "PolicyID: $PolicyID"

        $url = Get-GraphUrl -PolicyType $PolicyType -PolicyID $PolicyID

        $headers = @{
            "Authorization" = "Bearer $AccessToken"
            "Content-Type"  = "application/json"
        }

        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method GET -ErrorAction SilentlyContinue

        if ($null -ne $response) {
            # return ($response | ConvertTo-Json -Depth 10)
            return $response
        }
        else {
            Write-Warning "Policy not found for PolicyID: $PolicyID"
            return $null
        }
    }
    catch {
        Write-Warning "Error while retrieving policy: $($_.Exception.Message)"
        return $null
    }
}
