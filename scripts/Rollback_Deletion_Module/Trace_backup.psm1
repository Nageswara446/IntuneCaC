# Import helper function scripts
. "$PSScriptRoot\Modules\Get-DatabaseConnection.ps1"
. "$PSScriptRoot\Modules\GetPolicybackup.ps1"

# Wrapper function to call GetPolicyDetails and return the result
function Invoke-GetPolicyDetails {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$PolicyId,
        [Parameter(Mandatory)][PSCustomObject]$Config
    )

    # Call the imported function
    return GetBackupDetails -PolicyId $PolicyId -Config $Config
}

# Export the main function(s) you want accessible from the module
Export-ModuleMember -Function Invoke-GetPolicyDetails
