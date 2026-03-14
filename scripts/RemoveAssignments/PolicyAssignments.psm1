<#
.SYNOPSIS
    PowerShell module for managing Intune policy assignments via Microsoft Graph.

.DESCRIPTION
    Provides functions to retrieve scope tags, groups, policies, and assignments,
    and to remove assignments/filters for compliance and configuration policies.

.AUTHOR
    Saurabh Saxena
#>

# Import required modules
. "$PSScriptRoot\Modules\Get-AccessToken.ps1"
. "$PSScriptRoot\Modules\Get-AllGraphItems.ps1"
. "$PSScriptRoot\Modules\Get-DatabaseConnection.ps1"
. "$PSScriptRoot\Modules\Confirm-Policy.ps1"
. "$PSScriptRoot\Modules\Remove-PolicyAssignments.ps1"
. "$PSScriptRoot\Modules\Get-ScopeTagDetails.ps1"
. "$PSScriptRoot\Modules\Get-GroupName.ps1"
. "$PSScriptRoot\Modules\Get-PolicyAssignments.ps1"
. "$PSScriptRoot\Modules\Get-DeviceConfigDetails.ps1"
. "$PSScriptRoot\Modules\Get-DeviceCompliancePolicyDetails.ps1"
. "$PSScriptRoot\Modules\Export-PolicyAssignments.ps1"
. "$PSScriptRoot\Modules\Push-PolicyJsonToGitHub.ps1"

function Invoke-PolicyAssignmentAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Environment,  # ADT or Prod

        [Parameter(Mandatory = $true)]
        [string]$PolicyID,     # Single policy ID

        [Parameter(Mandatory = $true)]
        [ValidateSet("AllAssignments", "SpecificAssignment", "AllFilters", "SpecificFilter")]
        [string]$ActionType,

        [Parameter(Mandatory = $false)]
        [string[]]$AssignmentName,  # Required if ActionType = SpecificAssignment

        [Parameter(Mandatory = $false)]
        [string[]]$FilterName       # Required if ActionType = SpecificFilter
    )

    $configPath = "$PSScriptRoot\config.json"
    if (-not (Test-Path $configPath)) { throw "Config file not found at $configPath" }
    $config = Get-Content -Path $configPath | ConvertFrom-Json

    # Authenticate
    $Token = Get-AccessToken -Environment $Environment -Config $config
    $headers = @{
        Authorization = "Bearer $Token"
        'Content-Type' = 'application/json'
        'Accept'       = 'application/json'
    }

    $scopeTags = Get-ScopeTagDetails -Headers $headers
    try {
        $configs = Get-AllGraphItems -Uri $config.GraphApi.Endpoints.DeviceConfiguration.Url -Headers $headers
        $configsCatalog = Get-AllGraphItems -Uri $config.GraphApi.Endpoints.SettingsCatalog.Url -Headers $headers
        $compliances    = Get-AllGraphItems -Uri $config.GraphApi.Endpoints.Compliance.Url -Headers $headers

        # Write-Output "Fetched configs: $($configs.Count)"
        # Write-Output "Fetched configsCatalog: $($configsCatalog.Count)"
        # Write-Output "Fetched compliances: $($compliances.Count)"
    }
    catch {
        throw "Failed to fetch policies: $_"
    }


    $PolicyExist = Confirm-Policy -PolicyID $PolicyID -Config $config
    if (-not $PolicyExist) { 
        return [PSCustomObject]@{
            PolicyID = $PolicyID
            Status   = "NotFound"
            Message  = "Record not found in DB"
        }
    }

    $matchedPolicy = $configs | Where-Object { $_.id -eq $PolicyID } | ForEach-Object { Get-DeviceConfigDetails -DeviceConfig $_ -ScopeTags $scopeTags -Headers $headers }
    if (-not $matchedPolicy) {
        $matchedPolicy = $configsCatalog | Where-Object { $_.id -eq $PolicyID } | ForEach-Object { 
            Get-DeviceConfigDetails -DeviceConfig $_ -ScopeTags $scopeTags -Headers $headers 
        }
    }

    if (-not $matchedPolicy) {
        $matchedPolicy = $compliances | Where-Object { $_.id -eq $PolicyID } | ForEach-Object { Get-DeviceCompliancePolicyDetails -DeviceCompliancePolicy $_ -ScopeTags $scopeTags -Headers $headers }
    
    }

    if (-not $matchedPolicy) { 
        return [PSCustomObject]@{
            PolicyID = $PolicyID
            Status   = "NotFound"
            Message  = "Policy ID $PolicyID not found in Intune." 
        }
    }

    # Normalize inputs
    $AssignmentName = @($AssignmentName) -split '\s*,\s*' | Where-Object { $_ }
    if ($FilterName) {
        if ($FilterName -is [string]) {
            $FilterName = $FilterName -split '\s*,\s*'
        }
        elseif ($FilterName -is [array]) {
            $FilterName = $FilterName | ForEach-Object { $_ -split '\s*,\s*' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        }
        else {
            return [PSCustomObject]@{
                FilterName = $FilterName
                Status   = "NotFound"
                Message  = "Invalid FilterName $FilterName"
            }
        }
    }

    # BEFORE ACTION
    # Write-Output "`n=== POLICY DETAILS BEFORE ACTION ===`n"
    $assignmentsBefore = Get-PolicyAssignments -PolicyId $matchedPolicy.Id -PolicyType $matchedPolicy.PolicyType -Headers $headers
    $matchedPolicy | Format-List
    if ($assignmentsBefore.Count -gt 0) {
        # Write-Output "`nAssignments (Before):"
        $assignmentsBefore | Format-Table AssignmentId,GroupId,GroupName,Intent,FilterId,FilterName -AutoSize
        $TimestampId = Get-Date -Format "yyyyMMddHHmmss"
        $TempExportPath = ".\Backup_$TimestampId"
        # Write-Output "`nTaking backup of assignments..."
        $PolicyObject = [PSCustomObject]@{
            PolicyId       = $matchedPolicy.Id
            PolicyCategory = $matchedPolicy.PolicyType
        }
        Export-PolicyAssignments -AccessToken $Token -Policies $PolicyObject -AssignmentEndpointBase $config.GraphApi.AssignmentEndpointBase -TempExportPath $TempExportPath -Config $config
        Push-PolicyJsonToGitHub -GitHubPAT $config.Git.GitPAT -Policies $PolicyObject -BaseExportPath $TempExportPath -AssignmentsPath "$TempExportPath\Assignments" -Config $config
    } else {
        Write-Output "No assignments found for this policy."
    }
    # ACTION
    switch ($ActionType) {
        "AllAssignments" {
            Write-Output "`nRemoving ALL assignments... ${matchedPolicy.PolicyType}"
            Remove-PolicyAssignments -PolicyId $matchedPolicy.Id -PolicyType $matchedPolicy.PolicyType -Headers $headers -ActionType "AllAssignments"
        }
        "SpecificAssignment" {
            if (-not $AssignmentName) { throw "Error: Provide -AssignmentName" }
            Write-Output "`nRemoving specific assignments: $($AssignmentName -join ', ')"
            Remove-PolicyAssignments -PolicyId $matchedPolicy.Id -PolicyType $matchedPolicy.PolicyType -Headers $headers -ActionType "SpecificAssignment" -AssignmentName $AssignmentName
        }
        "AllFilters" {
            Write-Output "`nRemoving ALL filters (keeping assignments)..."
            Remove-PolicyAssignments -PolicyId $matchedPolicy.Id -PolicyType $matchedPolicy.PolicyType -Headers $headers -ActionType "AllFilters"
        }
        "SpecificFilter" {
            if (-not $FilterName) { throw "Error: Provide -FilterName" }
            Write-Output "`nRemoving specific filter(s): $($FilterName -join ', ')"
            Remove-PolicyAssignments -PolicyId $matchedPolicy.Id -PolicyType $matchedPolicy.PolicyType -Headers $headers -ActionType "SpecificFilter" -FilterName $FilterName
        }
    }

    # AFTER ACTION
    Write-Output "`n=== POLICY DETAILS AFTER ACTION ===`n"
    $assignmentsAfter = Get-PolicyAssignments -PolicyId $matchedPolicy.Id -PolicyType $matchedPolicy.PolicyType -Headers $headers
    $matchedPolicy | Format-List
    if ($assignmentsAfter.Count -gt 0) {
        Write-Output "`nAssignments (After):"
        $assignmentsAfter | Format-Table AssignmentId,GroupId,GroupName,Intent,FilterId,FilterName -AutoSize
    } else {
        Write-Output "No assignments remain for this policy."
    }
    if (Test-Path $TempExportPath) {
        Remove-Item -Path $TempExportPath -Recurse -Force
    }
}

Export-ModuleMember -Function Invoke-PolicyAssignmentAction
