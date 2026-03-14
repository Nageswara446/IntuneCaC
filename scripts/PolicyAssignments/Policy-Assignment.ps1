function Assign-IntunePolicy {

    param(
        [Parameter(Mandatory=$true)]
        $Headers,

        [string]$PolicyId,                       # Intune Policy ID
 
        [hashtable[]]$IncludeGroupNames,         # Array of includegroups with filter details @{FilterName="filterName"; FilterMode="include/exclude";GroupName="Name of the group"}

        [string[]]$ExcludeGroupNames,            # AAD Group display names for exclusion

        [string[]]$ScopeTagNames,                # Scope tag display names

        [string]$uri
    )

    # Function to resolve display names to IDs
    function Resolve-NamesToIds {
        param(
            [string[]]$Names,
            [string]$Type
        )

        $ids = @()
        foreach ($name in $Names) {
            try {
                $id=@()
                switch ($Type) {
                    "Group" {
                        $uri = "https://graph.microsoft.com/beta/groups?`$filter=displayname eq '$name'"
                        $response = Invoke-RestMethod -Headers $Headers -Method GET -Uri $uri -ErrorAction Stop
                        $id = ($response.value | Where-Object { $_.displayName -eq $name }).id
                    }
                    "Filter" {
                        $uri = "https://graph.microsoft.com/beta/deviceManagement/assignmentFilters"
                        $response = Invoke-RestMethod -Headers $Headers -Method GET -Uri $uri -ErrorAction Stop
                        $id = ($response.value | Where-Object { $_.displayName -eq $name }).id
                    }
                    "ScopeTag" {
                        $uri = "https://graph.microsoft.com/beta/deviceManagement/roleScopeTags"
                        $response = Invoke-RestMethod -Headers $Headers -Method GET -Uri $uri -ErrorAction Stop
                        $id = ($response.value | Where-Object { $_.displayName -eq $name }).id
                    }
                }

                if ($id) {
                    $ids += $id
                } else {
                    Write-Warning "The $Type with display name '$name' does not exist."
                }
            } catch {
                Write-Error "Failed to resolve $Type with display name '$name'."
                return $null
            }
        }
        return $ids
    }

    # Resolve Include Groups
    $includeGroups=@()
    foreach($includegroup in $IncludeGroupNames) {
        $IncludeGroupId = Resolve-NamesToIds -Names $includegroup["GroupName"] -Type "Group"
        if($includegroup["FilterName"] -ne $null) {
            $FilterID=Resolve-NamesToIds -Names $includegroup["FilterName"] -Type "Filter"
            
            if ($includegroup["FilterName"] -and $FilterID) {
                $includeGroups += [PSCustomObject]@{ 
                    GroupId     = $IncludeGroupId
                    GroupName   = $includegroup["GroupName"]
                    FilterID    = $FilterID
                    FilterName  = $includegroup["FilterName"]
                    FilterMode  = $includegroup["FilterMode"]
                }
            }
            elseif ($includegroup["FilterName"] -and -not $FilterID) {
                Write-Warning "Filter '$($includegroup["FilterName"])' not found — ignoring filter for group '$($includegroup["GroupName"])'."
                $includeGroups += [PSCustomObject]@{ 
                    GroupId   = $IncludeGroupId
                    GroupName = $includegroup["GroupName"]
                }
            }
        } else {
            $includeGroups+=[PSCustomObject]@{ 
                GroupId=$IncludeGroupId
                GroupName=$includegroup["GroupName"]
            }
        }
    }
    if (-not $IncludeGroups) { return }

    # Resolve Exclude Groups
    $ExcludeGroups = Resolve-NamesToIds -Names $ExcludeGroupNames -Type "Group"
    if (-not $ExcludeGroups) { return }

    # Resolve Scope Tags
    $ScopeTags=@()
    $ScopeTags += Resolve-NamesToIds -Names $ScopeTagNames -Type "ScopeTag"
    if ($ScopeTagNames -and (-not $ScopeTags)) { return }

    # Get current assignments to avoid duplicates
    $currentAssignmentsUri = "$uri/$PolicyId/Assignments"
    # Write-Output $currentAssignmentsUri
    $currentAssignments = Invoke-RestMethod -Headers $Headers -Method GET -Uri $currentAssignmentsUri

    $assignments = @()

    # Include Groups
    foreach ($group in $IncludeGroups) {
        if (-not $group.GroupId) {
            Write-Warning "Skipping group '$($group.GroupName)' because GroupId is null."
            continue
        }

        if ($group.FilterID -and ($group.FilterID -ne "")) {
            $assignments += @{
                target = @{
                    "@odata.type" = "#microsoft.graph.groupAssignmentTarget"
                    groupId = $group.GroupId
                    deviceAndAppManagementAssignmentFilterId = ($group.FilterID | Select-Object -First 1)
                    deviceAndAppManagementAssignmentFilterType = $group.FilterMode
                }
            }
        } else {
            Write-Warning "Skipping filter for group '$($group.GroupName)' because FilterID is null or missing."
            $assignments += @{
                target = @{
                    "@odata.type" = "#microsoft.graph.groupAssignmentTarget"
                    groupId = $group.GroupId
                }
            }
        }
    }

    # Exclude Groups
    foreach ($groupId in $ExcludeGroups) {
        if (-not $groupId) {
            Write-Warning "Skipping exclude group because GroupId is null."
            continue
        }

        $assignments += @{
            target = @{
                "@odata.type" = "#microsoft.graph.exclusionGroupAssignmentTarget"
                groupId = $groupId
            }
        }
    }

    # Merge new and existing assignments
    if ($currentAssignments.value) {
        $existingAssignments = @()
        foreach ($ca in $currentAssignments.value) {
            if ($ca.target -and $ca.target.groupId) {
                $existingAssignments += @{
                    target = $ca.target
                }
            }
        }

        # Ensure both are arrays before combining
        if ($existingAssignments -isnot [System.Collections.IEnumerable]) {
            $existingAssignments = @($existingAssignments)
        }
        if ($assignments -isnot [System.Collections.IEnumerable]) {
            $assignments = @($assignments)
        }

        # Combine and remove duplicates by groupId if available
        $allAssignments = @($existingAssignments + $assignments) |
            Sort-Object { $_.target.groupId } -Unique
    } else {
        $allAssignments = @($assignments)
    }

    # Remove conflicting include/exclude assignments for same group
    $groupCounts = @{}
    foreach ($a in $allAssignments) {
        $gid = $a.target.groupId
        if ($gid) {
            if (-not $groupCounts.ContainsKey($gid)) {
                $groupCounts[$gid] = @()
            }
            $groupCounts[$gid] += $a.target.'@odata.type'
        }
    }
    foreach ($gid in $groupCounts.Keys) {
        if ($groupCounts[$gid] -contains "#microsoft.graph.exclusionGroupAssignmentTarget" -and
            $groupCounts[$gid] -contains "#microsoft.graph.groupAssignmentTarget") {
            # Write-Warning "Conflicting assignment for groupId $gid — removing exclusion duplicate."
            $allAssignments = $allAssignments | Where-Object {
                !($_.target.groupId -eq $gid -and $_.target.'@odata.type' -eq "#microsoft.graph.exclusionGroupAssignmentTarget")
            }
        }
    }

    # Apply Assignments if there are any to apply
    if ($allAssignments.Count -gt 0) {

        # Filter out invalid entries (no groupId)
        $allAssignments = $allAssignments | Where-Object {
            $_.target.groupId -and $_.target.groupId -ne ""
        }

        if (-not $allAssignments -or $allAssignments.Count -eq 0) {
            Write-Warning "No valid assignments to apply for $PolicyId — skipping /assign call."
            return
        }

        # Remove null filter fields
        $body = @{
            assignments = $allAssignments | ForEach-Object {
                if (-not $_.target.deviceAndAppManagementAssignmentFilterId) {
                    $_.target.Remove("deviceAndAppManagementAssignmentFilterId")
                    $_.target.Remove("deviceAndAppManagementAssignmentFilterType")
                }
                $_
            }
        } | ConvertTo-Json -Depth 10

        # Write-Output "Final assignment payload:"
        # $allAssignments | ConvertTo-Json -Depth 10

        try {
            Invoke-RestMethod -Headers $Headers -Method POST -Uri "$uri/$PolicyId/assign" -Body $body
            Write-Output "Policy assignment completed (existing + new preserved)."
        } catch {
            Write-Error "Failed to assign policy: $_"
        }
    } else {
        Write-Output "No assignments to apply."
    }

    # -----------------------
    # Scope Tags Assignment
    # -----------------------
    if ($ScopeTags -and $ScopeTags.Count -gt 0) {
        $scopeBody = @{
            roleScopeTagIds = $ScopeTags
        } | ConvertTo-Json -Depth 5

        try {
            Invoke-RestMethod -Headers $Headers -Method PATCH -Uri "$uri/$PolicyId" -Body $scopeBody -ContentType "application/json"
            Write-Output "Scope tags applied."
        } catch {
            Write-Error "Failed to apply scope tags: $_"
        }
    }
}
