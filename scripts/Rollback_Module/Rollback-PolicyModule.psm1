# Import all helper function scripts (assumed to be in the same folder)
$functionFiles = @(
    "Get-DatabaseConnection.ps1",
    "GetPolicyDetails.ps1"
    # Add other helper scripts if needed
)

foreach ($file in $functionFiles) {
    $filePath = Join-Path $PSScriptRoot $file
    if (Test-Path $filePath) {
        . $filePath
    } else {
        
    }
}

# Wrapper function to call Get-PolicyFromTable and return the result
function Invoke-GetPolicyDetails {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$PolicyId,
        [Parameter(Mandatory)][PSCustomObject]$Config
    )

    # Call the imported function
    return GetPolicyDetails -PolicyId $PolicyId -Config $Config
}

# Export the main function(s) you want accessible from the module
Export-ModuleMember -Function Invoke-GetPolicyDetails
