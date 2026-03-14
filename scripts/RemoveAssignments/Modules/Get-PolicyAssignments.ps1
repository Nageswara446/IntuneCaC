function Get-PolicyAssignments {
    param([string]$PolicyId, [string]$PolicyType, $Headers)
    $uri = "https://graph.microsoft.com/beta/deviceManagement/$PolicyType/$PolicyId/assignments"
    try { 
        $response = Invoke-RestMethod -Uri $uri -Headers $Headers -Method GET 
    }
    catch { Write-Warning "Failed to get assignments for Policy $PolicyId : $_"; return @() }

    $filters = @{}
    try {
        $filtersUri = "https://graph.microsoft.com/beta/deviceManagement/assignmentFilters"
        $filtersResponse = Invoke-RestMethod -Uri $filtersUri -Headers $Headers -Method GET
        foreach ($f in $filtersResponse.value) { $filters[$f.id] = $f.displayName }
    } catch { Write-Warning "Could not fetch assignment filters" }

    $assignments = foreach ($a in $response.value) {
        $filterName = ""
        if ($a.target.deviceAndAppManagementAssignmentFilterId) {
            $filterId = $a.target.deviceAndAppManagementAssignmentFilterId
            $filterName = if ($filters.ContainsKey($filterId)) { $filters[$filterId] } else { "Unknown Filter ($filterId)" }
        }
        $groupName = if ($a.target.groupId) { Get-GroupName -GroupId $a.target.groupId -Headers $Headers } else { "" }
        [PSCustomObject]@{
            AssignmentId = $a.id
            GroupId      = $a.target.groupId
            GroupName    = $groupName
            TargetType   = $a.target.'@odata.type'
            Intent       = $a.intent
            FilterId     = $a.target.deviceAndAppManagementAssignmentFilterId
            FilterName   = $filterName
        }
    }
    return $assignments
}
