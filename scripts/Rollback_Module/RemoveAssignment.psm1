# Import required functions
. "$PSScriptRoot\Get-AccessToken.ps1"
. "$PSScriptRoot\Get-DatabaseConnection.ps1"
. "$PSScriptRoot\GetPolicyDetails.ps1"

function Remove-PolicyAssignments {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PolicyId,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config,

        [Parameter(Mandatory = $true)]
        [ValidateSet("ADT", "Prod")]
        [string]$Source,

        [Parameter(Mandatory = $false)]
        [string[]]$AssignmentName,  # For SpecificAssignment

        [Parameter(Mandatory = $false)]
        [string[]]$FilterName,      # For SpecificFilter

        [Parameter(Mandatory = $true)]
        [ValidateSet("AllAssignments","SpecificAssignment","AllFilters","SpecificFilter")]
        [string]$ActionType
    )

    Write-Output "DEBUG: Remove-PolicyAssignments called with PolicyId='$PolicyId', Source='$Source', ActionType='$ActionType'"
    Write-Output "DEBUG: AssignmentName='$AssignmentName', FilterName='$FilterName'"

    try {
        # Step 1: Get access token
        $AccessToken = Get-AccessToken -Config $Config -Source $Source
        if (-not $AccessToken) { throw "Failed to obtain access token" }

        $Headers = @{ Authorization = "Bearer $AccessToken" }

        # Step 2: Get PolicyType from DB
        Write-Output "DEBUG: Retrieving policy details from DB for PolicyId: $PolicyId"
        $policyDetails = GetPolicyDetails -PolicyId $PolicyId -Config $Config
        if (-not $policyDetails -or $policyDetails.Count -eq 0) {
            Write-Output "DEBUG: Policy details not found in DB"
            throw "Policy with ID '$PolicyId' not found in database"
        }

        $originalPolicyType = $policyDetails.PolicyType
        Write-Output "DEBUG: Retrieved PolicyType: $originalPolicyType for Policy ID: $PolicyId"

        # Map DB type → Graph endpoint
        switch ($originalPolicyType) {
            "Compliance Policy"    { $PolicyType = "deviceCompliancePolicies" }
            "Configuration Policy" { $PolicyType = "configurationPolicies" }
            default { throw "Unknown PolicyType '$originalPolicyType' for Policy ID: $PolicyId" }
        }
        Write-Output "DEBUG: Mapped PolicyType to: $PolicyType"

        # Step 3: Verify policy exists before fetching assignments
        $policyCheckUriBeta = "https://graph.microsoft.com/beta/deviceManagement/$PolicyType/$PolicyId"
        $policyCheckUriV1 = "https://graph.microsoft.com/v1.0/deviceManagement/$PolicyType/$PolicyId"
        Write-Output "DEBUG: Checking if policy exists at: $policyCheckUriBeta"

        try {
            $policyResponse = Invoke-RestMethod -Uri $policyCheckUriBeta -Headers $Headers -Method GET -ErrorAction Stop
            Write-Output "DEBUG: Policy exists in beta. ID: $($policyResponse.id)"
        } catch {
            Write-Output "DEBUG: Policy not found in beta, trying v1.0..."
            try {
                $policyResponse = Invoke-RestMethod -Uri $policyCheckUriV1 -Headers $Headers -Method GET -ErrorAction Stop
                Write-Output "DEBUG: Policy exists in v1.0. ID: $($policyResponse.id)"
            } catch {
                Write-Output "ERROR: Policy with ID '$PolicyId' not found in either beta or v1.0. Check if the policy exists in your tenant."
                throw "Policy with ID '$PolicyId' not found in Graph API."
            }
        }

        # Step 4: Fetch assignments with beta→v1.0 fallback
        $baseUriBeta = "https://graph.microsoft.com/beta/deviceManagement/$PolicyType/$PolicyId/assignments"
        $baseUriV1   = "https://graph.microsoft.com/v1.0/deviceManagement/$PolicyType/$PolicyId/assignments"
        Write-Output "DEBUG: Beta URI: $baseUriBeta"
        Write-Output "DEBUG: V1.0 URI: $baseUriV1"

        try {
            Write-Output "DEBUG: Attempting fetch from beta URI"
            $AssignmentsResponse = Invoke-RestMethod -Uri $baseUriBeta -Headers $Headers -Method GET -ErrorAction Stop
            $AssignmentsUri = $baseUriBeta
            Write-Output "DEBUG: Beta fetch successful. Response count: $($AssignmentsResponse.value.Count)"
        }
        catch [System.Net.WebException] {
            Write-Output "DEBUG: Beta fetch failed. Exception: $($_.Exception.Message)"
            try {
                Write-Warning "DEBUG: Assignments not found at /beta, retrying with /v1.0..."
                Write-Output "DEBUG: Attempting fetch from v1.0 URI"
                $AssignmentsResponse = Invoke-RestMethod -Uri $baseUriV1 -Headers $Headers -Method GET -ErrorAction Stop
                $AssignmentsUri = $baseUriV1
                Write-Output "DEBUG: V1.0 fetch successful. Response count: $($AssignmentsResponse.value.Count)"
            } catch {
                Write-Output "DEBUG: V1.0 fetch also failed. Exception: $($_.Exception.Message)"
                throw $_
            }
        }

        if (-not $AssignmentsResponse.value -or $AssignmentsResponse.value.Count -eq 0) {
            Write-Output "No assignments found for Policy ID: $PolicyId"
            return
        }

        # Step 4: Fetch assignment filters (optional)
        $filtersMap = @{}
        try {
            $filtersUri = "https://graph.microsoft.com/beta/deviceManagement/assignmentFilters"
            $filtersResponseRaw = Invoke-RestMethod -Uri $filtersUri -Headers $Headers -Method GET
            foreach ($f in $filtersResponseRaw.value) {
                if ($f.displayName -and $f.id) {
                    $filtersMap[$f.displayName.ToLower()] = $f.id
                }
            }
        } catch {
            Write-Warning "Could not retrieve assignment filters: $($_ | Out-String)"
        }

        # Step 5: Normalize assignments
        $assignments = foreach ($a in $AssignmentsResponse.value) {
            $rawTarget = $a.target
            $groupName = "Unknown"
            if ($rawTarget -and $rawTarget.groupId) {
                try {
                    $grp = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/groups/$($rawTarget.groupId)" -Headers $Headers -Method GET
                    $groupName = if ($grp.displayName) { $grp.displayName } else { "Unknown ($($rawTarget.groupId))" }
                } catch {
                    $groupName = "Unknown ($($rawTarget.groupId))"
                }
            }

            $filterName = ""
            if ($rawTarget -and $rawTarget.deviceAndAppManagementAssignmentFilterId -and
                $rawTarget.deviceAndAppManagementAssignmentFilterId -ne "00000000-0000-0000-0000-000000000000") {
                $filter = $filtersMap.GetEnumerator() | Where-Object { $_.Value -eq $rawTarget.deviceAndAppManagementAssignmentFilterId }
                $filterName = if ($filter) { $filter.Key } else { "" }
            }

            [PSCustomObject]@{
                AssignmentId = $a.id
                GroupId      = if ($rawTarget) { $rawTarget.groupId } else { $null }
                GroupName    = $groupName
                FilterId     = if ($rawTarget) { $rawTarget.deviceAndAppManagementAssignmentFilterId } else { $null }
                FilterName   = $filterName
                RawTarget    = $rawTarget
            }
        }

        # Step 6: Normalize inputs
        if ($AssignmentName) {
            $AssignmentName = @($AssignmentName) | Where-Object { $_ } | ForEach-Object { $_.Trim() }
        } else { $AssignmentName = @() }

        if ($FilterName) {
            $FilterName = @($FilterName) | Where-Object { $_ } | ForEach-Object { $_.Trim() }
        } else { $FilterName = @() }

        # Step 7: Select assignments to process
        switch ($ActionType) {
            "AllAssignments" { $assignmentsToProcess = $assignments }
            "SpecificAssignment" {
                if (-not $AssignmentName) { throw "Provide -AssignmentName for SpecificAssignment" }
                $namesClean = $AssignmentName | ForEach-Object { $_.ToLower() }
                $assignmentsToProcess = $assignments | Where-Object { $_.GroupName -and ($namesClean -contains $_.GroupName.Trim().ToLower()) }
            }
            "AllFilters" {
                $assignmentsToProcess = $assignments | Where-Object { $_.FilterId -and $_.FilterId -ne "00000000-0000-0000-0000-000000000000" }
            }
            "SpecificFilter" {
                if (-not $FilterName -or $FilterName.Count -eq 0) { throw "Provide valid -FilterName(s) for SpecificFilter" }
                $filterNamesClean = @()
                foreach ($f in $FilterName) {
                    $splitFilters = $f -split '\s*,\s*' | ForEach-Object { $_.Trim().ToLower() }
                    $filterNamesClean += $splitFilters | Where-Object { $_ -ne "" }
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

        Write-Output "`nAssignments to process:"
        $assignmentsToProcess | Format-Table GroupName, FilterName, AssignmentId -AutoSize

        # Step 8: Remove assignments
        if ($PolicyType -eq "deviceCompliancePolicies" -or $PolicyType -eq "configurationPolicies") {
            # Compliance → replace entire assignments array
            $remainingAssignments = @()
            foreach ($a in $assignments) {
                if ($assignmentsToProcess.AssignmentId -contains $a.AssignmentId) {
                    switch ($ActionType) {
                        "SpecificAssignment" { Write-Output "Removing assignment for group '$($a.GroupName)'" }
                        "SpecificFilter" {
                            $target = @{ "@odata.type" = $a.RawTarget.'@odata.type' }
                            if ($a.RawTarget.groupId) { $target.groupId = $a.RawTarget.groupId }
                            $remainingAssignments += @{ target = $target }
                            Write-Output "Removed filter for group '$($a.GroupName)'" }
                        "AllAssignments" { }
                        "AllFilters" {
                            $target = @{ "@odata.type" = $a.RawTarget.'@odata.type' }
                            if ($a.RawTarget.groupId) { $target.groupId = $a.RawTarget.groupId }
                            $remainingAssignments += @{ target = $target }
                            Write-Output "Removed filter for group '$($a.GroupName)'" }
                    }
                } else {
                    $remainingAssignments += @{ target = $a.RawTarget }
                }
            }

            $body = @{ assignments = $remainingAssignments } | ConvertTo-Json -Depth 6 -Compress
            $postUri = "https://graph.microsoft.com/beta/deviceManagement/$PolicyType/$PolicyId/assign"
            Write-Output "Submitting compliance policy assignments body:`n$body"
            Invoke-RestMethod -Uri $postUri -Headers $Headers -Method POST -Body $body -ContentType "application/json"
            Write-Output "Updated compliance policy assignments successfully."
        }
        else {
            # Config → delete or recreate individually
            foreach ($assignment in $assignmentsToProcess) {
                try {
                    # Extract the actual assignment ID by splitting on '_' and taking the part after the policy ID
                    $actualAssignmentId = $assignment.AssignmentId -split '_' | Select-Object -Last 1
                    Write-Output "DEBUG: Using assignment ID '$actualAssignmentId' from full '$($assignment.AssignmentId)'"
                    $removeUri = "https://graph.microsoft.com/beta/deviceManagement/$PolicyType/$PolicyId/assignments/$actualAssignmentId"
                    Write-Output "DEBUG: Deleting assignment with URI: $removeUri"
                    Invoke-RestMethod -Uri $removeUri -Headers $Headers -Method DELETE

                    if ($ActionType -eq "SpecificAssignment") {
                        Write-Output "Removed assignment for group '$($assignment.GroupName)'"
                    }
                    elseif ($ActionType -in @("AllFilters","SpecificFilter")) {
                        Write-Output "Removed filter assignment for group '$($assignment.GroupName)'"
                        $odataType = $assignment.RawTarget.'@odata.type'
                        $postUri = "https://graph.microsoft.com/beta/deviceManagement/$PolicyType/$PolicyId/assignments"
                        $body = @{ target = @{ "@odata.type" = $odataType; groupId = $assignment.GroupId } } | ConvertTo-Json -Depth 5
                        Invoke-RestMethod -Uri $postUri -Headers $Headers -Method POST -Body $body -ContentType "application/json"
                        Write-Output "Recreated assignment without filter for group '$($assignment.GroupName)'"
                    }
                } catch {
                    Write-Warning "Error processing assignment $($assignment.AssignmentId): $($_ | Out-String)"
                }
            }
        }
    } catch {
        Write-Output "DEBUG: Final exception in Remove-PolicyAssignments. Exception: $($_.Exception.Message), StackTrace: $($_.Exception.StackTrace)"
        throw "Error processing assignments: $($_ | Out-String)"
    }
}

Export-ModuleMember -Function Remove-PolicyAssignments
