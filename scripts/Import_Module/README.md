New-ModuleManifest -Path ".\Import-Policy.psd1" -RootModule 'Import-Policy.psm1' -ModuleVersion '1.0.0'
Import-Module ".\Import_Module\Import-Policy.psm1" -Force -Verbose
Get-Command Import-Policy
