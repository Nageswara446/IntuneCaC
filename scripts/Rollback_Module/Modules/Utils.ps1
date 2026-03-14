function Get-PolicyFilePath {
    param (
        [Parameter(Mandatory)]
        [string]$PolicyId
    )

    return ".\GitRepo\Policies\policy_$PolicyId.json"
}
