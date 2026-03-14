function Format-RollbackMessage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$binding
    )

    # Create formatted message
    $formattedMessage = @"
Hello,

This is to inform you that rollback request has been triggered for the following policy entries:

Policy Details:
$binding

Please proceed to disable these configurations in ADT to prevent any further changes.

Thank you for your prompt attention.

Best regards,  
Release Administrator
"@

    return @{ 'formattedMessage' = $formattedMessage }
}

Export-ModuleMember -Function Format-RollbackMessage
