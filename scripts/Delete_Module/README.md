New-ModuleManifest -Path ".\Delete-Policy.psd1" -RootModule 'Delete-Policy.psm1' -ModuleVersion '1.0.0'
Import-Module ".\Delete-Policy.psm1" -Force -Verbose
Get-Command Delete-Policy
Delete-Policy -Destination "Prod" -PolicyIDs "126,30b08cc" -Action "Delete Policy" -WorkFlowID "10006" -WorkFlowTaskID  "001"
