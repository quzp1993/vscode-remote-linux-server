# VS Code 远程连接 CentOS 7 / Linux 服务器

这份仓库记录从 Windows 使用 VS Code Remote SSH 连接 Linux 服务器的方法，并包含免密 SSH 配置脚本。普通 Linux 服务器通常可以直接用 VS Code Remote SSH；如果服务器是 CentOS 7 / RHEL 7，因为系统 glibc 版本较旧，需要先安装兼容版 VS Code Server。

CentOS 7 兼容版 VS Code Server 参考项目：[MikeWang000000/vscode-server-centos7](https://github.com/MikeWang000000/vscode-server-centos7)。

## 适用场景

- Windows 客户端连接 Linux 服务器
- VS Code Remote SSH 连接 CentOS 7 / RHEL 7
- 给 `user@host` 配置 SSH 公钥免密登录
- 排查 `authorized_keys` 已写入但公钥登录仍失败的问题
- 处理 NFS home 目录与 SELinux 导致的 SSH 公钥认证失败

## Windows 客户端准备

安装这些工具：

- [VS Code](https://code.visualstudio.com/)
- VS Code 扩展：Remote - SSH
- Windows OpenSSH 客户端，命令行可运行 `ssh` 和 `scp`
- Git
- PowerShell 5 或更高版本

检查本机 VS Code 版本：

```powershell
code --version
```

第一行是版本号，例如：

```text
1.132.0
```

## 配置 SSH Host

编辑 Windows 用户目录下的 SSH 配置：

```powershell
notepad $env:USERPROFILE\.ssh\config
```

加入服务器配置：

```sshconfig
Host centos7-node
    HostName 172.16.100.7
    User licun
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
```

也可以为第二台服务器加一个别名：

```sshconfig
Host centos7-node-121
    HostName 172.16.100.121
    User licun
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
```

测试 SSH 密码登录：

```powershell
ssh centos7-node
```

首次连接会提示确认服务器指纹，确认是目标服务器后输入 `yes`。

## 配置 SSH 免密登录

如果本机还没有 SSH key，先生成一个：

```powershell
ssh-keygen -t ed25519 -f "$env:USERPROFILE\.ssh\id_ed25519" -N ""
```

把公钥安装到服务器：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\setup-passwordless-ssh.ps1 -Hosts licun@172.16.100.7,licun@172.16.100.121
```

脚本会要求输入每台服务器的 SSH 密码。成功后会在服务器上写入：

```text
~/.ssh/authorized_keys
```

并设置权限：

```text
~               不允许 group/other 写入
~/.ssh          700
~/.ssh/authorized_keys 600
```

验证免密登录：

```powershell
ssh -o BatchMode=yes licun@172.16.100.7 "echo key_ok"
ssh -o BatchMode=yes licun@172.16.100.121 "echo key_ok"
```

如果输出 `key_ok`，说明免密 SSH 已经成功。

## CentOS 7 安装兼容版 VS Code Server

CentOS 7 / RHEL 7 不能稳定运行新版 VS Code 官方 server，需要使用兼容补丁版。

1. 打开 [vscode-server-centos7 Releases](https://github.com/MikeWang000000/vscode-server-centos7/releases)。
2. 下载与本机 VS Code 版本匹配的压缩包，例如：

```text
vscode-server_1.132.0_x64.tar.gz
```

3. 把压缩包放到本仓库根目录，或在运行脚本时传入完整路径。

安装到服务器：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install-vscode-server-centos7.ps1 `
  -SshTarget licun@172.16.100.7 `
  -Package .\vscode-server_1.132.0_x64.tar.gz
```

成功时会看到：

```text
__VSCODE_SERVER_CENTOS7_READY__
```

之后在 VS Code 中执行：

```text
Remote-SSH: Connect to Host...
```

选择 `centos7-node` 即可连接。

## 公钥写入后仍然失败的排查

如果 `authorized_keys` 中已经有公钥，但仍然看到：

```text
Permission denied (publickey,password).
```

运行诊断脚本：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\diagnose-passwordless-ssh.ps1 -SshTarget licun@172.16.100.121
```

重点看这些项：

- `~/.ssh` 是否是 `700`
- `~/.ssh/authorized_keys` 是否是 `600`
- `authorized_keys` 是否包含本机公钥
- SELinux 标签是否是 `nfs_t`

如果 home 目录、`.ssh`、`authorized_keys` 都显示 `nfs_t`，例如：

```text
system_u:object_r:nfs_t:s0 /home/licun
system_u:object_r:nfs_t:s0 /home/licun/.ssh
system_u:object_r:nfs_t:s0 /home/licun/.ssh/authorized_keys
```

这通常表示用户 home 目录在 NFS 上。CentOS/RHEL 的 SELinux 默认可能阻止 `sshd` 读取 NFS home 里的 `authorized_keys`，需要管理员在服务器上执行：

```bash
sudo setsebool -P use_nfs_home_dirs 1
```

如果当前用户没有 sudo 权限，会看到类似：

```text
Sorry, user licun may not run sudo on slurm-node1.
```

这时必须联系服务器管理员执行上面的命令。管理员执行完成后，再验证：

```powershell
ssh -o BatchMode=yes licun@172.16.100.121 "echo key_ok"
```

## RSA 兼容方案

老服务器可能不接受 `ed25519`。可以额外生成 RSA key：

```powershell
ssh-keygen -t rsa -b 4096 -f "$env:USERPROFILE\.ssh\id_rsa_vscode_centos7" -N ""
```

安装 RSA 公钥：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\setup-passwordless-ssh.ps1 `
  -Hosts licun@172.16.100.121 `
  -PublicKeyPath "$env:USERPROFILE\.ssh\id_rsa_vscode_centos7.pub" `
  -PrivateKeyPath "$env:USERPROFILE\.ssh\id_rsa_vscode_centos7"
```

如果 RSA 成功，把 SSH config 改成：

```sshconfig
Host centos7-node-121
    HostName 172.16.100.121
    User licun
    IdentityFile ~/.ssh/id_rsa_vscode_centos7
    IdentitiesOnly yes
```

## 常用命令

测试密码登录：

```powershell
ssh licun@172.16.100.7
```

测试免密登录：

```powershell
ssh -o BatchMode=yes licun@172.16.100.7 "echo key_ok"
```

查看 SSH 详细调试日志：

```powershell
ssh -vvv licun@172.16.100.121
```

重新安装 VS Code Server：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install-vscode-server-centos7.ps1 `
  -SshTarget licun@172.16.100.7 `
  -Package .\vscode-server_1.132.0_x64.tar.gz
```

清理服务器上的 VS Code Server：

```bash
rm -rf ~/.vscode-server
```

## 注意事项

- 不要把私钥提交到 GitHub。
- 不要把服务器密码写进脚本。
- 不建议把 `vscode-server_*.tar.gz` 提交到仓库，文件通常很大，应该从 Releases 下载。
- `sudo setsebool -P use_nfs_home_dirs 1` 是持久 SELinux 策略变更，只应由服务器管理员确认后执行。
- 如果服务器不是 CentOS 7 / RHEL 7，通常不需要手动安装兼容版 VS Code Server。

