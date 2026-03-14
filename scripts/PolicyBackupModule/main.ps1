param (
    [Parameter(Mandatory)]
    [ValidateSet("ADT", "Prod")]
    [string]$Source,
    [Parameter(Mandatory)]
    [ValidateSet("ADT", "Prod")]
    [string]$Destination,
    [Parameter(Mandatory)]
    [string]$PolicyIDs,
    [Parameter(Mandatory)]
    [ValidateSet("Compliance", "Configuration", "All")] # Add more types as needed
    [string]$PolicyType,
    [Parameter(Mandatory)]
    [ValidateSet("dev", "main")]
    [string]$BranchName,
    [Parameter(Mandatory = $true)]
    [string]$XLRTaskID,
    [Parameter(Mandatory = $true)]
    [string]$WorkflowID,
    [Parameter(Mandatory = $false)]
    [hashtable]$Configuration
)

# Source the module functions
try {
    . "$PSScriptRoot\Modules\Get-DatabaseConnection.ps1"
    . "$PSScriptRoot\Modules\Confirm-Policy.ps1"
    . "$PSScriptRoot\Modules\Backup-Policies-Copy-Files.ps1"
    . "$PSScriptRoot\Modules\Add-DatabaseRecord.ps1"
    . "$PSScriptRoot\Modules\Get-CloneGitRepo.ps1"
    . "$PSScriptRoot\Modules\Add-PushChangesToGit.ps1"
} catch {
    Write-Output "Error sourcing module functions: $_" -ForegroundColor Red
    exit 1
}

# Validate PolicyIDs
if (-not $PolicyIDs) {
    Write-Output "PolicyIDs parameter is empty or invalid." -ForegroundColor Red
    exit 1
}

# Read and parse the JSON file
try {
    $ConfigFilePath =  "$PSScriptRoot\config.json"

     $jsonConfig = Get-Content -Raw -Path $ConfigFilePath | ConvertFrom-Json
     $jsonConfig.Source.ADT.tenantId = $Configuration.'ADT-TenantID'
     $jsonConfig.Source.ADT.clientSecret = $Configuration.'ADT-ClientSecret'
     $jsonConfig.Source.ADT.clientId = $Configuration.'ADT-ClientID'
     $jsonConfig.Source.Prod.tenantId = $Configuration.'Prod-TenantID'
     $jsonConfig.Source.Prod.clientSecret = $Configuration.'Prod-ClientSecret'
     $jsonConfig.Source.Prod.clientId = $Configuration.'Prod-ClientID'
     $jsonConfig.Git.GitPAT = $Configuration.'TU-GITPAT'
     $jsonConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigFilePath
    
    if (-not (Test-Path $ConfigFilePath)) {
        throw "Missing config file at $ConfigFilePath"
    }
    $Config = Get-Content -Raw -Path $ConfigFilePath | ConvertFrom-Json
    
} catch {
    Write-Output "Error reading or parsing the JSON configuration file: $_" -ForegroundColor Red
    exit 1
}

# Access Git configuration
try {
    $GitRepoOwner = $Config.Git.repoOwner
    $GitRepoName = $Config.Git.repoName
    $GitRawUrl = $Config.Git.rawUrl
    $GitPAT = $Config.Git.GitPAT

    if (-not ($GitRepoOwner -and $GitRepoName -and $GitRawUrl -and $GitPAT)) {
        throw "Incomplete Git configuration."
    }
} catch {
    Write-Output "Error accessing Git configuration: $_" -ForegroundColor Red
    exit 1
}

# Convert Policy IDs to an array
try {
    $PolicyIDArray = $PolicyIDs -split ','
    if (-not $PolicyIDArray) {
        throw "Failed to convert Policy IDs to an array."
    }
} catch {
    Write-Output "Error converting Policy IDs to an array: $_" -ForegroundColor Red
    exit 1
}

# Define paths and log file
try {
    $ClonePath = $Config.Git.clonePath
    if (-not (Test-Path -Path $ClonePath)) {
        try {
            New-Item -ItemType Directory -Path $ClonePath -Force | Out-Null
            Write-Output "Clone path created: $ClonePath"
        }
        catch {
            throw "Failed to create clone path: $ClonePath. Error: $_"
        }
    }
    else {
        Write-Output "Clone path exists: $ClonePath"
    }

    # Convert PolicyType to lowercase
    # $policyTypeLower = $PolicyType.ToLower()

    # Dynamically set paths based on PolicyType
    if ($Source -eq "Prod") {
        $SourcePath = "$ClonePath\$($Config.Source.Prod.backupPath)"
    } else {
        $SourcePath = "$ClonePath\$($Config.Source.ADT.backupPath)"
    }

    if ($Destination -eq "Prod") {
        $GitPolicyBackUpPath = $Config.Destination.Prod.backupPath
        $DestinationPath = "$ClonePath\$($Config.Destination.Prod.backupPath)"
        # $LogFilePath = "$ClonePath\$($Config.Destination.Prod.backupPath)"
    } else {
        $GitPolicyBackUpPath = $Config.Destination.ADT.backupPath
        $DestinationPath = "$ClonePath\$($Config.Destination.ADT.backupPath)"
        # $LogFilePath = "$ClonePath\$($Config.Destination.ADT.backupPath)"
    }
} catch {
    Write-Output "Error defining paths and log file: $_" -ForegroundColor Red
    exit 1
}

# Clone the GitHub repository using PAT
try {
    # Construct the repository URL with PAT
    $RepoUrlWithPAT = $Config.RepoUrl
    
    # Debugging output to verify URL
    Write-Output "Repository URL: $RepoUrlWithPAT" -ForegroundColor Yellow

    # If ClonePath already exists, remove it recursively
    if (Test-Path -Path $ClonePath) {
        Write-Host "Clone path already exists. Removing: $ClonePath" -ForegroundColor Cyan
        Remove-Item -Path $ClonePath -Recurse -Force
    }

    # Recreate a fresh directory
    New-Item -Path $ClonePath -ItemType Directory -Force | Out-Null
    
    # Call the function to clone the repository
    # Get-CloneGitRepo -RepoUrl $RepoUrlWithPAT -ClonePath $ClonePath -BranchName $BranchName
    Get-CloneGitRepo -Config $Config

    # Verify cloning success
    if (-Not (Test-Path -Path $ClonePath)) {
        throw "Failed to clone the repository. Directory does not exist: $ClonePath"
    }
} catch {
    Write-Output "Error cloning GitHub repository: $_" -ForegroundColor Red
    exit 1
}

# Create backup folder and copy files based on PolicyType and Policy IDs
$BackupResult = Backup-Policies-Copy-Files -SourcePath $SourcePath -BackupPath $DestinationPath -PolicyIDs $PolicyIDArray -AssignmentFile $PolicyType -Environment $Source -Config $Config -XLRTaskID $XLRTaskID -WorkflowID $WorkflowID -PolicyType $PolicyType -GitPolicyBackUpPath $GitPolicyBackUpPath

# Commit and push changes using PAT
$GitResult = Add-PushChangesToGit -RepoPath $ClonePath -BranchName $BranchName -GitPAT $GitPAT -GitPolicyBackUpPath $GitPolicyBackUpPath

Write-Output "`n===== Backup Result ====="
Write-Output "Log File: $($BackupResult.LogFile)"

if ($BackupResult.SuccessfullPolicies -and $BackupResult.SuccessfullPolicies.Count -gt 0) {
    Write-Output "Backup taken for Policies PolicyGuid:"
    foreach ($PolicyGuid in $BackupResult.SuccessfullPolicies) {
        Write-Output " - $PolicyGuid"
    }
}

if ($backupResult.PoliciesNotFound -and $backupResult.PoliciesNotFound.Count -gt 0) {
    Write-Output "Policies Not Found:"
    foreach ($PolicyGuid in $backupResult.PoliciesNotFound) {
        Write-Output "  - $PolicyGuid"
    }
}

Write-Output "`n===== Git Push Result ====="

if ($gitResult.Success -and $gitResult.ChangesCommitted) {
    Write-Output "Changes committed and pushed successfully."
    Write-Output "Branch: $($gitResult.BranchName)"
    Write-Output "Repo:   $($gitResult.RepoPath)"
    Write-Output "Commit: $($gitResult.CommitMessage)"
} elseif ($gitResult.Success -and -not $gitResult.ChangesCommitted) {
    Write-Output "No changes to commit under $GitPolicyBackUpPath."
} else {
    Write-Output "Git push failed."
    Write-Output "Message: $($gitResult.Message)"
}

# Sample Command To Run the Module
#.\main.ps1 -Source "ADT" -Destination "ADT" -PolicyIDs "1189d8f7-6f9f-4810-8f7c-fcce154456ba,54efe779-f2a8-4dd5-8301-95bb002836bc,4904f2eb-1a1f-408a-b6e6-2ce1bf4d7e6a" -PolicyType "All" -XLRTaskID "972" -WorkflowID "455972" -BranchName "dev"
