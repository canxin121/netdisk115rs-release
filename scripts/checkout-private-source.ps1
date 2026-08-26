[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Repository,

    [Parameter(Mandatory = $true)]
    [string]$Ref,

    [Parameter(Mandatory = $true)]
    [string]$Destination
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

if (-not $env:SOURCE_REPO_SSH_KEY) {
    throw "SOURCE_REPO_SSH_KEY is not set"
}
if (-not $env:RUNNER_TEMP) {
    throw "RUNNER_TEMP is not set"
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$keyPath = Join-Path $env:RUNNER_TEMP ("netdisk115rs-source-" + [Guid]::NewGuid().ToString("N"))
$knownHostsPath = "$keyPath.known_hosts"
$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

try {
    # actions/checkout's SSH-key ACL handling currently leaves an
    # Authenticated Users ACE on the Windows 11 ARM hosted image. Windows
    # OpenSSH rejects such a key as "UNPROTECTED PRIVATE KEY FILE". Create a
    # key file whose DACL contains only the current runner account instead.
    [System.IO.File]::WriteAllText(
        $keyPath,
        $env:SOURCE_REPO_SSH_KEY.Trim() + "`n",
        $utf8NoBom
    )
    $acl = Get-Acl -LiteralPath $keyPath
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($rule in @($acl.Access)) {
        [void]$acl.RemoveAccessRuleAll($rule)
    }
    $runnerRule = [System.Security.AccessControl.FileSystemAccessRule]::new(
        $identity,
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        [System.Security.AccessControl.AccessControlType]::Allow
    )
    [void]$acl.AddAccessRule($runnerRule)
    Set-Acl -LiteralPath $keyPath -AclObject $acl

    # Build known_hosts from GitHub's HTTPS Meta API rather than
    # trusting an unauthenticated ssh-keyscan result.
    $meta = Invoke-RestMethod -Headers @{ "User-Agent" = "netdisk115rs-release" } -Uri "https://api.github.com/meta"
    $knownHosts = @($meta.ssh_keys | ForEach-Object { "github.com $_" })
    if ($knownHosts.Count -eq 0) {
        throw "GitHub Meta API returned no SSH host keys"
    }
    [System.IO.File]::WriteAllLines($knownHostsPath, $knownHosts, $utf8NoBom)

    $ssh = Join-Path $env:SystemRoot "System32\OpenSSH\ssh.exe"
    if (-not (Test-Path -LiteralPath $ssh)) {
        throw "Windows OpenSSH client not found at $ssh"
    }
    $env:GIT_SSH_COMMAND = "$ssh -i $keyPath -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o CheckHostIP=no -o UserKnownHostsFile=$knownHostsPath"

    $destinationPath = [System.IO.Path]::GetFullPath($Destination)
    if (Test-Path -LiteralPath $destinationPath) {
        Remove-Item -LiteralPath $destinationPath -Recurse -Force
    }
    New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null
    git -C $destinationPath init
    if ($LASTEXITCODE -ne 0) { throw "git init failed" }
    git -C $destinationPath remote add origin "git@github.com:$Repository.git"
    if ($LASTEXITCODE -ne 0) { throw "git remote add failed" }
    git -C $destinationPath fetch --depth=1 origin $Ref
    if ($LASTEXITCODE -ne 0) { throw "git fetch failed for $Repository@$Ref" }
    git -C $destinationPath checkout --detach FETCH_HEAD
    if ($LASTEXITCODE -ne 0) { throw "git checkout failed" }

    Write-Host "Checked out $Repository@$((git -C $destinationPath rev-parse HEAD).Trim())"
}
finally {
    Remove-Item Env:GIT_SSH_COMMAND -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $keyPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $knownHostsPath -Force -ErrorAction SilentlyContinue
}
