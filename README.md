# netdisk115rs

`netdisk115rs` 是一个面向 115 网盘的本地服务与命令行工具，提供 Web 管理界面、文件操作、媒体库、离线任务、分享、只读直链 WebDAV 等能力。

本仓库用于分发安装脚本、服务组件和预编译 Release。`netdisk115rs` 核心程序以闭源二进制形式发布。

- 最新版本：<https://github.com/canxin121/netdisk115rs-release/releases/latest>
- 默认 Web 地址：`http://127.0.0.1:8080`
- 支持原生系统服务和开机自启动
- 新的 macOS Release 同时包含 `/Applications/Netdisk115.app`（Finder File Provider 挂载 App）
- 支持自动升级式安装：再次运行安装脚本即可更新程序
- Release 下载会自动校验 SHA-256

## 支持平台

| 系统 | 架构 | Release 文件 | 服务方式 |
| --- | --- | --- | --- |
| Linux | x86_64 | `netdisk115rs-linux-x86_64.tar.gz` | systemd |
| Linux | arm64 | `netdisk115rs-linux-arm64.tar.gz` | systemd |
| macOS | Intel x86_64 | `netdisk115rs-macos-x86_64.tar.gz` | LaunchDaemon + File Provider App |
| macOS | Apple Silicon arm64 | `netdisk115rs-macos-arm64.tar.gz` | LaunchDaemon + File Provider App |
| Windows | x86_64 | `netdisk115rs-windows-x86_64.zip` | Windows Service |
| Windows | arm64 | `netdisk115rs-windows-arm64.zip` | Windows Service |

Linux 安装方式要求系统使用 `systemd`。macOS 和 Linux 安装器会在需要时调用 `sudo`；建议以普通登录用户执行安装命令，不要使用 `sudo bash` 直接运行整个安装脚本。默认情况下，后台服务会以执行安装器的用户身份运行。Windows 安装器需要管理员 PowerShell。

## 快速安装

### macOS

在终端执行：

```bash
curl -fsSL https://raw.githubusercontent.com/canxin121/netdisk115rs-release/main/install.sh | bash
```

安装器会自动识别 Intel 或 Apple Silicon，下载对应 Release，校验 SHA-256。新格式 Release 会安装 LaunchDaemon 与 `/Applications/Netdisk115.app` 并启动后端服务；旧格式（例如现有 `v0.1.0`）没有 App 时会兼容为仅安装后端。正式新 Release 中的 App 使用 Apple Developer ID 签名并经过 notarization。

安装完成后打开：

```text
http://127.0.0.1:8080
```

### Linux

在终端执行：

```bash
curl -fsSL https://raw.githubusercontent.com/canxin121/netdisk115rs-release/main/install.sh | bash
```

安装器会自动识别 x86_64 或 arm64，下载对应 Release，校验 SHA-256，注册 `systemd` 服务并设置开机自启动。

安装完成后打开：

```text
http://127.0.0.1:8080
```

### Windows

打开**管理员 PowerShell**，执行：

```powershell
irm https://raw.githubusercontent.com/canxin121/netdisk115rs-release/main/install.ps1 | iex
```

安装器会自动识别 x64 或 ARM64，下载对应 Release，校验 SHA-256，注册 `netdisk115rs` Windows Service，并设置为 `Automatic` 自动启动。

安装完成后打开：

```text
http://127.0.0.1:8080
```

## 安装位置

| 内容 | macOS | Linux | Windows |
| --- | --- | --- | --- |
| 主程序 | `/usr/local/bin/netdisk115rs` | `/usr/local/bin/netdisk115rs` | `%ProgramFiles%\netdisk115rs\netdisk115rs.exe` |
| Finder 挂载 App | `/Applications/Netdisk115.app` | — | — |
| 配置文件 | `/Library/Application Support/netdisk115rs/config.yaml` | `/var/lib/netdisk115rs/config.yaml` | `%ProgramData%\netdisk115rs\config.yaml` |
| 数据目录 | `/Library/Application Support/netdisk115rs/data` | `/var/lib/netdisk115rs/data` | `%ProgramData%\netdisk115rs\data` |
| Web 静态资源 | `/Library/Application Support/netdisk115rs/static` | `/var/lib/netdisk115rs/static` | `%ProgramData%\netdisk115rs\static` |
| 服务配置 | `/Library/LaunchDaemons/com.canxin.netdisk115rs.plist` | `/etc/systemd/system/netdisk115rs.service` | Windows SCM |

首次安装会从 Release 中的 `config.example.yaml` 自动创建 `config.yaml`。后续升级不会覆盖已有的 `config.yaml`、账号登录态和 `data/`。

## 首次使用

### 1. 确认服务正在运行

macOS：

```bash
sudo launchctl print system/com.canxin.netdisk115rs
```

Linux：

```bash
sudo systemctl status netdisk115rs
```

Windows：

```powershell
Get-Service netdisk115rs
```

服务正常后，浏览器访问：

```text
http://127.0.0.1:8080
```

默认只监听本机回环地址，不会直接暴露到局域网或公网。

### 2. 登录 115 账号

配置中的账号会话和媒体库路径默认使用相对路径，因此使用 CLI 时应先进入服务的数据目录，确保命令行和后台服务使用同一套 `data/`。

#### macOS

```bash
cd "/Library/Application Support/netdisk115rs"
netdisk115rs --config config.yaml login password 你的115账号
```

不传 `--password` 时会读取 `NETDISK_PASSWORD`，没有设置时会进入交互输入，避免把密码直接写到命令历史中。

查看登录状态：

```bash
netdisk115rs --config config.yaml login status
```

#### Linux

```bash
cd /var/lib/netdisk115rs
netdisk115rs --config config.yaml login password 你的115账号
```

查看登录状态：

```bash
netdisk115rs --config config.yaml login status
```

#### Windows

```powershell
Set-Location "$env:ProgramData\netdisk115rs"
& "$env:ProgramFiles\netdisk115rs\netdisk115rs.exe" --config .\config.yaml login password 你的115账号
```

查看登录状态：

```powershell
& "$env:ProgramFiles\netdisk115rs\netdisk115rs.exe" --config .\config.yaml login status
```

登录完成后建议重启后台服务，让正在运行的服务重新加载账号状态。

### 短信验证码登录

先发送验证码：

```bash
netdisk115rs --config config.yaml login sms-code 你的手机号
```

非默认地区号码可以按 CLI 提示使用 `--country` 指定国家或地区码。

收到验证码后：

```bash
netdisk115rs --config config.yaml login sms 你的手机号 验证码
```

Windows 使用相同子命令，只需将可执行文件替换为：

```powershell
& "$env:ProgramFiles\netdisk115rs\netdisk115rs.exe"
```

## Web 访问控制

默认配置的 Web 访问控制为关闭状态。如果服务只监听 `127.0.0.1`，可以按本机应用使用；如果计划开放到局域网、反向代理或公网，建议先创建 Web 管理员并开启访问控制。

### macOS / Linux

先进入对应的数据目录，然后执行：

```bash
printf "Web admin password: " >&2
stty -echo
IFS= read -r WEB_PASSWORD
stty echo
printf '\n' >&2
printf '%s' "$WEB_PASSWORD" | netdisk115rs --config config.yaml access init --username admin --password-stdin
unset WEB_PASSWORD
```

密码至少需要 10 个字符。`--password-stdin` 可以避免把密码作为命令行参数写入 shell 历史。

查看 Web 用户：

```bash
netdisk115rs --config config.yaml access list
```

### Windows

```powershell
Set-Location "$env:ProgramData\netdisk115rs"
$secure = Read-Host "Web admin password" -AsSecureString
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
    $env:NETDISK_WEB_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    & "$env:ProgramFiles\netdisk115rs\netdisk115rs.exe" --config .\config.yaml access init --username admin
} finally {
    Remove-Item Env:NETDISK_WEB_PASSWORD -ErrorAction SilentlyContinue
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
}
```

修改访问控制后重启服务。

## 局域网访问

默认配置：

```yaml
server:
  listen: "127.0.0.1:8080"
```

如果需要允许局域网设备访问，可修改为：

```yaml
server:
  listen: "0.0.0.0:8080"
```

修改后重启服务，并确认操作系统防火墙允许对应端口。

如果服务需要暴露到公网，建议同时满足以下条件：

- 已开启 Web 访问控制；
- 使用反向代理提供 HTTPS；
- 不直接把未加密的 HTTP 管理端口暴露到互联网；
- 根据实际使用环境配置防火墙和访问来源限制。

## 服务管理

### macOS

查看状态：

```bash
sudo launchctl print system/com.canxin.netdisk115rs
```

重启：

```bash
sudo launchctl kickstart -k system/com.canxin.netdisk115rs
```

卸载当前 LaunchDaemon：

```bash
sudo launchctl bootout system /Library/LaunchDaemons/com.canxin.netdisk115rs.plist
```

重新加载：

```bash
sudo launchctl bootstrap system /Library/LaunchDaemons/com.canxin.netdisk115rs.plist
```

日志：

```bash
tail -f "/Library/Application Support/netdisk115rs/logs/netdisk115rs.log"
tail -f "/Library/Application Support/netdisk115rs/logs/netdisk115rs.error.log"
```

### Linux

查看状态：

```bash
sudo systemctl status netdisk115rs
```

启动：

```bash
sudo systemctl start netdisk115rs
```

停止：

```bash
sudo systemctl stop netdisk115rs
```

重启：

```bash
sudo systemctl restart netdisk115rs
```

确认开机自启动：

```bash
sudo systemctl is-enabled netdisk115rs
```

查看日志：

```bash
sudo journalctl -u netdisk115rs -f
```

最近 100 行日志：

```bash
sudo journalctl -u netdisk115rs -n 100 --no-pager
```

### Windows

查看状态：

```powershell
Get-Service netdisk115rs
```

启动：

```powershell
Start-Service netdisk115rs
```

停止：

```powershell
Stop-Service netdisk115rs
```

重启：

```powershell
Restart-Service netdisk115rs
```

查看服务启动类型：

```powershell
Get-CimInstance Win32_Service -Filter "Name='netdisk115rs'" | Select-Object Name, State, StartMode
```

日志目录：

```text
%ProgramData%\netdisk115rs\logs
```

PowerShell 查看错误日志：

```powershell
Get-Content "$env:ProgramData\netdisk115rs\logs\netdisk115rs.error.log" -Tail 100 -Wait
```

## 重启服务

修改配置、通过 CLI 新增账号或调整 Web 访问控制后，建议重启服务。

macOS：

```bash
sudo launchctl kickstart -k system/com.canxin.netdisk115rs
```

Linux：

```bash
sudo systemctl restart netdisk115rs
```

Windows：

```powershell
Restart-Service netdisk115rs
```

## 升级

再次执行对应平台的一键安装命令即可升级到最新 Release。

升级时安装器会停止旧服务、替换程序和 Web 静态资源，然后重新启动服务。macOS 还会先退出旧的 Host App / File Provider 进程，完整替换 App bundle，并在新 bundle 的嵌套代码签名验证通过后才删除旧副本；历史 `~/Applications/Netdisk115.app` 开发安装会迁移到 `/Applications`。已有配置和数据会保留。

建议重要部署在升级前自行备份配置和数据目录。

### macOS / Linux 升级到最新版本

```bash
curl -fsSL https://raw.githubusercontent.com/canxin121/netdisk115rs-release/main/install.sh | bash
```

### Windows 升级到最新版本

管理员 PowerShell：

```powershell
irm https://raw.githubusercontent.com/canxin121/netdisk115rs-release/main/install.ps1 | iex
```

## 安装指定版本

### macOS / Linux

例如安装 `v0.1.0`：

```bash
curl -fsSL https://raw.githubusercontent.com/canxin121/netdisk115rs-release/main/install.sh | bash -s -- --version v0.1.0
```

### Windows

需要传递参数时，建议先保存安装脚本：

```powershell
$script = "$env:TEMP\install-netdisk115rs.ps1"
irm https://raw.githubusercontent.com/canxin121/netdisk115rs-release/main/install.ps1 -OutFile $script
& $script -Version v0.1.0
```

## 安装但暂不启动

macOS / Linux：

```bash
curl -fsSL https://raw.githubusercontent.com/canxin121/netdisk115rs-release/main/install.sh | bash -s -- --no-start
```

Windows：

```powershell
$script = "$env:TEMP\install-netdisk115rs.ps1"
irm https://raw.githubusercontent.com/canxin121/netdisk115rs-release/main/install.ps1 -OutFile $script
& $script -NoStart
```

## 手动下载和离线安装

所有正式版本都可以在 Releases 页面下载：

<https://github.com/canxin121/netdisk115rs-release/releases>

### macOS / Linux

下载与你的系统和架构对应的 `.tar.gz`，同时下载 `install.sh`，然后执行：

```bash
chmod +x install.sh
./install.sh --archive ./netdisk115rs-macos-arm64.tar.gz
```

Linux x86_64 示例：

```bash
./install.sh --archive ./netdisk115rs-linux-x86_64.tar.gz
```

### Windows

下载对应的 `.zip` 和 `install.ps1`，管理员 PowerShell 执行：

```powershell
.\install.ps1 -ArchivePath .\netdisk115rs-windows-x86_64.zip
```

ARM64：

```powershell
.\install.ps1 -ArchivePath .\netdisk115rs-windows-arm64.zip
```

本地 `--archive` / `-ArchivePath` 模式用于安装已经下载好的包，不会再次从 GitHub 下载 Release。

## 手动校验 SHA-256

每个 Release 都包含 `SHA256SUMS`。

### macOS

```bash
grep '  netdisk115rs-macos-arm64.tar.gz$' SHA256SUMS | shasum -a 256 -c -
```

Intel Mac 将文件名替换为 `netdisk115rs-macos-x86_64.tar.gz`。

### Linux

```bash
grep '  netdisk115rs-linux-x86_64.tar.gz$' SHA256SUMS | sha256sum -c -
```

ARM64 将文件名替换为 `netdisk115rs-linux-arm64.tar.gz`。

### Windows

```powershell
Get-FileHash .\netdisk115rs-windows-x86_64.zip -Algorithm SHA256
```

将输出的 Hash 与 `SHA256SUMS` 中对应文件的值比较。ARM64 使用 `netdisk115rs-windows-arm64.zip`。

通过在线安装脚本安装时，这一步由安装器自动完成。

## 卸载

### macOS / Linux

默认卸载服务、主程序以及 macOS 的 `/Applications/Netdisk115.app`，保留配置、账号状态和 App 数据，便于重新安装：

```bash
curl -fsSL https://raw.githubusercontent.com/canxin121/netdisk115rs-release/main/uninstall.sh | bash
```

彻底删除服务、程序、配置和数据；macOS 同时清理 Host App / File Provider sandbox container 与 App Group 数据：

```bash
curl -fsSL https://raw.githubusercontent.com/canxin121/netdisk115rs-release/main/uninstall.sh | bash -s -- --purge
```

### Windows

管理员 PowerShell：

```powershell
$script = "$env:TEMP\uninstall-netdisk115rs.ps1"
irm https://raw.githubusercontent.com/canxin121/netdisk115rs-release/main/uninstall.ps1 -OutFile $script
& $script
```

默认保留 `%ProgramData%\netdisk115rs` 中的配置和数据。

彻底删除：

```powershell
& $script -Purge
```

## macOS Release 签名与公证

GitHub Actions 的普通 CI 会用 ad-hoc 签名构建 `Netdisk115.app`，用于验证 Xcode 构建、打包、安装、重复安装升级和卸载流程。ad-hoc 包不会作为正式 macOS Release 发布。

正式 `Release` workflow 对两个 macOS 架构强制执行以下步骤：

1. 从 private `canxin121/netdisk115rs` 的 `macos/signing/DeveloperIDApplication.p12` 导入 Apple 签发的 **Developer ID Application** 证书；
2. 对 File Provider extension 和 Host App 分别签名，启用 Hardened Runtime，并验证 Team ID / entitlements；
3. 使用 `xcrun notarytool` 提交 Apple notarization；
4. `stapler` 附加并验证公证票据，`spctl` 通过后才打进 `.tar.gz`；
5. 安装器 smoke test 再验证签名、公证、服务启动和重复安装升级。

Release 仓库需要配置 `APPLE_TEAM_ID`、`MACOS_DEVELOPER_ID_P12_PASSWORD`、`APPLE_API_KEY_ID`、`APPLE_API_ISSUER_ID`、`APPLE_API_KEY_P8` secrets。缺少任意正式签名材料时，macOS Release job 会失败而不是发布一个 Gatekeeper 会拒绝的 App。
当前 App Group 使用 `<APPLE_TEAM_ID>.com.netdisk115.fileprovider` 的 macOS Team-ID 前缀形式，因此 Developer ID 直分发不额外依赖 provisioning profile；如果以后改成 `group.*` App Group，则需要同步引入 Apple provisioning profile。

## CLI 使用

安装后可以直接查看所有命令：

```bash
netdisk115rs --help
```

常用示例需要在服务数据目录下执行，以便使用同一套相对数据路径。

查看账号信息：

```bash
netdisk115rs --config config.yaml info
```

查看空间配额：

```bash
netdisk115rs --config config.yaml quota
```

以文件系统方式列出根目录：

```bash
netdisk115rs --config config.yaml fs ls /
```

搜索：

```bash
netdisk115rs --config config.yaml search 关键词
```

查看 WebDAV 管理命令：

```bash
netdisk115rs --config config.yaml webdav --help
```

Windows 使用 `%ProgramFiles%\netdisk115rs\netdisk115rs.exe` 执行相同子命令。

## WebDAV

程序支持多个只读直链 WebDAV mount，每个 mount 可以独立指定：

- 115 账号；
- 115 根目录；
- WebDAV URL 前缀；
- Basic Auth 用户名和密码。

查看管理命令：

```bash
netdisk115rs --config config.yaml webdav --help
```

配置完成后可以使用：

```bash
netdisk115rs --config config.yaml webdav validate
netdisk115rs --config config.yaml webdav apply
```

详细字段可参考安装目录中的 `config.yaml` 以及 Release 内的 `config.example.yaml`。

## 配置和数据备份

升级默认不会删除用户数据，但重要部署仍建议定期备份整个状态目录。

macOS：

```text
/Library/Application Support/netdisk115rs
```

Linux：

```text
/var/lib/netdisk115rs
```

Windows：

```text
%ProgramData%\netdisk115rs
```

其中通常包括：

- `config.yaml`：服务配置；
- `data/accounts/`：账号会话；
- `data/library.sqlite`：媒体库和本地索引；
- 其他运行状态文件。

不要公开分享包含账号会话、密码或访问 token 的配置和数据文件。

## 常见问题

### 浏览器无法访问 `127.0.0.1:8080`

先检查服务状态和日志：

- macOS：`sudo launchctl print system/com.canxin.netdisk115rs`
- Linux：`sudo systemctl status netdisk115rs`
- Windows：`Get-Service netdisk115rs`

如果服务启动失败，再查看对应平台的日志。

### 端口 8080 已被占用

修改 `config.yaml`：

```yaml
server:
  listen: "127.0.0.1:18080"
```

然后重启服务，并访问新的端口。

### CLI 登录成功，但 Web 服务里还看不到账号

CLI 和服务使用的是独立进程。确认 CLI 是在服务状态目录中运行的，然后重启后台服务。

### 修改 `config.yaml` 后没有生效

大部分启动级配置需要重启服务后生效。

### 升级会不会覆盖配置和数据

不会。安装器会替换程序和 Web 静态资源，但保留已有 `config.yaml` 和状态目录中的用户数据。

### 如何查看当前版本

macOS / Linux：

```bash
netdisk115rs --version
```

Windows：

```powershell
& "$env:ProgramFiles\netdisk115rs\netdisk115rs.exe" --version
```

## Release 安全与完整性

- 在线安装会下载并验证 Release 中的 `SHA256SUMS`；
- 每个平台使用对应架构的原生二进制；
- 发布流程会在 Linux x86_64、Linux arm64、macOS Intel、macOS Apple Silicon、Windows x86_64、Windows arm64 上实际完成安装和系统服务启动测试后再发布；
- Release 仓库不分发 `netdisk115rs` 核心源码；
- Release 包中只包含运行所需的二进制、Web 静态资源、示例配置和构建标识等文件。

## 源码与许可说明

`netdisk115rs` 核心程序为闭源分发。本仓库公开的是安装脚本、发布自动化、服务组件和文档，不代表核心程序源码已开放授权。

第三方组件继续适用各自的许可条款。更多说明见 [NOTICE.md](NOTICE.md)。
