[CmdletBinding()]
param(
    [string]$Version = $(if ($env:NETDISK115RS_VERSION) { $env:NETDISK115RS_VERSION } else { "latest" }),
    [string]$ArchivePath = $(if ($env:NETDISK115RS_LOCAL_ARCHIVE) { $env:NETDISK115RS_LOCAL_ARCHIVE } else { "" }),
    [switch]$NoStart
)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$Repo = if ($env:NETDISK115RS_RELEASE_REPO) { $env:NETDISK115RS_RELEASE_REPO } else { "canxin121/netdisk115rs-release" }
$ServiceName = "netdisk115rs"
$InstallDir = Join-Path $env:ProgramFiles "netdisk115rs"
$StateDir = Join-Path $env:ProgramData "netdisk115rs"
$Binary = Join-Path $InstallDir "netdisk115rs.exe"
$Wrapper = Join-Path $InstallDir "netdisk115rs-service.exe"
$Config = Join-Path $StateDir "config.yaml"

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Administrator PowerShell is required because this installer creates a Windows Service."
}

$arch = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
switch ($arch) {
    "x64" { $AssetArch = "x86_64" }
    "arm64" { $AssetArch = "arm64" }
    default { throw "Unsupported Windows architecture: $arch" }
}
$Asset = "netdisk115rs-windows-$AssetArch.zip"

$temp = Join-Path ([IO.Path]::GetTempPath()) ("netdisk115rs-install-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    $archive = Join-Path $temp $Asset
    if ($ArchivePath) {
        Copy-Item -LiteralPath $ArchivePath -Destination $archive
    } else {
        $base = if ($Version -eq "latest") {
            "https://github.com/$Repo/releases/latest/download"
        } else {
            "https://github.com/$Repo/releases/download/$Version"
        }
        $url = "$base/$Asset"
        Write-Host "Downloading $url"
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $archive
        $sums = Join-Path $temp "SHA256SUMS"
        Invoke-WebRequest -UseBasicParsing -Uri "$base/SHA256SUMS" -OutFile $sums
        $line = Get-Content $sums | Where-Object { $_ -match ("\s\*?" + [regex]::Escape($Asset) + "$") } | Select-Object -First 1
        if (-not $line) { throw "SHA256SUMS does not contain $Asset" }
        $expected = ($line -split "\s+")[0].ToLowerInvariant()
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant()
        if ($actual -ne $expected) { throw "SHA-256 mismatch for $Asset" }
    }

    $pkg = Join-Path $temp "pkg"
    Expand-Archive -LiteralPath $archive -DestinationPath $pkg -Force
    foreach ($required in @("netdisk115rs.exe", "netdisk115rs-service.exe", "config.example.yaml", "static\index.html")) {
        if (-not (Test-Path (Join-Path $pkg $required))) { throw "Package is missing $required" }
    }

    $existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($existing) {
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        sc.exe delete $ServiceName | Out-Null
        for ($i = 0; $i -lt 30; $i++) {
            if (-not (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue)) { break }
            Start-Sleep -Milliseconds 500
        }
    }

    New-Item -ItemType Directory -Force -Path $InstallDir, $StateDir, (Join-Path $StateDir "logs") | Out-Null
    Copy-Item -Force (Join-Path $pkg "netdisk115rs.exe") $Binary
    Copy-Item -Force (Join-Path $pkg "netdisk115rs-service.exe") $Wrapper
    $static = Join-Path $StateDir "static"
    if (Test-Path $static) { Remove-Item -Recurse -Force $static }
    Copy-Item -Recurse -Force (Join-Path $pkg "static") $static

    $createdConfig = $false
    if (-not (Test-Path $Config)) {
        Copy-Item (Join-Path $pkg "config.example.yaml") $Config
        $createdConfig = $true
    }

    $binPath = ('"{0}" run --binary "{1}" --config "{2}" --working-dir "{3}"' -f $Wrapper, $Binary, $Config, $StateDir)
    New-Service -Name $ServiceName -BinaryPathName $binPath -DisplayName "netdisk115rs" -Description "netdisk115rs backend" -StartupType Automatic | Out-Null
    sc.exe failure $ServiceName reset= 3600 actions= restart/5000/restart/5000/restart/10000 | Out-Null
    sc.exe failureflag $ServiceName 1 | Out-Null

    if (-not $NoStart) {
        Start-Service -Name $ServiceName
        $svc = Get-Service -Name $ServiceName
        $svc.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromSeconds(30))
        if ($createdConfig) {
            $healthy = $false
            for ($i = 0; $i -lt 30; $i++) {
                try {
                    $response = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:8080/" -TimeoutSec 2
                    if ($response.StatusCode -eq 200) { $healthy = $true; break }
                } catch {}
                Start-Sleep -Seconds 1
            }
            if (-not $healthy) {
                Get-Content (Join-Path $StateDir "logs\netdisk115rs.error.log") -Tail 80 -ErrorAction SilentlyContinue
                throw "Service did not become healthy on http://127.0.0.1:8080/"
            }
        }
    }

    Write-Host "netdisk115rs installed as Windows Service '$ServiceName'."
    Write-Host "Program: $InstallDir"
    Write-Host "Config/state: $StateDir"
} finally {
    Remove-Item -Recurse -Force $temp -ErrorAction SilentlyContinue
}
