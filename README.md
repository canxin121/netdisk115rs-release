# netdisk115rs Releases

`netdisk115rs` 的公开发布仓库。这里仅保存安装器、服务宿主、GitHub Actions、文档和 GitHub Release 二进制；应用源码仍位于私有仓库 `canxin121/netdisk115rs`，不会提交或上传到本仓库。

## 一键安装

### macOS

Apple Silicon 与 Intel 都有原生包。安装器需要 `sudo`，会安装系统级 LaunchDaemon，开机自动启动，不要求用户先登录：

```bash
curl -fsSL https://raw.githubusercontent.com/canxin121/netdisk115rs-release/main/install.sh | bash
```

默认位置：

- 程序：`/usr/local/bin/netdisk115rs`
- 配置/状态：`/Library/Application Support/netdisk115rs`
- 服务：`/Library/LaunchDaemons/com.canxin.netdisk115rs.plist`

```bash
sudo launchctl print system/com.canxin.netdisk115rs
sudo launchctl kickstart -k system/com.canxin.netdisk115rs
```

### Linux

x86_64 与 arm64 都有原生包：

```bash
curl -fsSL https://raw.githubusercontent.com/canxin121/netdisk115rs-release/main/install.sh | bash
```

默认位置：

- 程序：`/usr/local/bin/netdisk115rs`
- 配置/状态：`/var/lib/netdisk115rs`
- 服务：`/etc/systemd/system/netdisk115rs.service`

安装器执行 `systemctl enable`，服务以执行安装器的用户身份运行，随系统启动并在异常退出后自动重启。

```bash
sudo systemctl status netdisk115rs
sudo systemctl restart netdisk115rs
journalctl -u netdisk115rs -f
```

### Windows

x86_64 与 arm64 都有原生包。在**管理员 PowerShell** 中执行：

```powershell
irm https://raw.githubusercontent.com/canxin121/netdisk115rs-release/main/install.ps1 | iex
```

默认位置：

- 程序：`%ProgramFiles%\netdisk115rs`
- 配置/状态：`%ProgramData%\netdisk115rs`
- 服务名：`netdisk115rs`

Windows 包内带本仓库源码构建的 `netdisk115rs-service.exe`，通过 Windows SCM 注册为真正的 `Automatic` Service；它负责启动闭源后端、转发 Stop/Shutdown，并配合 SCM failure actions 在异常退出后重启。

```powershell
Get-Service netdisk115rs
Restart-Service netdisk115rs
```

## 首次运行

默认监听：

```text
http://127.0.0.1:8080
```

配置文件：

| 平台 | 路径 |
| --- | --- |
| macOS | `/Library/Application Support/netdisk115rs/config.yaml` |
| Linux | `/var/lib/netdisk115rs/config.yaml` |
| Windows | `%ProgramData%\netdisk115rs\config.yaml` |

首次安装会从发布包里的 `config.example.yaml` 创建 `config.yaml`；后续升级只替换程序和 `static/`，不覆盖已有配置、账号 session 和 `data/`。

## 升级与指定版本

重新运行一键安装命令即可升级到 latest。macOS/Linux 可固定版本：

```bash
curl -fsSL https://raw.githubusercontent.com/canxin121/netdisk115rs-release/main/install.sh | bash -s -- --version v0.1.0
```

Windows 安装脚本支持 `-Version v0.1.0`；需要参数时建议先保存脚本再执行：

```powershell
irm https://raw.githubusercontent.com/canxin121/netdisk115rs-release/main/install.ps1 -OutFile $env:TEMP\install-netdisk115rs.ps1
& $env:TEMP\install-netdisk115rs.ps1 -Version v0.1.0
```

## 卸载

默认保留配置与数据：

```bash
curl -fsSL https://raw.githubusercontent.com/canxin121/netdisk115rs-release/main/uninstall.sh | bash
```

彻底删除状态：

```bash
curl -fsSL https://raw.githubusercontent.com/canxin121/netdisk115rs-release/main/uninstall.sh | bash -s -- --purge
```

Windows（管理员 PowerShell）：

```powershell
irm https://raw.githubusercontent.com/canxin121/netdisk115rs-release/main/uninstall.ps1 -OutFile $env:TEMP\uninstall-netdisk115rs.ps1
& $env:TEMP\uninstall-netdisk115rs.ps1
# 或彻底删除：
& $env:TEMP\uninstall-netdisk115rs.ps1 -Purge
```

## 闭源构建模型

发布仓库的 Actions 通过 Secret `SOURCE_REPO_SSH_KEY` 使用**只读 Deploy Key** checkout 私有源码：

```text
canxin121/netdisk115rs-release  (public)
        |
        | SOURCE_REPO_SSH_KEY (read-only deploy key)
        v
canxin121/netdisk115rs          (private)
        |
        +--> bun install --frozen-lockfile
        +--> bun run build -> static/
        +--> cargo build --release --locked
        +--> package + native service test
        v
GitHub Release binaries only
```

Actions 不会 `upload-artifact` 私有源码目录；Release 中只有二进制、Web 静态资源、示例配置和源码 commit 标识。Deploy Key 仅能读取 `canxin121/netdisk115rs`，不使用个人 PAT 作为跨仓库构建凭据。

## CI：真实安装与服务测试

`.github/workflows/ci.yml` 对六个 GitHub hosted runner 做 native build + native install/service smoke test：

| 平台 | Runner | Release asset |
| --- | --- | --- |
| Linux x86_64 | `ubuntu-24.04` | `netdisk115rs-linux-x86_64.tar.gz` |
| Linux arm64 | `ubuntu-24.04-arm` | `netdisk115rs-linux-arm64.tar.gz` |
| macOS Intel | `macos-15-intel` | `netdisk115rs-macos-x86_64.tar.gz` |
| macOS Apple Silicon | `macos-15` | `netdisk115rs-macos-arm64.tar.gz` |
| Windows x86_64 | `windows-2025` | `netdisk115rs-windows-x86_64.zip` |
| Windows arm64 | `windows-11-arm` | `netdisk115rs-windows-arm64.zip` |

每个 job 都会：

1. 用只读 Deploy Key 拉取私有源码；
2. 构建 Web 与 Rust 后端；Windows 额外构建 `service/windows-wrapper`；
3. 生成与 Release 相同格式的本地安装包；
4. 调用公开安装器；
5. 验证 `systemd` / `launchd` / Windows SCM 的自启动状态与 Running 状态；
6. 请求 `http://127.0.0.1:8080/` 做 HTTP 探活；
7. 清理测试服务。

## 创建 Release

GitHub Actions → **Release** → Run workflow：

- `tag`：例如 `v0.1.0`；
- `source_ref`：私有仓库 branch/tag/commit，默认 `main`；
- `prerelease`：是否预发布。

工作流要求 `Cargo.toml` 中的版本与 tag 一致，然后在六个平台逐个完成 native 安装/服务测试；全部通过后才发布六个资产与 `SHA256SUMS`。

远程一键安装会校验 Release 中的 SHA-256 后再安装。本仓库不保存 `config.yaml`、Cookie、账号 session、私有源码或 Deploy Key。

> `netdisk115rs` 应用本身为闭源分发；见 [NOTICE.md](NOTICE.md)。
