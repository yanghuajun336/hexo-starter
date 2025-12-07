FROM node:20-bullseye-slim

# 环境变量
ENV REPO_URL="" \
    REPO_BRANCH="main" \
    PULL_INTERVAL="60" \
    HEXO_PORT="4000" \
    WEBHOOK_PORT="9001" \
    WEBHOOK_SECRET="" \
    GIT_USER="hexo" \
    GIT_EMAIL="hexo@example.com" \
    BUILD_CMD="npx hexo generate" \
    START_CMD="npx hexo server -i 0.0.0.0 -p 4000" \
    THEME_MODE="auto" \
    THEME_NAME="butterfly" \
    THEME_REPO="https://github.com/jerryc127/hexo-theme-butterfly.git" \
    DEFAULT_SITE_THEME="landscape" \
    ALLOW_CONFIG_INIT="true"

WORKDIR /var/www/hexo

# 安装系统依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    openssh-client \
    ca-certificates \
    curl \
    build-essential \
    python3 \
    nginx \
    && rm -rf /var/lib/apt/lists/*

# 配置 npm 并安装全局包（分开执行，便于调试）
RUN npm set progress=false \
    && npm config set registry https://registry.npmmirror.com

# 安装 Hexo CLI 和渲染器（使用最新稳定版本）
RUN npm install -g hexo-cli hexo-renderer-pug hexo-renderer-stylus \
    && mkdir -p /run/nginx /var/log/nginx

# 复制配置文件
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY webhook.js /usr/local/bin/webhook.js
COPY nginx.conf /etc/nginx/nginx.conf

# 设置权限
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/webhook.js

# 暴露端口
EXPOSE 4000 9001

# 健康检查
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:4000/ || exit 1

CMD ["/usr/local/bin/entrypoint.sh"]