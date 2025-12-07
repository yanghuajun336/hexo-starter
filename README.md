好的！我给你准备一份完整、专业的文档。

---

# 📚 Hexo Docker 自动化部署方案完整文档

## 目录

- [1. 项目简介](#1-项目简介)
- [2.  架构设计与实现原理](#2-架构设计与实现原理)
- [3. 环境准备](#3-环境准备)
- [4.  快速开始](#4-快速开始)
- [5.  配置详解](#5-配置详解)
- [6. 使用指南](#6-使用指南)
- [7. 博客写作规范](#7-博客写作规范)
- [8. 故障排查](#8-故障排查)
- [9. 高级配置](#9-高级配置)
- [10.  附录](#10-附录)

---

## 1.  项目简介

### 1.1 项目概述

本项目提供了一套基于 Docker 的 Hexo 博客自动化部署方案，实现了从代码提交到博客发布的完整自动化流程。

**核心特性：**

- 🚀 **全自动部署**：代码提交后自动触发构建和发布
- 🔄 **双更新机制**：支持定时轮询和 Webhook 两种更新方式
- 🎨 **主题管理**：自动安装和配置 Butterfly 主题
- ⚡ **高性能服务**：使用 Nginx 提供静态文件服务
- 🐳 **容器化部署**：一键启动，环境隔离
- 🔐 **安全可靠**：支持私有仓库、Webhook 签名验证

### 1. 2 技术栈

| 技术 | 版本 | 用途 |
|------|------|------|
| **Node.js** | 20 | Hexo 运行环境 |
| **Hexo** | 7.x | 静态博客生成器 |
| **Nginx** | 1.18+ | 静态文件服务器 |
| **Docker** | 20.10+ | 容器化部署 |
| **Git** | 2.x | 代码版本管理 |
| **Butterfly** | 最新版 | Hexo 主题 |

### 1.3 系统要求

**服务器要求：**
- 操作系统：Linux (Ubuntu 20.04+/CentOS 8+/Debian 11+)
- CPU：1 核心以上
- 内存：1GB 以上
- 磁盘：5GB 以上可用空间

**客户端要求：**
- Docker >= 20.10
- Docker Compose >= 1.29
- Git >= 2.0

---

## 2. 架构设计与实现原理

### 2.1 系统架构图

```
┌─────────────────────────────────────────────────────────────┐
│                        Docker Container                      │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                    Entrypoint. sh                      │  │
│  │              (容器启动入口脚本)                        │  │
│  └────────┬─────────────────────────────────────────────┘  │
│           │                                                  │
│           ├─────► 1. Git Clone/Pull (获取博客源码)           │
│           │                                                  │
│           ├─────► 2.  Theme Installation (主题安装)          │
│           │                                                  │
│           ├─────► 3. Hexo Generate (静态文件生成)            │
│           │           │                                      │
│           │           └─────► public/ (静态HTML)             │
│           │                                                  │
│           ├─────► 4.  Nginx Start (前台运行)                 │
│           │           │                                      │
│           │           └─────► 服务 public/ 目录              │
│           │                                                  │
│           ├─────► 5.  Webhook Server (后台监听)              │
│           │           │                                      │
│           │           └─────► Node.js HTTP Server           │
│           │                   (监听 9001 端口)               │
│           │                                                  │
│           └─────► 6. Periodic Poller (定时轮询)             │
│                       │                                      │
│                       └─────► 每 N 秒检查更新                │
└───────────────────────────────────────────────────────────┘
                           │                  │
                           │                  │
        ┌──────────────────┘                  └─────────────────┐
        ▼                                                        ▼
   用户访问                                              Git 仓库更新
   :4000                                                        │
        │                                                        │
        │                                                        ▼
        └─────► Nginx ────► public/                    Webhook/轮询触发
                            (静态文件)                            │
                                                                 │
                                                                 ▼
                                                          自动重新生成
```

### 2.2 工作流程

#### 2.2.1 初始化流程

```mermaid
graph TD
    A[容器启动] --> B[配置 Git 环境]
    B --> C{检查 REPO_URL}
    C -->|已设置| D[克隆/拉取仓库]
    C -->|未设置| E[使用本地文件]
    D --> F[安装依赖 npm install]
    E --> F
    F --> G[检查主题配置]
    G --> H{主题完整? }
    H -->|否| I[克隆主题到 themes/]
    H -->|是| J[跳过主题安装]
    I --> K[安装渲染器]
    J --> K
    K --> L[执行 hexo generate]
    L --> M[启动 Webhook 服务器]
    M --> N[启动定时轮询]
    N --> O[启动 Nginx 前台]
    O --> P[服务就绪]
```

#### 2.2.2 自动更新流程

**方式一：Webhook 触发（实时）**

```
GitHub/Gitee 推送 → Webhook 通知 → Node.js 接收
                                        │
                                        ↓
                                   验证签名
                                        │
                                        ↓
                                   检查分支
                                        │
                                        ↓
                              git pull + npm install
                                        │
                                        ↓
                                  hexo generate
                                        │
                                        ↓
                              Nginx 自动服务新文件
```

**方式二：定时轮询（定时）**

```
每隔 N 秒 → git fetch → 比较 commit hash
                              │
                              ↓
                         有新提交? 
                              │
                    ┌─────────┴─────────┐
                   Yes                  No
                    │                   │
                    ↓                   ↓
          git pull + rebuild        跳过本次
```

### 2.3 核心组件说明

#### 2.3. 1 Hexo 静态生成器

**作用：** 将 Markdown 文件转换为静态 HTML 网站

**工作流程：**

1.  **解析配置**：读取 `_config.yml` 和主题配置
2. **加载文件**：读取 `source/` 目录下的 Markdown 文件
3. **渲染模板**：使用主题模板（Pug/EJS）渲染页面
4. **生成文件**：输出静态 HTML/CSS/JS 到 `public/` 目录

**关键目录：**

```
/var/www/hexo/
├── _config.yml          # 站点配置
├── _config.butterfly.yml # 主题配置
├── source/              # 源文件目录
│   ├── _posts/          # 博客文章（Markdown）
│   └── about/           # 关于页面等
├── themes/              # 主题目录
│   └── butterfly/       # Butterfly 主题
└── public/              # 生成的静态文件（Nginx 服务）
    ├── index.html
    ├── css/
    ├── js/
    └── ... 
```

#### 2.3.2 Nginx 静态服务器

**作用：** 高性能 HTTP 服务器，提供静态文件访问

**配置要点：**

```nginx
server {
    listen 4000;
    root /var/www/hexo/public;  # 指向 Hexo 生成的静态文件
    index index.html;
    
    location / {
        try_files $uri $uri/index.html $uri.html =404;
    }
    
    location /webhook {
        proxy_pass http://127.0.0.1:9001;  # 代理到 Webhook 服务
    }
}
```

**优势：**
- ⚡ 高性能：直接服务静态文件，无需 Node.js 运行时
- 🗜️ 压缩：自动 Gzip 压缩，减少传输大小
- 📦 缓存：静态资源缓存，加速访问

#### 2.3. 3 Webhook 服务器

**作用：** 接收 Git 平台的推送通知，触发自动重建

**实现：** Node.js HTTP Server（webhook.js）

**核心功能：**

```javascript
// 1. 验证签名（防止恶意请求）
function verifySignature(payload, signature) {
  const hmac = crypto.createHmac('sha256', SECRET);
  const digest = hmac.update(payload).digest('hex');
  return crypto.timingSafeEqual(
    Buffer.from('sha256=' + digest),
    Buffer.from(signature)
  );
}

// 2.  触发重建
function rebuild() {
  exec(`
    git pull origin ${BRANCH} &&
    npm install &&
    npm install hexo-renderer-pug hexo-renderer-stylus &&
    npx hexo generate
  `);
}
```

**端点：**
- `POST /webhook` - 接收 Git 推送通知
- `GET /health` - 健康检查

#### 2.3.4 定时轮询器

**作用：** 定期检查 Git 仓库更新，作为 Webhook 的备份机制

**实现：** Bash 后台循环

```bash
while true; do
  sleep ${PULL_INTERVAL}
  
  LOCAL=$(git rev-parse HEAD)
  REMOTE=$(git rev-parse origin/${BRANCH})
  
  if [ "${LOCAL}" != "${REMOTE}" ]; then
    git pull && npm install && hexo generate
  fi
done
```

**优势：**
- 🔄 可靠性：即使 Webhook 失败也能更新
- ⏰ 可预测：固定时间间隔检查
- 🛡️ 容错性：网络问题不影响更新

### 2.4 数据流转

```
┌──────────────┐
│ Markdown文章 │
│  (Git 仓库)  │
└──────┬───────┘
       │ 1. git clone/pull
       ↓
┌──────────────┐
│ source/_posts│
│  (容器内)    │
└──────┬───────┘
       │ 2. hexo generate
       ↓
┌──────────────┐
│   public/    │
│ (静态HTML)   │
└──────┬───────┘
       │ 3. nginx serve
       ↓
┌──────────────┐
│  用户浏览器  │
└──────────────┘
```

---

## 3. 环境准备

### 3.1 安装 Docker

**Ubuntu/Debian：**

```bash
# 更新软件包索引
sudo apt-get update

# 安装必要的依赖
sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# 添加 Docker 官方 GPG 密钥
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# 设置 Docker 仓库
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 安装 Docker Engine
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# 将当前用户加入 docker 组
sudo usermod -aG docker $USER

# 重新登录或执行
newgrp docker

# 验证安装
docker --version
docker compose version
```

**CentOS/RHEL：**

```bash
# 安装依赖
sudo yum install -y yum-utils

# 添加 Docker 仓库
sudo yum-config-manager --add-repo https://download.docker. com/linux/centos/docker-ce.repo

# 安装 Docker
sudo yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# 启动 Docker
sudo systemctl start docker
sudo systemctl enable docker

# 添加用户到 docker 组
sudo usermod -aG docker $USER

# 验证
docker --version
```

### 3.2 配置 Git 凭据

**方式一：SSH 密钥（推荐）**

```bash
# 1. 生成 SSH 密钥
ssh-keygen -t ed25519 -C "your_email@example.com"

# 2. 查看公钥
cat ~/.ssh/id_ed25519.pub

# 3. 添加到 Git 平台
# GitHub: https://github.com/settings/keys
# Gitee: https://gitee. com/profile/sshkeys
# GitLab: https://gitlab.com/-/profile/keys

# 4. 测试连接
ssh -T git@github.com    # GitHub
ssh -T git@gitee.com     # Gitee
```

**方式二：Access Token**

```bash
# 1.  生成 Token
# GitHub: Settings → Developer settings → Personal access tokens
# Gitee: 设置 → 私人令牌

# 2. Token 需要的权限
# - repo (完整权限)
# - write:packages (可选)

# 3. 在 . env 中配置
REPO_URL=https://username:token@github.com/username/repo.git
```

### 3.3 项目目录结构

```bash
your-blog/
├── docker/              # Docker 配置目录（本项目）
│   ├── Dockerfile
│   ├── docker-compose.yaml
│   ├── entrypoint.sh
│   ├── webhook.js
│   ├── nginx.conf
│   ├── . env            # 环境变量配置（不提交）
│   ├── .env.example    # 环境变量示例
│   ├── .gitignore
│   └── README.md
├── source/             # Hexo 博客源文件
│   ├── _posts/         # 博客文章
│   └── about/
├── themes/             # Hexo 主题
├── _config.yml         # Hexo 配置
├── _config.butterfly.yml # 主题配置
└── package.json        # 依赖配置
```

---

## 4. 快速开始

### 4. 1 克隆项目

```bash
# 如果你已有 Hexo 博客项目
cd your-hexo-blog
mkdir docker
cd docker

# 下载所有配置文件到这个目录
# （或者从我提供的完整文件创建）
```

### 4.2 配置环境变量

```bash
# 复制示例配置
cp .env.example .env

# 编辑配置
nano .env  # 或使用 vim
```

**关键配置项：**

```bash
# ========== Git 仓库配置 ==========
# SSH 方式（推荐）
REPO_URL=git@github. com:username/blog.git

# 或 HTTPS + Token 方式
REPO_URL=https://username:ghp_xxxxxxxxxxxx@github.com/username/blog.git

# 分支
REPO_BRANCH=main

# ========== Git 身份 ==========
GIT_USER=Your Name
GIT_EMAIL=your.email@example.com

# ========== 端口配置 ==========
HEXO_PORT=4000        # 博客访问端口
WEBHOOK_PORT=9001     # Webhook 端口

# ========== Webhook 安全 ==========
# 生成随机密钥：openssl rand -hex 20
WEBHOOK_SECRET=your_webhook_secret_here

# ========== 构建配置 ==========
BUILD_CMD=npx hexo clean && npx hexo generate
PULL_INTERVAL=300     # 轮询间隔（秒）

# ========== 主题配置 ==========
THEME_MODE=auto       # auto/keep/force
THEME_NAME=butterfly
```

### 4.3 构建镜像

```bash
# 在 docker 目录下
docker build -t hexo-site:latest .

# 查看镜像
docker images | grep hexo-site
```

**构建参数说明：**

- `-t hexo-site:latest` - 镜像名称和标签
- `. ` - Dockerfile 所在目录（当前目录）

### 4.4 启动容器

```bash
# 使用 docker compose
docker compose up -d

# 查看容器状态
docker compose ps

# 查看实时日志
docker compose logs -f
```

**等待初始化：**

容器首次启动需要：
1. 克隆 Git 仓库（~10-30秒）
2. 安装 npm 依赖（~30-60秒）
3.  克隆主题（~10-20秒）
4. 生成静态文件（~5-10秒）

总计约 1-2 分钟。

### 4.5 验证部署

```bash
# 1. 检查容器状态
docker ps | grep hexo-site

# 应该显示 STATUS 为 Up

# 2. 测试博客访问
curl -I http://localhost:4000

# 应该返回 200 OK

# 3. 测试 Webhook
curl http://localhost:9001/health

# 应该返回 {"status":"ok","service":"hexo-webhook",... }

# 4. 浏览器访问
# http://localhost:4000
```

### 4.6 配置防火墙（如果是云服务器）

```bash
# Ubuntu/Debian (UFW)
sudo ufw allow 4000/tcp
sudo ufw allow 9001/tcp
sudo ufw reload

# CentOS/RHEL (Firewalld)
sudo firewall-cmd --permanent --add-port=4000/tcp
sudo firewall-cmd --permanent --add-port=9001/tcp
sudo firewall-cmd --reload

# 阿里云/腾讯云/AWS
# 需要在控制台的安全组中开放端口
```

---

## 5. 配置详解

### 5.1 环境变量完整列表

| 变量名 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| **Git 配置** ||||
| `REPO_URL` | string | 空 | Git 仓库地址（SSH 或 HTTPS） |
| `REPO_BRANCH` | string | main | Git 分支 |
| `GIT_USER` | string | hexo | Git 提交用户名 |
| `GIT_EMAIL` | string | hexo@example.com | Git 提交邮箱 |
| **端口配置** ||||
| `HEXO_PORT` | number | 4000 | 博客访问端口 |
| `WEBHOOK_PORT` | number | 9001 | Webhook 监听端口 |
| **安全配置** ||||
| `WEBHOOK_SECRET` | string | 空 | Webhook 签名密钥 |
| **构建配置** ||||
| `BUILD_CMD` | string | npx hexo generate | 构建命令 |
| `START_CMD` | string | npx hexo server...  | 启动命令（仅调试用） |
| `PULL_INTERVAL` | number | 60 | 轮询间隔（秒） |
| **主题配置** ||||
| `THEME_MODE` | enum | auto | 主题模式（auto/keep/force） |
| `THEME_NAME` | string | butterfly | 主题名称 |
| `THEME_REPO` | string | github.com/. ../butterfly | 主题仓库地址 |
| `DEFAULT_SITE_THEME` | string | landscape | 默认主题名称 |
| `ALLOW_CONFIG_INIT` | boolean | true | 是否初始化主题配置 |

### 5.2 主题模式详解

| 模式 | 行为 | 适用场景 |
|------|------|----------|
| **auto** | 如果当前主题是默认主题（landscape），则切换为 butterfly；否则保持 | 新博客或想尝试 butterfly |
| **keep** | 始终保持仓库中 `_config.yml` 里配置的主题 | 已有自定义主题 |
| **force** | 强制切换为 butterfly，忽略仓库配置 | 确定要使用 butterfly |

**示例：**

```bash
# 场景1：新博客，想使用 butterfly
THEME_MODE=auto  # 或 force

# 场景2：已有 NexT 主题，想保留
THEME_MODE=keep

# 场景3：从其他主题迁移到 butterfly
THEME_MODE=force
```

### 5. 3 Webhook 签名配置

**为什么需要签名？**

防止恶意请求触发重建，消耗服务器资源。

**生成密钥：**

```bash
# 方法1：使用 openssl
openssl rand -hex 20

# 方法2：使用 uuidgen
uuidgen

# 方法3：在线生成
# https://www.random.org/strings/
```

**配置流程：**

```bash
# 1. 在 .env 中设置
WEBHOOK_SECRET=abc123def456ghi789jkl

# 2. 在 Git 平台配置相同的密钥
# GitHub: Webhook → Secret
# Gitee: WebHooks → 密码
```

### 5.4 Docker Compose 配置

**完整配置项：**

```yaml
version: "3.8"

services:
  hexo:
    image: hexo-site:latest
    container_name: hexo-site
    restart: unless-stopped
    
    environment:
      REPO_URL: "${REPO_URL}"
      # ...  其他环境变量
    
    ports:
      - "${HEXO_PORT:-4000}:4000"
      - "${WEBHOOK_PORT:-9001}:9001"
    
    volumes:
      # 方式1：Docker volume（生产推荐）
      - hexo_data:/var/www/hexo
      
      # 方式2：本地目录挂载（开发模式）
      # - ../:/var/www/hexo:rw
    
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    
    # 可选：资源限制
    # deploy:
    #   resources:
    #     limits:
    #       cpus: '1'
    #       memory: 1G
    #     reservations:
    #       cpus: '0.5'
    #       memory: 512M

volumes:
  hexo_data:
    driver: local
```

**配置项说明：**

- **restart: unless-stopped** - 容器总是重启（除非手动停止）
- **healthcheck** - 健康检查，失败时自动重启
- **logging** - 日志轮转，防止日志文件过大
- **deploy. resources** - 限制容器资源使用

---

## 6. 使用指南

### 6.1 博客写作流程

#### 6.1.1 本地写作（推荐）

```bash
# 1. 克隆仓库到本地
git clone git@github.com:username/blog.git
cd blog

# 2. 安装依赖（首次）
npm install

# 3.  创建新文章
npx hexo new post "文章标题"

# 4. 编辑文章
# 文件位置：source/_posts/文章标题.md

# 5. 本地预览
npx hexo server

# 6. 浏览器访问 http://localhost:4000 预览

# 7. 提交代码
git add .
git commit -m "Add new post: 文章标题"
git push

# 8. 等待自动部署（Webhook 约10秒，轮询最多5分钟）
```

#### 6.1.2 在线写作

**使用 GitHub/Gitee 在线编辑：**

```bash
# 1. 访问仓库网页
# GitHub: https://github.com/username/blog
# Gitee: https://gitee.com/username/blog

# 2. 进入 source/_posts 目录

# 3. 点击「新建文件」或「上传文件」

# 4. 文件名格式：YYYY-MM-DD-标题.md

# 5. 编辑内容

# 6. 提交更改（页面底部）

# 7. 自动触发部署
```

### 6.2 触发构建的两种方式

#### 6. 2.1 方式一：Webhook（实时，推荐）

**配置步骤：**

**GitHub:**

1. 进入仓库 → **Settings** → **Webhooks** → **Add webhook**

2. 配置参数：
   ```
   Payload URL: http://your-server-ip:9001/webhook
   Content type: application/json
   Secret: 你的 WEBHOOK_SECRET
   Which events: Just the push event
   Active: ✓
   ```

3.  点击 **Add webhook**

4. 测试：编辑任意文件并提交，查看 Recent Deliveries

**Gitee:**

1.  进入仓库 → **管理** → **WebHooks** → **添加 WebHook**

2. 配置参数：
   ```
   URL: http://your-server-ip:9001/webhook
   密码: 你的 WEBHOOK_SECRET
   选择事件: Push
   ```

3. 点击 **添加**

4. 测试：点击「测试」按钮

**验证 Webhook：**

```bash
# 查看 Webhook 日志
docker logs hexo-site | grep webhook

# 应该看到类似输出：
# [webhook] Received POST /webhook from xxx.xxx.xxx.xxx
# [webhook] Event: push
# [webhook] Rebuild triggered
```

**Webhook 工作流程：**

```
你提交代码 → Git 平台发送 HTTP POST
            ↓
    Webhook 服务器接收（9001端口）
            ↓
        验证签名
            ↓
        检查分支
            ↓
    执行 git pull
            ↓
   npm install（安装新依赖）
            ↓
    hexo generate
            ↓
    Nginx 自动服务新文件
            ↓
        博客更新完成
```

#### 6.2.2 方式二：定时轮询（自动，备份）

**工作原理：**

容器内每隔 `PULL_INTERVAL` 秒自动执行：

```bash
git fetch origin
本地 commit hash ← → 远程 commit hash
        ↓ 不同
    git pull + rebuild
```

**配置轮询间隔：**

```bash
# . env 文件
PULL_INTERVAL=300  # 5分钟检查一次

# 常用值：
# 60   - 1分钟（频繁更新）
# 300  - 5分钟（推荐）
# 600  - 10分钟
# 1800 - 30分钟（低频更新）
```

**查看轮询日志：**

```bash
docker logs hexo-site | grep "Checking for updates"

# 输出示例：
# [hexo-container] [2025-12-07 13:00:00] Checking for updates... 
# [hexo-container] No changes (abc1234)
# 或
# [hexo-container] Changes detected (abc1234 -> def5678)
# [hexo-container] Pulling and regenerating...
```

**优缺点对比：**

| 方式 | 延迟 | 可靠性 | 服务器负载 | 推荐场景 |
|------|------|--------|------------|----------|
| **Webhook** | 10秒内 | 依赖网络 | 低 | 生产环境 |
| **轮询** | 最多 N 秒 | 高 | 中等 | 备份机制 |

**最佳实践：** 两种方式同时启用，Webhook 作为主要方式，轮询作为备份。

### 6.3 手动触发重建

```bash
# 方法1：进入容器手动执行
docker exec -it hexo-site bash
cd /var/www/hexo
git pull
npm install
npx hexo clean
npx hexo generate
exit

# 方法2：重启容器（会重新克隆和构建）
docker compose restart

# 方法3：调用 Webhook API
curl -X POST http://localhost:9001/webhook \
  -H "Content-Type: application/json" \
  -d '{"ref":"refs/heads/main","repository":{"full_name":"test/repo"}}'
```

### 6.4 查看构建状态

```bash
# 1. 查看容器日志
docker logs hexo-site --tail 50

# 2.  查看最近的构建
docker logs hexo-site | grep -A 5 "Running initial build\|Rebuild triggered"

# 3. 实时监控
docker logs -f hexo-site

# 4. 检查生成的文件
docker exec hexo-site ls -lh /var/www/hexo/public/ | head -20

# 5. 检查 Nginx 日志
docker exec hexo-site tail -f /var/log/nginx/access.log
docker exec hexo-site tail -f /var/log/nginx/error.log
```

### 6.5 更新博客配置

#### 6.5.1 修改站点配置（_config.yml）

```bash
# 1. 本地修改
git clone your-repo
cd your-repo
nano _config.yml

# 2. 常见配置
title: 我的博客
subtitle: 副标题
description: 博客描述
author: 作者名
language: zh-CN
timezone: Asia/Shanghai

url: https://yourdomain.com
root: /

# 3. 提交并推送
git add _config.yml
git commit -m "Update site config"
git push

# 4. 等待自动部署
```

#### 6.5.2 修改主题配置（_config.butterfly.yml）

```bash
# 编辑主题配置
nano _config.butterfly.yml

# 常用配置
menu:
  首页: / || fas fa-home
  归档: /archives/ || fas fa-archive
  标签: /tags/ || fas fa-tags
  分类: /categories/ || fas fa-folder-open
  关于: /about/ || fas fa-heart

avatar:
  img: /img/avatar.jpg
  effect: false

# 提交
git add _config.butterfly.yml
git commit -m "Update theme config"
git push
```

### 6.6 管理主题

#### 6.6.1 切换主题

```bash
# 方式1：通过环境变量强制切换
# 编辑 .env
THEME_MODE=force
THEME_NAME=butterfly

# 重启容器
docker compose restart

# 方式2：手动修改配置
git clone your-repo
nano _config.yml

# 修改 theme 行
theme: butterfly  # 或其他主题名

git push
```

#### 6.6.2 更新主题

```bash
# 进入容器
docker exec -it hexo-site bash

# 更新主题
cd /var/www/hexo/themes/butterfly
git pull

# 重新生成
cd /var/www/hexo
npx hexo clean
npx hexo generate

exit

# 或者删除主题让容器重新克隆
docker exec hexo-site rm -rf /var/www/hexo/themes/butterfly
docker compose restart
```

---

## 7. 博客写作规范

### 7.1 文章命名规范

**文件名格式：**

```bash
# 推荐格式
YYYY-MM-DD-文章标题-英文.md

# 示例
2025-12-07-docker-hexo-deployment. md
2025-12-08-kubernetes-gateway-api.md
```

**为什么这样命名？**

- ✅ 文件列表自动按时间排序
- ✅ URL 更 SEO 友好
- ✅ 便于查找历史文章

### 7.2 Front Matter 模板

**标准模板：**

```markdown
---
title: 文章标题
date: 2025-12-07 14:30:00
updated: 2025-12-07 14:30:00
tags:
  - 标签1
  - 标签2
  - 标签3
categories:
  - [一级分类, 二级分类]
description: 文章简介（用于SEO和摘要）
keywords: 关键词1, 关键词2, 关键词3
cover: /img/cover/article-cover.jpg
top_img: /img/banner/article-banner.jpg
comments: true
toc: true
toc_number: true
copyright: true
---

这里开始正文... 
```

**字段说明：**

| 字段 | 必填 | 说明 | 示例 |
|------|------|------|------|
| `title` | ✅ | 文章标题 | Docker 容器化部署 |
| `date` | ✅ | 发布日期 | 2025-12-07 14:30:00 |
| `updated` | ❌ | 更新日期 | 2025-12-08 10:00:00 |
| `tags` | 推荐 | 标签列表 | [Docker, DevOps] |
| `categories` | 推荐 | 分类层级 | [[技术, 容器化]] |
| `description` | 推荐 | 文章摘要 | 介绍如何使用Docker部署应用 |
| `keywords` | ❌ | SEO关键词 | docker,容器,部署 |
| `cover` | ❌ | 封面图片 | /img/cover. jpg |
| `top_img` | ❌ | 顶部大图 | /img/banner. jpg |
| `comments` | ❌ | 是否开启评论 | true |
| `toc` | ❌ | 是否显示目录 | true |
| `copyright` | ❌ | 是否显示版权 | true |

### 7.3 分类体系建议

**推荐分类结构：**

```yaml
categories:
  # 技术类
  - [技术, 前端]
  - [技术, 后端]
  - [技术, DevOps]
  - [技术, 数据库]
  - [技术, 云原生]
  
  # 工具类
  - [工具, 开发工具]
  - [工具, 效率提升]
  
  # 思考类
  - [思考, 技术思考]
  - [思考, 职业发展]
  
  # 生活类
  - [生活, 随笔]
  - [生活, 读书笔记]
```

**分类原则：**

1. **层级清晰**：最多2-3层
2. **数量适中**：一级分类不超过10个
3. **便于导航**：用户能快速找到相关文章
4. **避免重叠**：同一篇文章只属于一个分类路径

### 7.4 标签使用建议

**标签分类：**

```yaml
# 技术栈标签
tags: [Docker, Kubernetes, Nginx, Node.js]

# 主题标签
tags: [部署, 自动化, CI/CD, 监控]

# 语言标签
tags: [JavaScript, Python, Go, Shell]

# 概念标签
tags: [微服务, 容器化, 云原生, DevOps]
```

**标签原则：**

1. **每篇文章 3-5 个标签**
2. **使用现有标签**（避免标签泛滥）
3. **具体明确**（不要用"其他"、"杂项"）
4. **便于检索**（考虑读者会搜什么）

### 7.5 文章模板示例

#### 7.5.1 技术教程模板

```markdown
---
title: Kubernetes Gateway API 使用指南
date: 2025-12-07 14:00:00
tags:
  - Kubernetes
  - Gateway API
  - 云原生
categories:
  - [技术, 云原生]
description: 详细介绍 Kubernetes Gateway API 的使用方法和最佳实践
cover: /img/covers/k8s-gateway. jpg
toc: true
---

## 前言

简单介绍文章背景和要解决的问题。

## 环境准备

### 系统要求

- Kubernetes 1.26+
- kubectl 工具

### 安装步骤

```bash
# 安装命令
kubectl apply -f ... 
```

## 核心概念

### 概念一

解释第一个核心概念... 

### 概念二

解释第二个核心概念...

## 实战示例

### 示例1：基础配置

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
... 
```

### 示例2：高级配置

... 

## 常见问题

### 问题1

**现象：** ... 

**原因：** ... 

**解决方案：** ... 

## 总结

总结文章要点。

## 参考资料

- [官方文档](https://example.com)
- [相关文章](https://example.com)
```

#### 7.5.2 故障排查模板

```markdown
---
title: 解决 Nginx 403 Forbidden 错误
date: 2025-12-07 15:00:00
tags:
  - Nginx
  - 故障排查
  - Web服务
categories:
  - [技术, 运维]
description: 记录一次 Nginx 403 错误的排查和解决过程
---

## 问题描述

访问网站时出现 403 Forbidden 错误。

**环境信息：**
- OS: Ubuntu 20.04
- Nginx: 1.18.0
- 现象截图: ![错误截图](/img/error-403.png)

## 错误日志

```
2025/12/07 13:01:38 [error] directory index forbidden
```

## 排查过程

### 步骤1：检查文件权限

```bash
ls -la /var/www/html/
```

**发现：** index.html 文件大小为 0

### 步骤2：检查 Nginx 配置

```nginx
location / {
    try_files $uri $uri/ /index.html;
}
```

**发现：** 配置导致无限重定向

## 解决方案

修改 Nginx 配置：

```nginx
location / {
    try_files $uri $uri/index.html =404;
}
```

重启 Nginx：

```bash
nginx -s reload
```

## 预防措施

1. 使用配置管理工具
2. 定期备份配置
3. 监控错误日志

## 总结

问题根因是...  以后要注意... 
```

#### 7.5.3 读书笔记模板

```markdown
---
title: 《凤凰项目》读书笔记
date: 2025-12-07 20:00:00
tags:
  - 读书笔记
  - DevOps
  - 管理
categories:
  - [生活, 读书笔记]
description: DevOps 经典书籍《凤凰项目》的读书笔记和思考
cover: /img/books/phoenix-project.jpg
---

## 书籍信息

- **书名：** 凤凰项目
- **作者：** Gene Kim
- **出版时间：** 2013年
- **豆瓣评分：** 8.5

## 核心观点

### 观点1：三步工作法

... 

### 观点2：持续改进

...

## 精彩摘录

> 引用书中的精彩段落

## 我的思考

结合自己的实际工作经验... 

## 行动计划

读完这本书后，我打算：

1. [ ] 在团队中推行某某实践
2. [ ] 学习某某技术
3. [ ] 改进某某流程

## 推荐指数

⭐⭐⭐⭐⭐ 5/5

推荐理由：... 
```

### 7.6 写作风格建议

**1. 标题层级：**

```markdown
# 一级标题（文章标题，只用一次）
## 二级标题（章节）
### 三级标题（小节）
#### 四级标题（要点）
```

**2.  代码块：**

```markdown
# 指定语言高亮
​```bash
#!/bin/bash
echo "Hello"
​```

​```javascript
const hello = () => console.log('Hello');
​```

​```yaml
apiVersion: v1
kind: Pod
​```
```

**3. 图片：**

```markdown
# 本地图片（放在 source/img/ 目录）
![图片描述](/img/screenshot.png)

# 外部图片
![图片描述](https://example.com/image.jpg)

# 图片带链接
[![图片描述](/img/logo.png)](https://example.com)
```

**4. 链接：**

```markdown
# 内部链接
[关于页面](/about/)
[其他文章](/2025/12/06/other-post/)

# 外部链接
[GitHub](https://github. com)

# 参考链接
这是一段文字[^1]

[^1]: 参考资料说明
```

**5. 表格：**

```markdown
| 列1 | 列2 | 列3 |
|-----|-----|-----|
| 内容1 | 内容2 | 内容3 |
| 内容4 | 内容5 | 内容6 |

# 对齐方式
| 左对齐 | 居中 | 右对齐 |
|:------|:----:|------:|
| 内容 | 内容 | 内容 |
```

**6. 提示框（Butterfly 主题）：**

```markdown
{% note success %}
这是成功提示
{% endnote %}

{% note info %}
这是信息提示
{% endnote %}

{% note warning %}
这是警告提示
{% endnote %}

{% note danger %}
这是危险提示
{% endnote %}
```

**7. 折叠内容：**

```markdown
{% hideToggle 点击展开,#FF7242,#FFF7E9 %}
这里是折叠的内容
{% endhideToggle %}
```

### 7.7 SEO 优化建议

**1. 标题优化：**

```markdown
# ❌ 不好的标题
- 学习笔记
- 今天的收获
- 问题解决

# ✅ 好的标题
- Docker 容器化部署完整指南
- 解决 Kubernetes Pod 启动失败的5种方法
- 从零搭建高可用 Nginx 集群
```

**2. 描述优化：**

```yaml
# ❌ 不好的描述
description: 本文介绍了... 

# ✅ 好的描述
description: 详细介绍如何使用 Docker 部署 Hexo 博客，包括 Nginx 配置、Webhook 自动化和故障排查，附完整代码示例。
```

**3. 关键词优化：**

```yaml
# ❌ 关键词堆砌
keywords: docker,容器,kubernetes,k8s,devops,cicd,自动化,部署,运维

# ✅ 精准关键词
keywords: Docker 部署,Hexo 博客,Nginx 配置,自动化部署
```

**4. URL 优化：**

```markdown
# ❌ 不好的 URL
/2025/12/07/1/

# ✅ 好的 URL（在 _config.yml 配置）
permalink: :year/:month/:day/:title/
# 结果：/2025/12/07/docker-hexo-deployment/
```

---

## 8. 故障排查

### 8.1 常见问题速查表

| 现象 | 可能原因 | 解决方案 |
|------|----------|----------|
| 403 Forbidden | public/ 目录为空 | 手动执行 hexo generate |
| 404 Not Found | 文章路径错误 | 检查 permalink 配置 |
| 主题不生效 | 主题未安装 | 检查 themes/ 目录 |
| Webhook 无响应 | 端口未开放 | 检查防火墙规则 |
| Git 克隆失败 | 认证失败 | 检查 SSH Key 或 Token |
| 构建慢 | npm 源慢 | 换用国内镜像 |
| 容器启动失败 | 配置错误 | 查看容器日志 |

### 8.2 日志查看

```bash
# 1. 容器日志（最近100行）
docker logs hexo-site --tail 100

# 2.  实时日志
docker logs -f hexo-site

# 3. 特定时间范围
docker logs hexo-site --since "2025-12-07T14:00:00"

# 4.  Nginx 访问日志
docker exec hexo-site tail -f /var/log/nginx/access.log

# 5.  Nginx 错误日志
docker exec hexo-site tail -f /var/log/nginx/error.log

# 6.  Webhook 日志
docker exec hexo-site tail -f /tmp/webhook.log

# 7. 搜索特定关键词
docker logs hexo-site | grep -i "error\|fail\|warn"

# 8. 导出日志到文件
docker logs hexo-site > hexo-logs.txt 2>&1
```

### 8. 3 进入容器调试

```bash
# 1. 以 root 身份进入
docker exec -it hexo-site bash

# 2. 常用调试命令
cd /var/www/hexo

# 检查目录结构
ls -la

# 检查 Git 状态
git status
git log -1

# 检查 Node.js 版本
node --version
npm --version

# 检查 Hexo 版本
npx hexo version

# 手动生成
npx hexo clean
npx hexo generate --debug

# 检查生成结果
ls -lh public/

# 测试 Nginx
nginx -t
curl http://localhost:4000

# 退出容器
exit
```

### 8.4 重置容器

```bash
# 1. 停止容器
docker compose stop

# 2. 删除容器
docker compose rm -f

# 3. 删除 volume（注意：会删除所有数据！）
docker volume rm docker_hexo_data

# 4. 重新启动
docker compose up -d

# 5. 查看初始化日志
docker compose logs -f
```

### 8.5 网络问题排查

```bash
# 1. 检查端口占用
sudo netstat -tlnp | grep -E "4000|9001"
sudo lsof -i :4000
sudo lsof -i :9001

# 2. 测试端口连通性
# 从容器内部测试
docker exec hexo-site curl -I http://localhost:4000

# 从宿主机测试
curl -I http://localhost:4000

# 从外部测试
curl -I http://your-server-ip:4000

# 3. 检查防火墙
# Ubuntu/Debian
sudo ufw status

# CentOS/RHEL
sudo firewall-cmd --list-ports

# 4. 检查 Docker 网络
docker network ls
docker network inspect bridge

# 5. 测试 DNS 解析（容器内）
docker exec hexo-site ping -c 3 github.com
docker exec hexo-site ping -c 3 gitee.com
```

### 8.6 性能问题排查

```bash
# 1. 查看容器资源使用
docker stats hexo-site

# 2. 查看容器详情
docker inspect hexo-site

# 3. 检查磁盘使用
docker exec hexo-site df -h
docker system df

# 4. 检查 npm 缓存
docker exec hexo-site du -sh ~/. npm

# 5. 清理 Docker 资源
docker system prune -a
docker volume prune
```

---

## 9.  高级配置

### 9.1 自定义域名

**步骤1：配置 DNS**

```
类型: A
主机记录: @ (或 www)
记录值: 你的服务器IP
TTL: 600
```

**步骤2：配置 Nginx 反向代理（推荐）**

在宿主机安装 Nginx：

```nginx
# /etc/nginx/sites-available/blog. conf
server {
    listen 80;
    server_name yourdomain.com www.yourdomain.com;
    
    location / {
        proxy_pass http://localhost:4000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

**步骤3：配置 HTTPS（Let's Encrypt）**

```bash
# 安装 Certbot
sudo apt install certbot python3-certbot-nginx

# 获取证书
sudo certbot --nginx -d yourdomain.com -d www.yourdomain.com

# 自动续期
sudo crontab -e
# 添加：
0 3 * * * certbot renew --quiet
```

### 9.2 配置 CDN

**使用 Cloudflare：**

1. 注册 Cloudflare 账号
2. 添加你的域名
3. 修改域名的 DNS 服务器为 Cloudflare 提供的
4. 在 Cloudflare 面板开启 CDN 加速

**配置缓存规则：**

```
Page Rules:
- *.css, *.js, *.jpg, *.png: Cache Everything (1 month)
- /: Bypass Cache
```

### 9.3 配置评论系统

**Gitalk（基于 GitHub Issues）：**

```yaml
# _config.butterfly.yml
comments:
  use: gitalk
  
gitalk:
  client_id: your_client_id
  client_secret: your_client_secret
  repo: blog-comments
  owner: your_github_username
  admin:
    - your_github_username
```

**Waline（独立部署）：**

```yaml
comments:
  use: Waline
  
waline:
  serverURL: https://your-waline-server.com
  lang: zh-CN
```

### 9.4 配置统计分析

**Google Analytics：**

```yaml
# _config.butterfly.yml
google_analytics: UA-XXXXXXXXX-X
```

**百度统计：**

```yaml
baidu_analytics: your_baidu_token
```

### 9.5 配置搜索功能

**本地搜索：**

```bash
# 安装插件
npm install hexo-generator-search --save

# _config.yml
search:
  path: search.xml
  field: post
  content: true
```

**Algolia 搜索：**

```bash
npm install hexo-algolia --save

# _config.yml
algolia:
  applicationID: 'your_app_id'
  apiKey: 'your_api_key'
  indexName: 'blog'
```

### 9. 6 多环境部署

**生产环境（docker-compose. prod.yaml）：**

```yaml
version: "3.8"

services:
  hexo:
    image: hexo-site:latest
    container_name: hexo-prod
    restart: always
    environment:
      REPO_URL: "${REPO_URL}"
      REPO_BRANCH: "main"
      PULL_INTERVAL: "300"
      NODE_ENV: "production"
    ports:
      - "4000:4000"
      - "9001:9001"
    volumes:
      - hexo_prod_data:/var/www/hexo
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 1G

volumes:
  hexo_prod_data:
```

**开发环境（docker-compose.dev.yaml）：**

```yaml
version: "3.8"

services:
  hexo:
    build: .
    container_name: hexo-dev
    environment:
      REPO_URL: ""
      THEME_MODE: "keep"
      NODE_ENV: "development"
    ports:
      - "4000:4000"
    volumes:
      - ../:/var/www/hexo:rw
    command: npx hexo server
```

**使用方式：**

```bash
# 生产环境
docker compose -f docker-compose.prod. yaml up -d

# 开发环境
docker compose -f docker-compose.dev.yaml up -d
```

### 9.7 备份和恢复

**自动备份脚本：**

```bash
#!/bin/bash
# backup.sh

BACKUP_DIR="/backup/hexo"
DATE=$(date +%Y%m%d_%H%M%S)

# 备份 Git 仓库
docker exec hexo-site tar czf /tmp/hexo_${DATE}.tar.gz /var/www/hexo

# 复制到宿主机
docker cp hexo-site:/tmp/hexo_${DATE}.tar.gz ${BACKUP_DIR}/

# 清理旧备份（保留7天）
find ${BACKUP_DIR} -name "hexo_*.tar.gz" -mtime +7 -delete

echo "Backup completed: hexo_${DATE}.tar.gz"
```

**定时任务：**

```bash
# 添加到 crontab
crontab -e

# 每天凌晨3点备份
0 3 * * * /path/to/backup.sh >> /var/log/hexo-backup.log 2>&1
```

**恢复：**

```bash
# 解压备份
tar xzf hexo_20251207_030000.tar.gz

# 复制到容器
docker cp var/www/hexo hexo-site:/var/www/

# 重启容器
docker compose restart
```

### 9.8 监控告警

**使用 Uptime Kuma：**

```bash
# 部署 Uptime Kuma
docker run -d \
  --name uptime-kuma \
  -p 3001:3001 \
  -v uptime-kuma:/app/data \
  louislam/uptime-kuma:1

# 访问 http://localhost:3001
# 添加监控：
# - HTTP: http://localhost:4000
# - Keyword: 博客标题
# - 通知：邮件/钉钉/Slack
```

**健康检查脚本：**

```bash
#!/bin/bash
# health-check.sh

URL="http://localhost:4000"
WEBHOOK_URL="https://your-webhook-url"

# 检查网站是否可访问
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" $URL)

if [ "$HTTP_CODE" != "200" ]; then
  # 发送告警
  curl -X POST $WEBHOOK_URL \
    -H "Content-Type: application/json" \
    -d "{\"text\":\"⚠️ 博客无法访问！HTTP $HTTP_CODE\"}"
  
  # 尝试重启容器
  docker compose restart
fi
```

---

## 10. 附录

### 10.1 完整文件清单

```
docker/
├── Dockerfile              # Docker 镜像构建文件
├── docker
