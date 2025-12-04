# Hexo Docker 镜像（支持自动拉取、构建与 webhook）

该镜像用于在容器中运行 Hexo 博客，支持：

- 容器启动时自动从指定 git 仓库拉取代码并安装依赖。
- 周期性轮询远程仓库更新并自动构建（`PULL_INTERVAL`）。
- 支持通过 webhook（POST /payload）主动触发拉取与构建，并可配置 `WEBHOOK_SECRET` 进行签名校验。
- 所有主要参数通过环境变量配置，且提供默认值。

主要环境变量：

- `REPO_URL`：要克隆的仓库地址（例如 git@github.com:you/your-hexo.git 或 https://...）。默认空（会初始化一个新站点）。
- `REPO_BRANCH`：分支，默认 `main`。
- `PULL_INTERVAL`：轮询间隔（秒），默认 `60`。
- `HEXO_PORT`：Hexo 服务端口，默认 `4000`。
- `WEBHOOK_PORT`：Webhook 监听端口，默认 `9001`。
- `WEBHOOK_SECRET`：若设置，则 webhook 需要使用 HMAC-SHA1 签名（GitHub 风格，头部 `X-Hub-Signature`）。
- `GIT_USER` / `GIT_EMAIL`：容器内 git 提交配置的用户名和邮箱（默认为 `hexo` 和 `hexo@example.com`）。
- `BUILD_CMD`：构建命令，默认 `npx hexo generate`。
- `START_CMD`：启动命令，默认 `npx hexo server -i 0.0.0.0 -p $HEXO_PORT`。

构建镜像示例：

```bash
docker build -t hexo-auto:latest .
```

运行示例（使用 GitHub 仓库并开启 webhook secret）：

```bash
docker run -d \
  -e REPO_URL="https://github.com/you/your-hexo.git" \
  -e REPO_BRANCH="main" \
  -e WEBHOOK_SECRET="yoursecret" \
  -p 4000:4000 -p 9001:9001 \
  --name hexo-auto hexo-auto:latest
```

发送 webhook（测试）示例：

```bash
curl -X POST http://localhost:9001/payload -d '{}' \
  -H "X-Hub-Signature: sha1=$(echo -n '{}' | openssl dgst -sha1 -hmac 'yoursecret' | sed 's/^.* //')"
```

注意：如果你使用私有仓库并且通过 ssh 克隆，请在运行容器时挂载 SSH 密钥到 `/root/.ssh`，或者在镜像中配置合适的凭证。

如果没有提供 `REPO_URL`，容器会在工作目录初始化一个新的 Hexo 站点并运行，方便快速本地调试。
