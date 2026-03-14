function Remove-PolicyAssignments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PolicyId,

        [Parameter(Mandatory = $true)]
        [string]$PolicyType,  # e.g., deviceConfigurations, deviceCompliancePolicies, configurationPolicies

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,  # Contains Authorization Bearer token

        [Parameter(Mandatory = $false)]
        [string[]]$AssignmentName,  # For SpecificAssignment

        [Parameter(Mandatory = $false)]
        [string[]]$FilterName,      # For SpecificFilter

        [Parameter(Mandatory = $true)]
        [ValidateSet("AllAssignments","SpecificAssignment","AllFilters","SpecificFilter")]
        [string]$ActionType
    )

    # Write-Verbose "Processing $PolicyType policy with ID: $PolicyId"
    $uri = "https://graph.microsoft.com/beta/deviceManagement/$PolicyType/$PolicyId/assignments"

    try {
        # --- 1. Fetch assignments
        # Write-Verbose "Fetching assignments from $uri"
        $AssignmentsResponse = Invoke-RestMethod -Uri $uri -Headers $Headers -Method GET -TimeoutSec 120
        if (-not $AssignmentsResponse.value -or $AssignmentsResponse.value.Count -eq 0) {
            Write-Output "No assignments found for Policy ID: $PolicyId"
            return
        }

        # --- 2. Fetch assignment filters (safe fallback)
        $filtersMap = @{}
        try {
            $filtersUri = "https://graph.microsoft.com/beta/deviceManagement/assignmentFilters"
            # Write-Verbose "Fetching filters from $filtersUri"
            $filtersResponseRaw = Invoke-RestMethod -Uri $filtersUri -Headers $Headers -Method GET
            foreach ($f in $filtersResponseRaw.value) {
                if ($f.displayName -and $f.id) {
                    $filtersMap[$f.displayName.ToLower()] = $f.id
                }
            }
        } catch {
            Write-Warning "Could not retrieve assignment filters: $($_.Exception.Message)"
        }

        # --- 3. Build assignment objects
        $assignments = foreach ($a in $AssignmentsResponse.value) {
            $rawTarget = $a.target
            $groupName = "Unknown"

            if ($rawTarget -and $rawTarget.groupId) {
                try {
                    $grpUri = "https://graph.microsoft.com/v1.0/groups/$($rawTarget.groupId)"
                    $grp = Invoke-RestMethod -Uri $grpUri -Headers $Headers -Method GET
                    $groupName = if ($grp.displayName) { $grp.displayName } else { "Unknown ($($rawTarget.groupId))" }
                } catch {
                    $groupName = "Unknown ($($rawTarget.groupId))"
                }
            }

            $filterName = ""
            if ($rawTarget.deviceAndAppManagementAssignmentFilterId -and
                $rawTarget.deviceAndAppManagementAssignmentFilterId -ne "00000000-0000-0000-0000-000000000000") {
                $filter = $filtersMap.GetEnumerator() | Where-Object { $_.Value -eq $rawTarget.deviceAndAppManagementAssignmentFilterId }
                $filterName = if ($filter) { $filter.Key } else { "" }
            }

            [PSCustomObject]@{
                AssignmentId = $a.id
                GroupId      = $rawTarget.groupId
                GroupName    = $groupName
                FilterId     = $rawTarget.deviceAndAppManagementAssignmentFilterId
                FilterName   = $filterName
                RawTarget    = $rawTarget
            }
        }

        # --- 4. Normalize names
        $AssignmentName = @($AssignmentName | Where-Object { $_ }) | ForEach-Object { $_.Trim() }
        $FilterName     = @($FilterName | Where-Object { $_ }) | ForEach-Object { $_.Trim() }

        # --- 5. Determine assignments to process
        switch ($ActionType) {
            "AllAssignments" {
                $assignmentsToProcess = $assignments
            }
            "SpecificAssignment" {
                if (-not $AssignmentName) { throw "Provide -AssignmentName for SpecificAssignment" }
                $assignmentsToProcess = $assignments | Where-Object { 
                    $AssignmentName -contains $_.GroupName
                }
            }
            "AllFilters" {
                $assignmentsToProcess = $assignments | Where-Object { 
                    $_.FilterId -and $_.FilterId -ne "00000000-0000-0000-0000-000000000000"
                }
            }
            "SpecificFilter" {
                if (-not $FilterName) { throw "Provide valid -FilterName for SpecificFilter" }
                $filterNamesClean = @()
                foreach ($f in $FilterName) {
                    $filterNamesClean += ($f -split '\s*,\s*' | ForEach-Object { $_.Trim().ToLower() })
                }
                $assignmentsToProcess = $assignments | Where-Object {
                    $_.FilterName -and ($filterNamesClean -contains $_.FilterName.Trim().ToLower())
                }
            }
        }

        if (-not $assignmentsToProcess -or $assignmentsToProcess.Count -eq 0) {
            Write-Output "No assignments match the criteria for action $ActionType."
            return
        }

        # Write-Output "`nAssignments to process:"
        # $assignmentsToProcess | Format-Table GroupName, FilterName, AssignmentId -AutoSize

        # --- 6. Handle by Policy Type
        if ($PolicyType -eq "deviceCompliancePolicies") {
            # Compliance policies use POST /assign
            try {
                $remainingAssignments = @()

                foreach ($a in $assignments) {
                    if ($assignmentsToProcess.AssignmentId -contains $a.AssignmentId) {
                        switch ($ActionType) {
                            "SpecificAssignment" { 
                                Write-Output "Removing assignment for '$($a.GroupName)'" 
                            }
                            "AllAssignments"     { Write-Output "Removing all assignments" }
                            "SpecificFilter" {
                                Write-Output "Removing filter for '$($a.GroupName)'"
                                $remainingAssignments += @{ target = @{ "@odata.type" = "#microsoft.graph.groupAssignmentTarget"; groupId = $a.GroupId } }
                            }
                            "AllFilters" {
                                Write-Output "Removing all filters from assignments"
                                $remainingAssignments += @{ target = @{ "@odata.type" = "#microsoft.graph.groupAssignmentTarget"; groupId = $a.GroupId } }
                            }
                        }
                    } else {
                        $remainingAssignments += @{ target = $a.RawTarget }
                    }
                }

                $body = @{ assignments = $remainingAssignments } | ConvertTo-Json -Depth 6
                $postUri = "https://graph.microsoft.com/beta/deviceManagement/$PolicyType/$PolicyId/assign"
                # Write-Verbose "POST $postUri with body: $body"
                Invoke-RestMethod -Uri $postUri -Headers $Headers -Method POST -Body $body -ContentType "application/json"
                Write-Output "Updated compliance policy assignments successfully."
            } catch {
                Write-Warning "Error updating compliance policy assignments: $($_.Exception.Message)"
            }
        }
        else {
            # --- Configuration and Settings policies
            try {
                # For Configuration policies, always use POST /assign with filtered assignments
                $remainingAssignments = @()

                foreach ($a in $assignments) {
                    if ($ActionType -in @("AllAssignments", "SpecificAssignment") -and $assignmentsToProcess.AssignmentId -contains $a.AssignmentId) {
                        # Skip assignments to remove
                        Write-Output "Removing assignment for '$($a.GroupName)'"
                        continue
                    }

                    if ($ActionType -in @("AllFilters", "SpecificFilter") -and $assignmentsToProcess.AssignmentId -contains $a.AssignmentId) {
                        # Remove filter but keep assignment
                        $odataType = switch ($PolicyType) {
                            "configurationPolicies" { "#microsoft.graph.groupAssignmentTarget" }
                            "deviceConfigurations" { "#microsoft.graph.deviceConfigurationGroupAssignmentTarget" }
                            default { "#microsoft.graph.groupAssignmentTarget" }
                        }

                        $remainingAssignments += @{
                            target = @{
                                "@odata.type" = $odataType
                                groupId       = $a.GroupId
                            }
                        }
                        Write-Output "Removed filter from assignment '$($a.GroupName)'"
                        continue
                    }

                    # Keep all other assignments unchanged
                    $remainingAssignments += @{ target = $a.RawTarget }
                }

                $body = @{ assignments = $remainingAssignments } | ConvertTo-Json -Depth 6
                $postUri = "https://graph.microsoft.com/beta/deviceManagement/$PolicyType/$PolicyId/assign"
                # Write-Verbose "POST $postUri with body: $body"
                Invoke-RestMethod -Uri $postUri -Headers $Headers -Method POST -Body $body -ContentType "application/json"
                Write-Output "Updated configuration policy assignments successfully."
            } catch {
                Write-Warning "Error updating configuration policy assignments: $($_.Exception.Message)"
            }
        }
    } catch {
        throw "Error processing assignments: $($_.Exception.Message)"
    }
}
