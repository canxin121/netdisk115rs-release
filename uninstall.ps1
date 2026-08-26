[CmdletBinding()]
param([switch]$Purge)
$ErrorActionPreference = "Stop"
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Administrator PowerShell is required."
}
$service = Get-Service -Name "netdisk115rs" -ErrorAction SilentlyContinue
if ($service) {
    Stop-Service -Name "netdisk115rs" -Force -ErrorAction SilentlyContinue
    sc.exe delete netdisk115rs | Out-Null
}
Remove-Item -Recurse -Force (Join-Path $env:ProgramFiles "netdisk115rs") -ErrorAction SilentlyContinue
if ($Purge) {
    Remove-Item -Recurse -Force (Join-Path $env:ProgramData "netdisk115rs") -ErrorAction SilentlyContinue
}
Write-Host "netdisk115rs removed. State $($(if ($Purge) {'purged'} else {'preserved'}))."
