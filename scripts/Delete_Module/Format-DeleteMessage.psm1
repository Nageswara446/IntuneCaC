function Format-RollbackMessage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$binding
    )

    # Remove unwanted lines like MySQL connection or success messages
    $cleanInput = $binding -split "`n" | Where-Object {
        $_ -notmatch 'Connected to MySQL|Success Response|ErrorMessage|Record Inserted|^-+$|^$'
    }

    # Initialize array for parsed policies
    $parsedPolicies = @()
    $currentPolicy = @{}

    foreach ($line in $cleanInput) {
        $trimmed = $line.Trim()

        # Detect policy ID line
        if ($trimmed -match '^-+\s*([0-9a-fA-F-]{36})') {
            # Save previous policy if exists
            if ($currentPolicy.Count -gt 0) {
                $parsedPolicies += [PSCustomObject]$currentPolicy
                $currentPolicy = @{}
            }
            $currentPolicy['PolicyID'] = $matches[1]
        }
        elseif ($trimmed -match '^PolicyType:\s*(.+)$') {
            $currentPolicy['PolicyType'] = $matches[1]
        }
        elseif ($trimmed -match '^PolicyName:\s*(.+)$') {
            $currentPolicy['PolicyName'] = $matches[1]
        }
    }

    # Add the last policy if present
    if ($currentPolicy.Count -gt 0) {
        $parsedPolicies += [PSCustomObject]$currentPolicy
    }

    # Build formatted policy list
    if ($parsedPolicies.Count -eq 0) {
        $policyDetails = "No valid policies found in the input."
    } else {
        $policyDetails = ($parsedPolicies | ForEach-Object {
            "- Policy ID: $($_.PolicyID)`n  Policy Type: $($_.PolicyType)`n  Policy Name: $($_.PolicyName)"
        }) -join "`n`n"
    }

    # Create the final formatted message
    $formattedMessage = @"
Hello,

This is to inform you that a delete request has been triggered for the following policies:

Policy Details:

$policyDetails

Kindly approve the process on XLR to proceed further.

Thank you for your prompt attention.

Best regards,
Release Administrator
"@

    # Return formatted message
    return @{ 'formattedMessage' = $formattedMessage }
}

Export-ModuleMember -Function Format-RollbackMessage
