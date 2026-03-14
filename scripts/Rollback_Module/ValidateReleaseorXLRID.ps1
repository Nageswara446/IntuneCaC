. "$PSScriptRoot\..\Modules\Common\Get-DatabaseConnection.ps1"
function ValidateXLRIDorReleaseTag {

    param (
        [Parameter(Mandatory)][PSCustomObject]$Configuration,
        [Parameter(Mandatory)][string]$XLRIDReleaseTag,
        [Parameter(Mandatory)][string]$XLRIDReleaseTagValue,
        [Parameter(Mandatory)][string]$policy,
        [string]$PolicyID
    )

    $connection = $null
    $result = [PSCustomObject]@{
        Success      = $false
        Response     = $null
        ErrorMessage = ""
    }
    $PolicyIDArray = @()
    if ($policy -eq 'Specific Policy') {
        if (-not [string]::IsNullOrWhiteSpace($PolicyID)) {
            $PolicyIDArray = $PolicyID -split ',' | ForEach-Object { $_.Trim() }
        } else {
            $result.ErrorMessage = "PolicyID must be provided when policy is 'Specific Policy'."
            return $result
        }
    }

    $configPath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath "..\Modules\Common\config.json")
    $Config = Get-Content -Raw -Path $configPath | ConvertFrom-Json

    if ($XLRIDReleaseTag -eq 'XLRelease ID') {

        $connection = Get-DatabaseConnection -Config $Config

        # 1️⃣ Check if WorkflowID exists
        $command = $connection.CreateCommand()
        $command.CommandText = @"
            SELECT COUNT(*) AS RecordCount
            FROM unified_release_management.policies 
            WHERE WorkflowID = @XLRIDReleaseTagValue 
            AND ActionType IN ('Create New Policy') 
            AND Is_Deleted = 'False'
"@
        $command.Parameters.AddWithValue("@XLRIDReleaseTagValue", $XLRIDReleaseTagValue) | Out-Null
        $reader = $command.ExecuteReader()
        $count = if ($reader.Read()) { $reader["RecordCount"] } else { 0 }
        $reader.Close()

        if ($count -le 0) {
            $result.ErrorMessage = "XLR ID does not exist."
            return $result
        }
	

        # 2️⃣ Get all Create New Policy records for this WorkflowID
        $command2 = $connection.CreateCommand()
        $command2.CommandText = @"
            SELECT PolicyGuid, GitPath, Environment, PolicyType, WorkflowID
            FROM unified_release_management.policies 
            WHERE WorkflowID = @XLRIDReleaseTagValue 
            AND ActionType IN ('Create New Policy') 
            AND Is_Deleted = 'False'
"@
        $command2.Parameters.AddWithValue("@XLRIDReleaseTagValue", $XLRIDReleaseTagValue) | Out-Null
        $reader2 = $command2.ExecuteReader()
	
        $releaseList = @()
        while ($reader2.Read()) {
            $releaseList += [PSCustomObject]@{
                GitPath       = $reader2["GitPath"]
                Environment   = $reader2["Environment"]
                PolicyType    = $reader2["PolicyType"]
                WorkflowID    = $reader2["WorkflowID"]
                PolicyGuid    = $reader2["PolicyGuid"]
            }
        }
        $reader2.Close()

        # 3️⃣ Iterate over each record
        foreach ($item in $releaseList) {

            $Policy_Guid = $item.PolicyGuid
            $GitPath     = $item.GitPath

            # Skip if not in specified list
            if ($policy -eq 'Specific Policy' -and -not ($PolicyIDArray -contains $Policy_Guid)) {
                # Write-Host "Skipping PolicyGuid $Policy_Guid as it is not in specified list."
                continue
            }

            # Extract Policy GUID from GitPath
            if ($GitPath -match '/([0-9a-fA-F-]{36})\.json$') {
                $extractedPolicyGuid = $matches[1]
            } else {
                # Write-Host "Could not extract PolicyGuid from GitPath for $Policy_Guid"
                continue
            }

            # 4️⃣ Get Export Policy corresponding to Create New Policy
            $command3 = $connection.CreateCommand()
            $command3.CommandText = @"
                SELECT PolicyGuid, PolicyName, GitPath, Environment, PolicyType, WorkflowID
                FROM unified_release_management.policies 
                WHERE WorkflowID = @XLRIDReleaseTagValue
                AND ActionType IN ('Export Policy') 
                AND Is_Deleted = 'False'
                AND GitPath LIKE CONCAT('%', @extractedPolicyGuid, '%')
"@
            $command3.Parameters.AddWithValue("@XLRIDReleaseTagValue", $XLRIDReleaseTagValue) | Out-Null
            $command3.Parameters.AddWithValue("@extractedPolicyGuid", $extractedPolicyGuid) | Out-Null

            $reader3 = $command3.ExecuteReader()
            $foundExport = $false
            while ($reader3.Read()) {
                $foundExport = $true
                $finalGitPath   = $reader3["GitPath"]
                $finalPolicyGuid = $reader3["PolicyGuid"]
                $finalPolicyName = $reader3["PolicyName"]
                $release_env    = $reader3["Environment"]
                $release_policytype = $reader3["PolicyType"]
                $release_workflowID = $reader3["WorkflowID"]

                $ReleaseVersion = $null
                if ($finalGitPath -match 'releases/download/(Release-[^/]+)') {
                    $ReleaseVersion = $matches[1]
                }
            }
            $reader3.Close()

            if (-not $foundExport) {
                # Write-Host "No Export Policy found for PolicyGuid $Policy_Guid"
                continue
            }

            # 5️⃣ Validate GitHub release and assets
            $Token       = $Config.Git.GitPAT
            $RepoOwner   = $Config.Git.repoOwner
            $RepoName    = $Config.Git.repoName
            $ApiBaseUrl  = $Config.Git.rawUrl
            $TagName     = $ReleaseVersion
            $AssetName   = "$finalPolicyGuid.json"
            $AssignmentAssetName = "${finalPolicyGuid}_assignment.json"
            $releaseUrl  = "$ApiBaseUrl/api/v3/repos/$RepoOwner/$RepoName/releases/tags/$TagName"

            $headers = @{
                Authorization = "token $Token"
                Accept        = "application/json"
                "User-Agent"  = "MyPowerShellScript/1.0"
            }

            try {
                $release = Invoke-RestMethod -Uri $releaseUrl -Headers $headers -Method Get
            } catch {
                # Write-Host "Failed to get release for tag $TagName. $_"
                continue
            }

            $asset = $release.assets | Where-Object { $_.name -eq $AssetName }
            if ($asset) {
                $GitPathdb += "$Policy_Guid - $release_env - $release_policytype - $release_workflowID - $GitPath;"
                $PolicyValidation += "Exported $release_policytype found with name - $finalPolicyName and Id - $Policy_Guid in $release_workflowID;"

                $assignmentAsset = $release.assets | Where-Object { $_.name -eq $AssignmentAssetName }
                if ($assignmentAsset) {
                    # Write-Host "Assignment asset found for $Policy_Guid"
                } else {
                    # Write-Host "Assignment asset not found for $Policy_Guid"
                }
            } else {
                $result.ErrorMessage = "Asset $AssetName not found for PolicyGuid $Policy_Guid"
                continue
            }
        }

        $result.Success  = $true
        $result.Response = "Validation Report: $($PolicyValidation)"
        # $result.Response = "Validation Report: $($PolicyValidation) Exists: $($GitPathdb)"
        return $result
    }

    if ($XLRIDReleaseTag -eq 'Release Tag' -and $policy -ne 'Specific Policy') {
        $connection = Get-DatabaseConnection -Config $Config

        # --- FIRST QUERY ---
        $command = $connection.CreateCommand()
        $query = @"
            SELECT COUNT(*) AS RecordCount
            FROM unified_release_management.policies 
            WHERE GitPath LIKE @XLRIDReleaseTagValue
            AND ActionType IN ('Export Policy') 
            AND Is_Deleted = 'False'    
"@
        $command.CommandText = $query
        $command.Parameters.AddWithValue("@XLRIDReleaseTagValue", "%$XLRIDReleaseTagValue%") | Out-Null
        # Write-Host "SQL Query with parameters replaced:"
        # Write-Host (Get-SqlCommandWithParametersReplaced -Command $command)

        # Write-Host "Executing first query to count matching Export Policies..." -ForegroundColor Yellow
        $reader = $command.ExecuteReader()
        $count = 0

        if ($reader.Read()) {
            $count = $reader["RecordCount"]
        }
        $reader.Close()
        # Write-Host "Export Policy record count: $count" -ForegroundColor Cyan

        if ($count -gt 0) {

            # --- SECOND QUERY ---
            Write-Host "Executing second query to fetch Export Policy details..." -ForegroundColor Yellow

            $command2 = $connection.CreateCommand()
            $query2 = @"
                SELECT PolicyGuid,GitPath,Environment,PolicyType,WorkflowID
                FROM unified_release_management.policies 
                WHERE GitPath LIKE @XLRIDReleaseTagValue
                AND ActionType IN ('Export Policy') 
                AND Is_Deleted = 'False'                
"@
            $command2.CommandText = $query2
            $command2.Parameters.AddWithValue("@XLRIDReleaseTagValue", "%$XLRIDReleaseTagValue%") | Out-Null
            # Write-Host "SQL Query with parameters replaced:"
            # Write-Host (Get-SqlCommandWithParametersReplaced -Command $command2)
            $reader2 = $command2.ExecuteReader()

            $releaseList = @()

            while ($reader2.Read()) {
                $obj = [PSCustomObject]@{
                    GitPathdb  = $reader2["GitPath"]
                    Env        = $reader2["Environment"]
                    PolicyType = $reader2["PolicyType"]
                    release_workflowID = $reader2["WorkflowID"]
                }
                # Write-Host "Fetched Export Policy: $($obj.GitPathdb) | Env: $($obj.Env) | Type: $($obj.PolicyType) | WF: $($obj.release_workflowID)" -ForegroundColor DarkGray
                $releaseList += $obj
            }
            $reader2.Close()
            # Write-Host "Total Export Policies found: $($releaseList.Count)" -ForegroundColor Cyan

            foreach ($item in $releaseList) {
                $release_git        = $item.GitPathdb
                $release_env        = $item.Env
                $release_policytype = $item.PolicyType
                $release_workflowID = $item.release_workflowID

                if ($release_git -match '/([0-9a-fA-F\-]{36})\.json$') {
                    $PolicyGuid = $matches[1]
                    # Write-Host "Extracted PolicyGuid from GitPath: $PolicyGuid" -ForegroundColor Magenta
                } else {
                    # Write-Host " Could not extract PolicyGuid from GitPath: $release_git" -ForegroundColor Red
                    continue
                }

                if ($policy -eq 'Specific Policy' -and -not ($PolicyIDArray -contains $PolicyGuid)) {
                    # Write-Host "Skipping PolicyGuid $PolicyGuid as it’s not in the specified list." -ForegroundColor DarkYellow
                    continue
                }

                # --- THIRD QUERY ---
                # Write-Host "Executing third query for Create New Policy for PolicyGuid: $PolicyGuid" -ForegroundColor Yellow

                $command3 = $connection.CreateCommand()
                $query3 = @"
                    SELECT PolicyGuid,PolicyName, GitPath,Environment,PolicyType,WorkflowID
                    FROM unified_release_management.policies 
                    WHERE GitPath LIKE @PolicyGuid
                    AND ActionType IN ('Create New Policy')
                    AND Is_Deleted = 'False'
"@
                $command3.CommandText = $query3
                $command3.Parameters.AddWithValue("@PolicyGuid", "%$PolicyGuid%") | Out-Null
                # Write-Host "SQL Query with parameters replaced:"
                # Write-Host (Get-SqlCommandWithParametersReplaced -Command $command3)
                $reader3 = $command3.ExecuteReader()

                $NewPolicyGuid = $null
                if ($reader3.Read()) {
                    $NewPolicyGuid = $reader3["PolicyGuid"]
                    $NewPolicyName = $reader3["PolicyName"]
                    # Write-Host "Found Create New Policy entry. NewPolicyGuid: $NewPolicyGuid" -ForegroundColor Green
                } else {
                    # Write-Host " No Create New Policy found for $PolicyGuid" -ForegroundColor Red
                }
                $reader3.Close()

                # --- VALIDATION OUTPUT ---
                if ($null -ne $NewPolicyGuid) {
                    $PolicyValidation += "Exported $release_policytype found with name - $NewPolicyName and ID - $NewPolicyGuid in $release_workflowID;"
                    # Write-Host " Exported $release_policytype found with $NewPolicyGuid in $release_workflowID" -ForegroundColor Green
                } else {
                    $PolicyValidation += "Exported $release_policytype found with (no matching 'Create New Policy' found) for $PolicyGuid in $release_workflowID;"
                    # Write-Host " No Create New Policy match for Exported $release_policytype ($PolicyGuid) in $release_workflowID" -ForegroundColor Red
                }
            }

            # Write-Host "Final PolicyValidation summary: $PolicyValidation" -ForegroundColor Cyan

            $result.Success  = $true
            $result.Response = "Validation Report : $($PolicyValidation)"
            # Write-Host "Script completed successfully!" -ForegroundColor Green
            return $result

        } else {
            # Write-Host " No Export Policies found for release tag $XLRIDReleaseTagValue" -ForegroundColor Red
            $result.ErrorMessage = "Release not found for tag $TagName"
            return $result
        }
    }

    if ($XLRIDReleaseTag -eq 'Release Tag' -and $policy -eq 'Specific Policy') {
        # Write-Host ">>> Starting validation for Release Tag with Specific Policy: $XLRIDReleaseTagValue" -ForegroundColor Cyan

        $connection = Get-DatabaseConnection -Config $Config
        # Write-Host "Database connection established successfully." -ForegroundColor Green

        # --- FIRST QUERY ---
        $command = $connection.CreateCommand()
        $query = @"
            SELECT COUNT(*) AS RecordCount
            FROM unified_release_management.policies
            WHERE GitPath LIKE @XLRIDReleaseTagValue
            AND ActionType IN ('Export Policy')
            AND Is_Deleted = 'False'
"@
        $command.CommandText = $query
        $command.Parameters.AddWithValue("@XLRIDReleaseTagValue", "%$XLRIDReleaseTagValue%") | Out-Null
        # Write-Host "SQL Query with parameters replaced:"
        # Write-Host (Get-SqlCommandWithParametersReplaced -Command $command)

        # Write-Host "Executing first query to count matching Export Policies..." -ForegroundColor Yellow
        $reader = $command.ExecuteReader()
        $count = 0
        if ($reader.Read()) { $count = $reader["RecordCount"] }
        $reader.Close()
        # Write-Host "Export Policy record count: $count" -ForegroundColor Cyan

        if ($count -gt 0) {

            # --- SECOND QUERY ---
            # Write-Host "Executing second query to fetch Export Policy details..." -ForegroundColor Yellow

            $command2 = $connection.CreateCommand()
            $query2 = @"
                SELECT PolicyGuid,GitPath,Environment,PolicyType,WorkflowID
                FROM unified_release_management.policies
                WHERE GitPath LIKE @XLRIDReleaseTagValue
                AND ActionType IN ('Export Policy')
                AND Is_Deleted = 'False'
"@
            $command2.CommandText = $query2
            $command2.Parameters.AddWithValue("@XLRIDReleaseTagValue", "%$XLRIDReleaseTagValue%") | Out-Null
            # Write-Host "SQL Query with parameters replaced:"
            # Write-Host (Get-SqlCommandWithParametersReplaced -Command $command2)
            $reader2 = $command2.ExecuteReader()

            $releaseList = @()
            while ($reader2.Read()) {
                $obj = [PSCustomObject]@{
                    GitPathdb        = $reader2["GitPath"]
                    Env              = $reader2["Environment"]
                    PolicyType       = $reader2["PolicyType"]
                    release_workflowID = $reader2["WorkflowID"]
                }
                # Write-Host "Fetched Export Policy: $($obj.GitPathdb) | Env: $($obj.Env) | Type: $($obj.PolicyType) | WF: $($obj.release_workflowID)" -ForegroundColor DarkGray
                $releaseList += $obj
            }
            $reader2.Close()
            # Write-Host "Total Export Policies found: $($releaseList.Count)" -ForegroundColor Cyan

            foreach ($item in $releaseList) {
                $release_git        = $item.GitPathdb
                $release_env        = $item.Env
                $release_policytype = $item.PolicyType
                $release_workflowID = $item.release_workflowID

                if ($release_git -match '/([0-9a-fA-F\-]{36})\.json$') {
                    $PolicyGuid = $matches[1]
                    # Write-Host "Extracted PolicyGuid from GitPath: $PolicyGuid" -ForegroundColor Magenta
                } else {
                    # Write-Host "Could not extract PolicyGuid from GitPath: $release_git" -ForegroundColor Red
                    continue
                }

                # --- NEW SPECIFIC POLICY LOGIC ---
                if ($policy -eq 'Specific Policy') {
                    # Query to get NewPolicyGuid for the current PolicyGuid
                    $commandCheck = $connection.CreateCommand()
                    $queryCheck = @"
                        SELECT PolicyGuid, PolicyName
                        FROM unified_release_management.policies
                        WHERE GitPath LIKE @PolicyGuid
                        AND ActionType IN ('Create New Policy')
                        AND Is_Deleted = 'False'
"@
                    $commandCheck.CommandText = $queryCheck
                    $commandCheck.Parameters.AddWithValue("@PolicyGuid", "%$PolicyGuid%") | Out-Null
                    # Write-Host "Executing query to fetch NewPolicyGuid for PolicyGuid: $PolicyGuid" -ForegroundColor Yellow
                    $readerCheck = $commandCheck.ExecuteReader()

                    $NewPolicyGuid = $null
                    if ($readerCheck.Read()) {
                        $NewPolicyGuid = $readerCheck["PolicyGuid"]
                        $NewPolicyName = $readerCheck["PolicyName"]
                        # Write-Host "Found Create New Policy entry. NewPolicyGuid: $NewPolicyGuid" -ForegroundColor Green
                    } else {
                        # Write-Host "No Create New Policy found for $PolicyGuid" -ForegroundColor Red
                    }
                    $readerCheck.Close()

                    # Skip if NewPolicyGuid is not in the specified list
                    if (-not ($PolicyIDArray -contains $NewPolicyGuid)) {
                        # Write-Host "Skipping PolicyGuid $PolicyGuid because NewPolicyGuid $NewPolicyGuid is not in the specified list." -ForegroundColor DarkYellow
                        continue
                    }
                }

                # --- VALIDATION OUTPUT ---
                if ($null -ne $NewPolicyGuid) {
                    $PolicyValidation += "Exported $release_policytype found with name - $NewPolicyName and ID - $NewPolicyGuid in $release_workflowID;"
                    # Write-Host "Exported $release_policytype found with $NewPolicyGuid in $release_workflowID" -ForegroundColor Green
                } else {
                    $PolicyValidation += "Exported $release_policytype found with (no matching 'Create New Policy' found) for $PolicyGuid in $release_workflowID;"
                    # Write-Host "No Create New Policy match for Exported $release_policytype ($PolicyGuid) in $release_workflowID" -ForegroundColor Red
                }
            }

            # Write-Host "Final PolicyValidation summary: $PolicyValidation" -ForegroundColor Cyan
            $result.Success  = $true
            $result.Response = "Validation Report : $($PolicyValidation)"
            # Write-Host "Script completed successfully!" -ForegroundColor Green
            return $result

        } else {
            Write-Host "No Export Policies found for release tag $XLRIDReleaseTagValue" -ForegroundColor Red
            $result.ErrorMessage = "Release not found for tag $TagName"
            return $result
        }

    } else {
        Write-Host "Provided tag is not 'Release Tag'. Value: $XLRIDReleaseTag" -ForegroundColor Red
        $result.ErrorMessage = "Release Tag does not exist in database"
        return $result
    }


}
    # } catch {
    #     $result.ErrorMessage = "Failed to validate release or git tag: $($_.Exception.Message)"
    #     if ($_.Exception.Response -ne $null) {
    #         $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
    #         $result.ErrorMessage += "`n" + $reader.ReadToEnd()
    #     }
    #     return $result
    # }


function Get-SqlCommandWithParametersReplaced {
    param(
        [System.Data.Common.DbCommand]$Command
    )

    $query = $Command.CommandText

    foreach ($param in $Command.Parameters) {
        $paramName = $param.ParameterName
        $paramValue = $param.Value

        if ($null -eq $paramValue) {
            $replacement = "NULL"
        } elseif ($paramValue -is [string]) {
            $escapedValue = $paramValue.Replace("'", "''")
            $replacement = "'$escapedValue'"
        } elseif ($paramValue -is [DateTime]) {
            $replacement = "'$($paramValue.ToString("yyyy-MM-dd HH:mm:ss"))'"
        } else {
            $replacement = $paramValue.ToString()
        }

        $query = $query -replace [regex]::Escape($paramName), $replacement
    }

    return $query
}



