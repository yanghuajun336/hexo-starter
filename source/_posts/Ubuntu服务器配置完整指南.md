---
title: Ubuntu 服务器配置完整指南：用户管理、SSH 安全配置与 Docker 安装
date: 2025-10-18 10:30:00
categories:
  - 运维
  - Linux
tags:
  - Ubuntu
  - SSH
  - Docker
  - 服务器配置
  - 安全
description: 详细介绍 Ubuntu 服务器的基础配置，包括用户管理、SSH 安全配置、Docker 安装以及 Windows 客户端连接问题解决方案
#cover: /images/ubuntu-server-config.jpg
---

在日常的服务器运维工作中，正确配置 Ubuntu 服务器的用户权限、SSH 安全策略和容器环境是确保系统安全性和高效运行的基础。本文将详细介绍从零开始配置 Ubuntu 服务器的完整流程。

<!-- more -->

## 🔧 系统用户管理

### 创建系统用户

首先创建一个专用的系统用户，避免直接使用 root 账户操作：

```bash
# 创建新用户（推荐参数组合）
sudo useradd -r -m -s /bin/bash yanghuajun
```

**参数说明：**
- `-r`：创建系统账号（UID 小于 1000）
- `-m`：自动创建用户主目录 `/home/yanghuajun`
- `-s /bin/bash`：指定默认 Shell 为 bash

{% note info %}
💡 **最佳实践**：建议为不同的服务创建专用用户，遵循最小权限原则。
{% endnote %}

### 设置用户密码

```bash
# 为新用户设置密码
sudo passwd yanghuajun
```

系统会提示输入并确认新密码。密码应当满足复杂性要求：
- 至少 8 位字符
- 包含大小写字母、数字和特殊字符
- 避免使用字典词汇

---

## 🔐 SSH 安全配置

### SSH 密钥对生成

在**客户端**生成 SSH 密钥对：

```bash
# 生成 RSA 密钥对
ssh-keygen -t rsa -b 4096 -C "yanghuajun@zlinkcloudtech.com"
```

**生成过程：**
1. 选择密钥保存位置（默认 `~/.ssh/id_rsa`）
2. 设置密钥密码（可选，但推荐）
3. 生成公钥 `id_rsa.pub` 和私钥 `id_rsa`

### 服务器端密钥配置

在**服务器端**配置公钥认证：

```bash
# 切换到目标用户
sudo su - yanghuajun

# 创建 .ssh 目录并设置权限
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# 创建 authorized_keys 文件
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# 将客户端公钥内容添加到 authorized_keys
echo "ssh-rsa AAAAB3NzaC1yc2EAAAA... yanghuajun@zlinkcloudtech.com" >> ~/.ssh/authorized_keys
```

{% note warning %}
⚠️ **权限重要性**：`.ssh` 目录权限必须是 700，`authorized_keys` 文件权限必须是 600，否则 SSH 服务会拒绝密钥认证。
{% endnote %}

### SSH 服务配置

编辑 SSH 服务配置文件：

```bash
sudo vim /etc/ssh/sshd_config
```

**关键配置项：**

```config
# 启用公钥认证
PubkeyAuthentication yes

# 指定公钥文件位置
AuthorizedKeysFile .ssh/authorized_keys .ssh/authorized_keys2

# 禁用密码认证（建议先测试密钥登录成功后再启用）
PasswordAuthentication no

# 支持 RSA 算法（Ubuntu 22.04+ 需要）
PubkeyAcceptedAlgorithms +ssh-rsa

# 禁用 root 用户直接登录
PermitRootLogin no

# 限制登录用户
AllowUsers yanghuajun

# 修改默认端口（可选，提高安全性）
Port 2222
```

**重启 SSH 服务：**

```bash
sudo systemctl restart sshd
sudo systemctl status sshd
```

{% note danger %}
🚨 **安全提醒**：在禁用密码认证前，请务必确认密钥登录正常工作，避免锁定自己！
{% endnote %}

---

## 🐳 Docker 环境安装

### 系统依赖安装

```bash
# 更新软件包索引
sudo apt update

# 安装必要依赖
sudo apt install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    software-properties-common \
    gnupg \
    lsb-release
```

### 添加 Docker 官方源

```bash
# 添加 Docker GPG 密钥
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# 添加 Docker APT 源
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

### Docker 安装与配置

```bash
# 更新软件包索引
sudo apt update

# 安装 Docker Engine
sudo apt install -y docker-ce docker-ce-cli containerd.io

#安装docker-compose
sudo apt install docker-compose

# 启动并设置开机自启
sudo systemctl start docker
sudo systemctl enable docker

# 验证安装
sudo docker --version
sudo docker run hello-world
```

### 用户权限配置

```bash
# 将用户添加到 docker 组（避免每次使用 sudo）
sudo usermod -aG docker yanghuajun

# 重新登录或使用以下命令立即生效
newgrp docker

# 测试普通用户权限
docker ps
```

{% note info %}
💡 **重要说明**：Docker 守护进程绑定到 Unix socket 而不是 TCP 端口。默认情况下，Unix socket 由 root 用户拥有，其他用户只能通过 sudo 访问。
{% endnote %}

---

## 🖥️ Windows 客户端连接

### 方法一：命令行连接

```bash
# 基本连接命令
ssh -i "C:\Users\YourName\.ssh\id_rsa" yanghuajun@your-server-ip

# 指定端口（如果修改了默认端口）
ssh -i "C:\Users\YourName\.ssh\id_rsa" -p 2222 yanghuajun@your-server-ip

# 详细输出（用于调试）
ssh -v -i "C:\Users\YourName\.ssh\id_rsa" yanghuajun@your-server-ip
```

### 方法二：VS Code Remote SSH

1. 安装 VS Code 的 "Remote - SSH" 插件
2. 按 `Ctrl+Shift+P` 打开命令面板
3. 输入 "Remote-SSH: Open Configuration File"
4. 添加服务器配置：

```config
Host my-ubuntu-server
    HostName your-server-ip
    User yanghuajun
    Port 2222
    IdentityFile C:\Users\YourName\.ssh\id_rsa
    ServerAliveInterval 60
```

### Windows 私钥权限问题解决

如果遇到 `Permissions for 'xxx' are too open` 错误，需要修正 Windows 下的文件权限：

#### 🔧 图形界面方式

1. **清空继承权限**
   - 右键私钥文件 → 属性 → 安全 → 高级
   - 点击"禁用继承" → "从此对象删除所有已继承的权限"

2. **添加当前用户权限**
   - 点击"添加" → "选择主体" → "高级" → "立即查找"
   - 选择当前用户 → 确定
   - 设置"完全控制"权限

3. **验证权限设置**
   - 确保只有当前用户具有访问权限
   - 其他用户和组应该被完全移除

#### 💻 命令行方式

```cmd
# 移除所有权限
icacls "C:\Users\YourName\.ssh\id_rsa" /inheritance:r

# 添加当前用户完全控制权限
icacls "C:\Users\YourName\.ssh\id_rsa" /grant:r "%USERNAME%:F"

# 验证权限设置
icacls "C:\Users\YourName\.ssh\id_rsa"
```

---

## 🛠️ 故障排查

### SSH 连接问题

```bash
# 检查 SSH 服务状态
sudo systemctl status sshd

# 查看 SSH 日志
sudo tail -f /var/log/auth.log

# 测试配置文件语法
sudo sshd -t

# 查看监听端口
sudo netstat -tlnp | grep :22
```

### Docker 问题

```bash
# 检查 Docker 服务状态
sudo systemctl status docker

# 查看 Docker 日志
sudo journalctl -u docker.service

# 检查 Docker 版本和信息
docker version
docker info

# 测试网络连接
docker run --rm busybox ping -c 3 8.8.8.8
```

---

## 📋 安全检查清单

### 系统安全
- [ ] 禁用 root 直接登录
- [ ] 使用密钥认证替代密码
- [ ] 修改默认 SSH 端口
- [ ] 配置防火墙规则
- [ ] 定期更新系统补丁

### 用户管理
- [ ] 创建专用服务账户
- [ ] 设置强密码策略
- [ ] 定期审查用户权限
- [ ] 启用登录审计

### Docker 安全
- [ ] 使用非特权用户运行容器
- [ ] 定期更新 Docker 和镜像
- [ ] 限制容器资源使用
- [ ] 配置 Docker 守护进程安全选项

---

## 🔗 相关资源

### 官方文档
- [Ubuntu Server Guide](https://ubuntu.com/server/docs)
- [Docker Official Documentation](https://docs.docker.com/)
- [OpenSSH Manual](https://www.openssh.com/manual.html)

### 工具推荐
- **SSH 客户端**: PuTTY, MobaXterm, Windows Terminal
- **密钥管理**: ssh-agent, KeePass
- **监控工具**: htop, netstat, systemctl

### 参考文章
- [Windows SSH 权限问题解决](https://www.cnblogs.com/chkhk/p/13414823.html)
- [SSH 私钥格式问题](https://blog.csdn.net/qq_27727147/article/details/120304936)

---

{% note success %}
🎉 **配置完成**：按照以上步骤，您已经成功配置了一个安全、高效的 Ubuntu 服务器环境。记得定期备份重要配置文件和数据！
{% endnote %}

---

*本文持续更新中，如有问题或建议，欢迎在评论区交流讨论。*
