# Function: Invoke-WithRetry
# Description: Executes a script block with retry logic for handling transient errors.
# Parameters:
#   - Action (ScriptBlock, Mandatory): The script block to execute.
#   - ActionName (string, Mandatory): Name of the action for logging purposes.
#   - MaxRetries (int, Optional, Default=3): Maximum number of retry attempts.
#   - BaseDelaySeconds (int, Optional, Default=2): Base delay in seconds for exponential backoff.
 
# Function: Invoke-WithRetry
# Description: Executes a script block with retry logic for handling transient errors.

function Invoke-WithRetry {
    param (
        [Parameter(Mandatory=$true)][ScriptBlock]$Action,
        [Parameter(Mandatory=$true)][string]$ActionName,
        [Parameter(Mandatory=$false)][int]$MaxRetries = 3,
        [Parameter(Mandatory=$false)][int]$BaseDelaySeconds = 2
    )

    $attempt = 1
    while ($attempt -le $MaxRetries) {
        try {
            $result = & $Action
            return $result
        }
        catch {
            if ($attempt -eq $MaxRetries) {
                return $null
            }
            $delay = [math]::Pow($BaseDelaySeconds, $attempt)
            Start-Sleep -Seconds $delay
            $attempt++
        }
    }
}