param(
    [string]$Version = "1.4.0"
)

$ErrorActionPreference = "Stop"
if (-not $env:RUNNER_TEMP) { throw "RUNNER_TEMP is required" }
if (-not $env:GITHUB_PATH) { throw "GITHUB_PATH is required" }

$root = Join-Path $env:RUNNER_TEMP "bun-windows-arm64"
$archive = Join-Path $env:RUNNER_TEMP "bun-windows-aarch64.zip"
Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $root -Force | Out-Null

$url = "https://github.com/oven-sh/bun/releases/download/bun-v$Version/bun-windows-aarch64.zip"
& curl.exe -fL --retry 3 --retry-delay 1 $url -o $archive
if ($LASTEXITCODE -ne 0) { throw "curl.exe failed with exit code $LASTEXITCODE" }

# Use Windows' native bsdtar instead of PowerShell's managed ZipFile/Expand-Archive path.
# The latter currently crashes the GitHub Windows ARM64 runner CLR during setup-bun.
& tar.exe -xf $archive -C $root
if ($LASTEXITCODE -ne 0) { throw "tar.exe failed with exit code $LASTEXITCODE" }

$binDir = Join-Path $root "bun-windows-aarch64"
$bun = Join-Path $binDir "bun.exe"
if (-not (Test-Path -LiteralPath $bun)) { throw "bun.exe was not extracted to $bun" }
Add-Content -LiteralPath $env:GITHUB_PATH -Value $binDir
& $bun --version
if ($LASTEXITCODE -ne 0) { throw "bun.exe failed with exit code $LASTEXITCODE" }
