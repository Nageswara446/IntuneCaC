# Restore-Policy.psm1

# Determine the root path (one level up from RestoreModule folder)
$moduleRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$commonPath = Join-Path $moduleRoot "..\Modules\Common" | Resolve-Path

# Import the required scripts
$commonScripts = @(
    "Get-DatabaseConnection.ps1",
    "Auth.ps1"
)

foreach ($script in $commonScripts) {
    $fullPath = Join-Path $commonPath $script
    if (Test-Path $fullPath) {
        . $fullPath
        Write-Output "Imported $script"
    } else {
        Write-Error "Required script $script not found at $fullPath"
    }
}

# Import Restore Module Scripts
$requiredScripts = @(
    "Get-PolicyByID.ps1",
    "Import-PolicyToIntune.ps1",
    "Update-PolicyByID.ps1",
    "Get-PolicyFromGitHubRelease.ps1"
)

foreach ($script in $requiredScripts) {
    $fullPath = Join-Path $PSScriptRoot $script
    if (Test-Path $fullPath) {
        . $fullPath
        Write-Output "Imported $script"
    } else {
        Write-Error "Required $script not found at $fullPath"
    }
}

# Restore function
function Restore-Policy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Environment,  # ADT or Prod

        [Parameter(Mandatory = $true)]
        [string]$GitVersionTag,

        [Parameter(Mandatory = $true)]
        [string]$XLRTaskID,

        [Parameter(Mandatory = $true)]
        [string]$PolicyIDs  # Comma-separated string
    )

    try {
        Write-Output "Starting Restore-Policy process..."
        Write-Output "Environment: $Environment"
        Write-Output "Git Version Tag: $GitVersionTag"
        Write-Output "XLR ID: $XLRTaskID"
        Write-Output "Policy IDs: $PolicyIDs"

        # Convert comma-separated string into array
        $PolicyIDsArray = $PolicyIDs -split "," | ForEach-Object { $_.Trim() }

        # Step 1: Read credentials/config
        $configPath = "config.json"
        if (-not (Test-Path $configPath)) { throw "Config file not found at $configPath" }
        $config = Get-Content -Path $configPath | ConvertFrom-Json

        # Step 2: Authenticate
        $authToken = Get-AccessToken -Environment $Environment -Config $config
        if (-not $authToken) { throw "Authentication failed." }

        # Step 3: Connect to DB
        $connection = Get-DatabaseConnection -Config $config
        if (-not $connection) { throw "DB Connection failed." }

        # Step 4: Collect policy details
        $allPolicyDetails = @()

        foreach ($PolicyGuid in $PolicyIDsArray) {
            Write-Output "Restoring Policy ID: $PolicyGuid"

            $query = "SELECT * FROM policies WHERE PolicyGuid = @PolicyGuid AND Version = @GitVersionTag AND XLRTaskID = @XLRTaskID"
            $command = $connection.CreateCommand()
            $command.CommandText = $query

            # Add parameters
            foreach ($p in @(
                @{ Name='@PolicyGuid'; Value=$PolicyGuid },
                @{ Name='@GitVersionTag'; Value=$GitVersionTag },
                @{ Name='@XLRTaskID'; Value=$XLRTaskID }
            )) {
                $param = $command.CreateParameter()
                $param.ParameterName = $p.Name
                $param.Value = $p.Value
                $command.Parameters.Add($param) | Out-Null
            }

            # Execute query
            $reader = $command.ExecuteReader()
            if ($reader.HasRows) {
                $reader.Read()
                $PolicyDetails = [PSCustomObject]@{
                    PolicyID = $reader["PolicyID"]
                    PolicyGuid    = $reader["PolicyGuid"]
                    PolicyName    = $reader["PolicyName"]
                    PolicyType    = $reader["PolicyType"]
                    PolicySubType = $reader["PolicySubType"]
                    Environment   = $reader["Environment"]
                    PolicyBackupPath = $null 
                    IsBackupExist = $false
                }
                $reader.Close()
                # Check if a backup exists in policybackup table
                $backupQuery = "SELECT * FROM policybackups WHERE PolicyID = @PolicyID"
                $backupCommand = $connection.CreateCommand()
                $backupCommand.CommandText = $backupQuery
                # Add parameter safely
                $param = $backupCommand.CreateParameter()
                $param.ParameterName = "@PolicyID"
                $param.Value = $PolicyDetails.PolicyID  # Correct syntax, no @ before $
                $backupCommand.Parameters.Add($param) | Out-Null

                # Execute the query
                $backupReader = $backupCommand.ExecuteReader()
                if ($backupReader.HasRows) {
                    $backupReader.Read()
                    # Write-Output $backupReader["BackupFilePath"]
                    $PolicyDetails.PolicyBackupPath = $backupReader["BackupFilePath"]
                    $PolicyDetails.IsBackupExist = $true
                }
                $backupReader.Close()

                $allPolicyDetails += $PolicyDetails
            } else {
                Write-Warning "PolicyID $PolicyID not found in DB."
            }
        }

        # Step 5: Close DB connection
        $connection.Close()
        Write-Output "DB connection closed."

        $AccessToken = Get-AccessToken -Environment $Environment -Config $config
        foreach($PolicyData in $allPolicyDetails) {
            $PolicyDetail = Get-PolicyByID -Environment $Environment -Config $config -PolicyID $PolicyData.PolicyGuid -PolicyType $PolicyData.PolicyType -AccessToken $AccessToken
            Write-Output "$($PolicyData.PolicyGuid)-$GitVersionTag"
            
            $policyContent = Get-PolicyFromGitHubRelease -Owner $config.Git.repoOwner -Repo $config.Git.repoName -Tag "$($PolicyData.PolicyGuid)-$GitVersionTag" -Token $config.Git.GitPAT -DownloadPath $config.Git.clonePath -Environment $Environment -PolicyID $PolicyData.PolicyGuid

            if ($null -eq $policyContent) {
                Write-Warning "Policy content for $($PolicyData.PolicyGuid) not found!"
                continue
            } else {
                Write-Output "Policy content successfully fetched for $($PolicyData.PolicyGuid)"
                $policyJson = $policyContent | ConvertFrom-Json
                Write-Output ($policyJson | ConvertTo-Json -Depth 10)
            }
            
            if ($null -ne $PolicyDetail) {
                Write-Output "Policy found. Updating PolicyID: " $PolicyData.PolicyGuid
                $UpdateResponse = Update-PolicyByID -Environment $Environment -Config $config -PolicyID $PolicyData.PolicyGuid -PolicyType $PolicyData.PolicyType -AccessToken $AccessToken -PolicyBody $PolicyDetail
                Write-Output $UpdateResponse
            } else {
                Write-Output "Policy not found. Creating new policy: " $PolicyData.PolicyGuid
                try {
                    $response = Import-PolicyToIntune -PolicyJson $policyContent -PolicyType $PolicyData.PolicyType -AccessToken $AccessToken -Config $config -Environment $Environment 
                    Write-Output "New Policy ID: " $response.Response.id
                } catch {
                    Write-Error "Failed to import policy: $_"
                }
            }
            # Write-Output ($PolicyDetail | ConvertTo-Json -Depth 10)
        }
        return $allPolicyDetails
    }
    catch {
        Write-Error "Error during restore: $_"
    }
}


# Export the function
Export-ModuleMember -Function Restore-Policy

#Import-Module .\Restore-Policy.psm1 -Force
#Restore-Policy -Environment "ADT" -GitVersionTag "v1.0.0" -XLRTaskID "001" -PolicyID "f18f56e7-6d1c-48c7-8afc-bd57e401a1c6"
