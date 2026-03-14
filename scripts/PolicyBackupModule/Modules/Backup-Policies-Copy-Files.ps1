function Backup-Policies-Copy-Files {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [string]$BackupPath,
        [Parameter(Mandatory = $true)]
        [string[]]$PolicyIDs,
        [Parameter(Mandatory = $true)]
        [string]$AssignmentFile,
        [Parameter(Mandatory = $true)]
        [string]$Environment,
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config,
        [Parameter(Mandatory = $true)]
        [string]$XLRTaskID,
        [Parameter(Mandatory = $true)]
        [string]$WorkflowID,
        [Parameter(Mandatory)]
        [ValidateSet("Compliance", "Configuration", "All")]  
        [string]$PolicyType,
        [Parameter(Mandatory = $true)]
        [string]$GitPolicyBackUpPath,
        [switch]$CleanEmptyFolders
    )

    # Validate source
    if (-Not (Test-Path -Path $SourcePath)) {
        Write-Output "Source path does not exist: $SourcePath" -ForegroundColor Red
        return
    }

    # Ensure base backup and Git backup roots exist
    foreach ($path in @($BackupPath, $GitPolicyBackUpPath)) {
        if (-Not (Test-Path $path)) {
            try {
                New-Item -ItemType Directory -Path $path -Force | Out-Null
            } catch {
                Write-Output "Failed to create root path: $path. Error: $_" -ForegroundColor Red
                return
            }
        }
    }

    $StringWorkflowID = $WorkflowID
    if ($StringWorkflowID -match "/(Release[^/]+)") {
        $StringWorkflowID = $matches[1]
        Write-Output $StringWorkflowID
    }

    $DateTime          = Get-Date -Format "dd-MMM-yyyy_HH-mm-ss"
    $BaseUniquePath    = Join-Path -Path $BackupPath -ChildPath "${DateTime}_$StringWorkflowID"
    $BaseGitBackUpPath = Join-Path -Path $GitPolicyBackUpPath -ChildPath "${DateTime}_$StringWorkflowID"

    # Initialize log
    $LogContent         = @()
    $SuccessfullPolicies= @()
    $PoliciesNotFound   = @()
    $CurrentDateTimeUTC = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss")
    $LogContent += "---------------- Start $CurrentDateTimeUTC ----------------"

    # Iterate over each Policy ID
    foreach ($PolicyGuid in $PolicyIDs) {
        $PolicyData = Confirm-Policy -PolicyGuid $PolicyGuid -XLRTaskID $XLRTaskID -WorkflowID $WorkflowID -Config $Config
        if (-Not $PolicyData) {
            $LogContent += "[$(Get-Date -Format 'u')] Policy not available: $PolicyGuid"
            $PoliciesNotFound += $PolicyGuid
            continue
        }

        # Determine folder type
        if ($PolicyType -eq "All") {
            if ($PolicyData.PolicyType -eq "Compliance Policy") {
                $PolicyTypeLower = "compliance"
            }
            elseif ($PolicyData.PolicyType -eq "Configuration Policy") {
                $PolicyTypeLower = "configuration"
            }
            else {
                $PolicyTypeLower = "other"
            }
        } else {
            $PolicyTypeLower = $PolicyType.ToLower()
        }

        # Build paths
        $UniquePath    = Join-Path -Path $BaseUniquePath    -ChildPath $PolicyTypeLower
        $GitBackUpPath = Join-Path -Path $BaseGitBackUpPath -ChildPath $PolicyTypeLower
        $SourcePath = (Resolve-Path $SourcePath).Path
        $file = Get-ChildItem -Path $SourcePath -Recurse -File |
        Where-Object {
            $_.BaseName -eq $PolicyGuid -and
            $_.DirectoryName -notmatch "\\backup(\\|$)"
        } |
        Select-Object -First 1
        if (-Not $file) {
            $LogContent += "[$(Get-Date -Format 'u')] No file found for PolicyGuid=$PolicyGuid"
            continue
        }

        # Ensure policy-type folder exists (only when file found)
        foreach ($path in @($UniquePath, $GitBackUpPath)) {
            if (-Not (Test-Path $path)) {
                New-Item -ItemType Directory -Path $path -Force | Out-Null
            }
        }

        # Copy policy JSON
        $DestinationFile = Join-Path -Path $UniquePath -ChildPath $file.Name
        $AssignmentPathForDB = "NoAssignments"   # Default null for DB insertion

        if (-Not (Test-Path -Path $DestinationFile)) {
            Copy-Item -Path $file.FullName -Destination $UniquePath -Force
            $LogContent += "[$(Get-Date -Format 'u')] Copied policy: $($file.FullName) to $UniquePath"
            $SuccessfullPolicies += $PolicyData.PolicyGuid
        } else {
            $LogContent += "[$(Get-Date -Format 'u')] Policy file already exists in backup: $DestinationFile"
        }

        # --- Backup Assignments ---
        $AssignmentsFolder = Join-Path -Path $SourcePath -ChildPath "assignments"
        if (Test-Path $AssignmentsFolder) {
            $AssignmentFiles = Get-ChildItem -Path $AssignmentsFolder -Filter "${PolicyGuid}_assignment*.json" -File -ErrorAction SilentlyContinue
            if ($AssignmentFiles) {
                # Create assignments folders only if files exist
                $AssignmentBackupFolder    = Join-Path -Path $UniquePath    -ChildPath "assignments"
                $GitAssignmentBackupFolder = Join-Path -Path $GitBackUpPath -ChildPath "assignments"
                foreach ($path in @($AssignmentBackupFolder, $GitAssignmentBackupFolder)) {
                    if (-Not (Test-Path $path)) {
                        New-Item -ItemType Directory -Path $path -Force | Out-Null
                    }
                }

                foreach ($Assignment in $AssignmentFiles) {
                    $AssignmentDest    = Join-Path -Path $AssignmentBackupFolder -ChildPath $Assignment.Name
                    $GitAssignmentDest = Join-Path -Path $GitAssignmentBackupFolder -ChildPath $Assignment.Name

                    if (-Not (Test-Path -Path $AssignmentDest)) {
                        Copy-Item -Path $Assignment.FullName -Destination $AssignmentDest -Force
                        $LogContent += "[$(Get-Date -Format 'u')] Copied assignment: $($Assignment.FullName) to $AssignmentDest"
                    } else {
                        $LogContent += "[$(Get-Date -Format 'u')] Assignment already exists: $AssignmentDest"
                    }

                    if (-Not (Test-Path -Path $GitAssignmentDest)) {
                        Copy-Item -Path $Assignment.FullName -Destination $GitAssignmentDest -Force
                        $LogContent += "[$(Get-Date -Format 'u')] Copied assignment to Git backup: $GitAssignmentDest"
                    } else {
                        $LogContent += "[$(Get-Date -Format 'u')] Assignment already exists in Git backup: $GitAssignmentDest"
                    }
                }

                # Set assignment path for DB insert
                $AssignmentPathForDB = Join-Path -Path $GitBackUpPath -ChildPath "assignments"
            } else {
                $LogContent += "[$(Get-Date -Format 'u')] No assignments found for PolicyGuid=$PolicyGuid"
            }
        } else {
            $LogContent += "[$(Get-Date -Format 'u')] Assignments folder not found: $AssignmentsFolder"
        }
        
        # Insert DB record (with Assignment path if available, else null)
        Add-DatabaseRecord -PolicyID $PolicyData.PolicyID `
                           -BackupPath $GitBackUpPath `
                           -AssignmentFile $AssignmentPathForDB `
                           -Environment $Environment `
                           -PolicyVersion $PolicyData.Version `
                           -Config $Config
    }

    # End log
    $EndDateTimeUTC = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss")
    $LogContent += "---------------- End $EndDateTimeUTC ----------------"

    # Save log
    if (-Not (Test-Path $BaseUniquePath)) {
        New-Item -ItemType Directory -Path $BaseUniquePath -Force | Out-Null
    }
    $LogFile = Join-Path $BaseUniquePath "backup_${DateTime}_$StringWorkflowID.log"
    $LogContent | Out-File -FilePath $LogFile -Append -Encoding UTF8

    # Clean up empty folders if switch is used
    if ($CleanEmptyFolders) {
        Get-ChildItem -Path $BaseUniquePath -Recurse -Directory |
            Sort-Object FullName -Descending | ForEach-Object {
                if (-Not (Get-ChildItem -Path $_.FullName -Recurse -Force | Where-Object { -not $_.PSIsContainer })) {
                    Remove-Item -Path $_.FullName -Force -Recurse
                    $LogContent += "[$(Get-Date -Format 'u')] Removed empty folder: $($_.FullName)"
                }
            }
    }

    return [PSCustomObject]@{
        SuccessfullPolicies = $SuccessfullPolicies
        PoliciesNotFound    = $PoliciesNotFound
        LogFile             = $LogFile
    }
}
