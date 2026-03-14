function Format-RollbackMessage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$binding
    )

    # Extract only lines with policy entries
    $policyLines = ($binding -split ';') | Where-Object {
        $_ -match 'https://github\.developer\.allianz\.io'
    }
    #format msg added
    $parsedPolicies = @()
    foreach ($line in $policyLines) {
        if ($line -match '([0-9a-fA-F-]{36})\s*-\s*(.*?)\s*-\s*(.*?)\s*-\s*(Applications/.*?)\s*-\s*(https://\S+)') {
            $parsedPolicies += [PSCustomObject]@{
                GUID  = $matches[1]
                Name  = $matches[2]
                Type  = $matches[3]
                Path  = $matches[4]
                URL   = $matches[5]
            }
        }
    }

    # Format the extracted policies for email
    $policyDetails = ""
    $i = 1
    foreach ($p in $parsedPolicies) {
        $policyDetails += @"
$i. $($p.GUID) - $($p.Name) - $($p.Type)
   Path: $($p.Path)
   URL: $($p.URL)

"@
        $i++
    }

    # Create formatted message
    $formattedMessage = @"
Hello,

This is to inform you that a rollback request has been triggered for the following policies:

Policy Details:
$policyDetails
Kindly approve the process on XLR to proceed further.

Thank you for your prompt attention.

Best regards,
Release Administrator
"@

    return @{ 'formattedMessage' = $formattedMessage }
}

Export-ModuleMember -Function Format-RollbackMessage
