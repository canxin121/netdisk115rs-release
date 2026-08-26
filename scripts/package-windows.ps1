param(
  [Parameter(Mandatory=$true)][string]$SourceDir,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [Parameter(Mandatory=$true)][string]$Arch
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$stage = Join-Path $env:RUNNER_TEMP ("netdisk115rs-package-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $stage | Out-Null
try {
  Copy-Item (Join-Path $SourceDir 'target\release\netdisk115rs.exe') (Join-Path $stage 'netdisk115rs.exe')
  Copy-Item (Join-Path $PSScriptRoot '..\service\windows-wrapper\target\release\netdisk115rs-service.exe') (Join-Path $stage 'netdisk115rs-service.exe')
  Copy-Item (Join-Path $SourceDir 'config.example.yaml') (Join-Path $stage 'config.example.yaml')
  Copy-Item (Join-Path $SourceDir 'static') (Join-Path $stage 'static') -Recurse
  (git -C $SourceDir rev-parse HEAD).Trim() | Set-Content -NoNewline (Join-Path $stage 'SOURCE_COMMIT.txt')
  $zip = Join-Path $OutDir "netdisk115rs-windows-$Arch.zip"
  if (Test-Path $zip) { Remove-Item $zip -Force }
  Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip
} finally {
  Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
}
