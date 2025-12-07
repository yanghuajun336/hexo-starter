#!/usr/bin/env bash
set -e

echo "============================================"
echo "[hexo-container] Starting Hexo Blog Container"
echo "[hexo-container] Time: $(date)"
echo "[hexo-container] REPO_URL: ${REPO_URL:-<none>}"
echo "[hexo-container] REPO_BRANCH: ${REPO_BRANCH}"
echo "[hexo-container] PULL_INTERVAL: ${PULL_INTERVAL}s"
echo "[hexo-container] THEME_MODE: ${THEME_MODE}"
echo "============================================"

# ========== Git 配置 ==========
git config --global --add safe.directory /var/www/hexo
git config --global user.name "${GIT_USER:-hexo}"
git config --global user.email "${GIT_EMAIL:-hexo@example.com}"
git config --global core.quotepath false

cd /var/www/hexo

# ========== 函数：检测并返回正确的分支 ==========
detect_branch() {
  local target_branch="${REPO_BRANCH}"
  
  # 检查目标分支是否存在
  if git show-ref --verify --quiet "refs/remotes/origin/${target_branch}" 2>/dev/null; then
    echo "${target_branch}"
    return 0
  fi
  
  # 尝试获取远程默认分支
  local default_branch
  default_branch=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)
  
  if [ -n "${default_branch}" ]; then
    echo "[hexo-container] Warning: Branch '${target_branch}' not found, using default '${default_branch}'" >&2
    echo "${default_branch}"
    return 0
  fi
  
  # 最后的fallback
  echo "[hexo-container] Warning: Could not detect branch, using '${target_branch}' as-is" >&2
  echo "${target_branch}"
  return 0
}

# ========== 克隆或更新仓库 ==========
if [ -n "${REPO_URL}" ]; then
  if [ -d .git ]; then
    echo "[hexo-container] Existing repository detected"
    echo "[hexo-container] Fetching updates from origin..."
    git fetch origin --prune || {
      echo "[hexo-container] Warning: git fetch failed, continuing anyway"
    }
    
    BRANCH=$(detect_branch)
    echo "[hexo-container] Using branch: ${BRANCH}"
    
    if git reset --hard "origin/${BRANCH}"; then
      echo "[hexo-container] Successfully reset to origin/${BRANCH}"
    elif git pull origin "${BRANCH}"; then
      echo "[hexo-container] Successfully pulled origin/${BRANCH}"
    else
      echo "[hexo-container] Warning: Failed to update from remote, using local state"
    fi
  else
    echo "[hexo-container] No existing repository, cloning ${REPO_URL}..."
    
    # 尝试克隆指定分支
    if git ls-remote --heads "${REPO_URL}" "${REPO_BRANCH}" >/dev/null 2>&1; then
      echo "[hexo-container] Cloning branch: ${REPO_BRANCH}"
      git clone --depth 1 --single-branch --branch "${REPO_BRANCH}" "${REPO_URL}" .  || git clone "${REPO_URL}" . 
    else
      # 获取默认分支
      default_branch=$(git ls-remote --symref "${REPO_URL}" HEAD 2>/dev/null | awk '/^ref:/ {sub(/refs\/heads\//,"",$2); print $2; exit}')
      if [ -n "${default_branch}" ]; then
        echo "[hexo-container] Branch '${REPO_BRANCH}' not found, cloning default branch: ${default_branch}"
        git clone --depth 1 --single-branch --branch "${default_branch}" "${REPO_URL}" .  || git clone "${REPO_URL}" .
      else
        echo "[hexo-container] Cloning with default settings"
        git clone "${REPO_URL}" .
      fi
    fi
  fi
else
  echo "[hexo-container] No REPO_URL provided"
  if [ !  -f package.json ] && [ ! -d source ]; then
    echo "[hexo-container] Initializing new Hexo site..."
    npx hexo init . || {
      echo "[hexo-container] Warning: hexo init failed"
    }
  else
    echo "[hexo-container] Using existing Hexo site"
  fi
fi

# ========== 安装依赖 ==========
if [ -f package.json ]; then
  echo "[hexo-container] Installing npm dependencies..."
  npm install --no-audit --no-fund --loglevel=error || {
    echo "[hexo-container] Warning: npm install had errors, continuing anyway"
  }
else
  echo "[hexo-container] No package.json found, skipping npm install"
fi

# ========== 主题配置 ==========
echo "============================================"
echo "[hexo-container] Theme Configuration"
echo "[hexo-container] Mode: ${THEME_MODE}"
echo "[hexo-container] Name: ${THEME_NAME}"
echo "[hexo-container] Default Site Theme: ${DEFAULT_SITE_THEME}"
echo "============================================"

THEME_DIR="themes/${THEME_NAME}"

# 确保 themes 目录存在
mkdir -p themes

# 读取当前站点主题
current_site_theme=""
if [ -f _config.yml ]; then
  current_site_theme=$(awk -F': ' '/^theme:/ {gsub(/\r/, "", $2); gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}' _config.yml || true)
  echo "[hexo-container] Current site theme in _config.yml: '${current_site_theme}'"
fi

# 安装主题（如果不存在或不完整）
echo "[hexo-container] Checking theme '${THEME_NAME}'..."
if [ -d "${THEME_DIR}/layout" ] && [ -f "${THEME_DIR}/_config.yml" ]; then
  echo "[hexo-container] ✅ Theme '${THEME_NAME}' exists and is complete"
  ls -lh "${THEME_DIR}/" | head -5
else
  echo "[hexo-container] ⚠️ Theme '${THEME_NAME}' missing or incomplete, installing..."
  
  # 删除不完整的主题目录
  rm -rf "${THEME_DIR}"
  
  # 克隆主题
  if git clone --depth 1 "${THEME_REPO}" "${THEME_DIR}"; then
    echo "[hexo-container] ✅ Theme '${THEME_NAME}' cloned successfully"
    ls -lh "${THEME_DIR}/" | head -5
  else
    echo "[hexo-container] ❌ Failed to clone theme '${THEME_NAME}'"
    echo "[hexo-container] Will attempt to use default theme 'landscape'"
    # 如果克隆失败，尝试使用 landscape 主题
    if [ !  -d "themes/landscape" ]; then
      git clone --depth 1 https://github.com/hexojs/hexo-theme-landscape.git themes/landscape || true
    fi
    current_site_theme="landscape"
  fi
fi

# 初始化主题配置文件
if [ "${ALLOW_CONFIG_INIT}" = "true" ] && [ !  -f "_config.${THEME_NAME}.yml" ] && [ -f "${THEME_DIR}/_config.yml" ]; then
  echo "[hexo-container] Creating _config.${THEME_NAME}. yml from theme default"
  cp "${THEME_DIR}/_config.yml" "_config.${THEME_NAME}.yml"
fi

# 决定是否切换主题
should_switch="false"
case "${THEME_MODE}" in
  keep)
    echo "[hexo-container] THEME_MODE=keep, not changing theme"
    ;;
  force-butterfly|force)
    echo "[hexo-container] THEME_MODE=force, switching to ${THEME_NAME}"
    should_switch="true"
    ;;
  auto|*)
    if [ -z "${current_site_theme}" ] || [ "${current_site_theme}" = "${DEFAULT_SITE_THEME}" ]; then
      echo "[hexo-container] THEME_MODE=auto, switching to ${THEME_NAME}"
      should_switch="true"
    else
      echo "[hexo-container] THEME_MODE=auto, keeping user's theme '${current_site_theme}'"
    fi
    ;;
esac

# 执行主题切换
if [ "${should_switch}" = "true" ]; then
  # 检查目标主题是否存在
  if [ -d "${THEME_DIR}/layout" ]; then
    if [ -f _config.yml ]; then
      backup_file="_config.yml.bak. $(date +%Y%m%d_%H%M%S)"
      cp _config.yml "${backup_file}"
      echo "[hexo-container] Backed up _config.yml to ${backup_file}"
      
      if grep -qE '^theme:' _config.yml 2>/dev/null; then
        sed -i "s/^theme:. */theme: ${THEME_NAME}/" _config.yml
      else
        echo "theme: ${THEME_NAME}" >> _config.yml
      fi
      echo "[hexo-container] ✅ Theme switched to '${THEME_NAME}'"
    else
      echo "theme: ${THEME_NAME}" > _config.yml
      echo "[hexo-container] Created _config.yml with theme '${THEME_NAME}'"
    fi
  else
    echo "[hexo-container] ⚠️ Cannot switch to '${THEME_NAME}' - theme not available"
  fi
fi

# 安装主题所需的渲染器
echo "[hexo-container] Checking theme renderers..."
need_renderers="false"

if [ !  -d "node_modules/hexo-renderer-pug" ]; then
  echo "[hexo-container] hexo-renderer-pug not found"
  need_renderers="true"
fi

if [ ! -d "node_modules/hexo-renderer-stylus" ]; then
  echo "[hexo-container] hexo-renderer-stylus not found"
  need_renderers="true"
fi

if [ "${need_renderers}" = "true" ]; then
  echo "[hexo-container] Installing theme renderers (pug, stylus)..."
  npm install --save --no-audit --no-fund hexo-renderer-pug hexo-renderer-stylus --loglevel=error || {
    echo "[hexo-container] Warning: Failed to install renderers"
  }
else
  echo "[hexo-container] ✅ All required renderers are installed"
fi

# 显示最终的主题配置
echo "[hexo-container] Final theme configuration:"
grep "^theme:" _config.yml || echo "No theme configured in _config.yml"
echo "[hexo-container] Available themes:"
ls -1 themes/ 2>/dev/null || echo "No themes found"

# ========== 启动 Webhook 服务器 ==========
echo "============================================"
echo "[hexo-container] Starting webhook server on port ${WEBHOOK_PORT}"
echo "============================================"
export PORT=${WEBHOOK_PORT}
node /usr/local/bin/webhook. js >/tmp/webhook. log 2>&1 &
WEBHOOK_PID=$! 
echo "[hexo-container] Webhook server started (PID: ${WEBHOOK_PID})"

# ========== 定时轮询（后台） ==========
if [ -n "${REPO_URL}" ]; then
  echo "============================================"
  echo "[hexo-container] Starting periodic pull (interval: ${PULL_INTERVAL}s)"
  echo "============================================"
  
  (while true; do
    sleep "${PULL_INTERVAL}"
    echo "[hexo-container] [$(date)] Checking for updates..."
    
    if git fetch origin --prune 2>/dev/null; then
      BRANCH=$(detect_branch)
      LOCAL=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
      REMOTE=$(git rev-parse "origin/${BRANCH}" 2>/dev/null || echo "unknown")
      
      if [ "${LOCAL}" != "${REMOTE}" ] && [ "${REMOTE}" != "unknown" ]; then
        echo "[hexo-container] Changes detected (${LOCAL:0:8} -> ${REMOTE:0:8})"
        echo "[hexo-container] Pulling and regenerating..."
        
        if git reset --hard "origin/${BRANCH}" || git pull origin "${BRANCH}"; then
          npm install --no-audit --no-fund --loglevel=error || true
          
          # 确保渲染器已安装
          if [ ! -d "node_modules/hexo-renderer-pug" ] || [ ! -d "node_modules/hexo-renderer-stylus" ]; then
            npm install --save --no-audit --no-fund hexo-renderer-pug hexo-renderer-stylus --loglevel=error || true
          fi
          
          ${BUILD_CMD} || {
            echo "[hexo-container] Build failed!"
          }
          echo "[hexo-container] [$(date)] Regeneration complete!"
        else
          echo "[hexo-container] Failed to pull changes"
        fi
      else
        echo "[hexo-container] No changes (${LOCAL:0:8})"
      fi
    else
      echo "[hexo-container] Git fetch failed, skipping this cycle"
    fi
  done) &
  
  POLLER_PID=$!
  echo "[hexo-container] Periodic poller started (PID: ${POLLER_PID})"
else
  echo "[hexo-container] REPO_URL not set, skipping periodic pull"
fi

# ========== 初始构建 ==========
echo "============================================"
echo "[hexo-container] Running initial build..."
echo "============================================"

# 执行构建
if eval "${BUILD_CMD}"; then
  echo "[hexo-container] ✅ Build completed"
else
  echo "[hexo-container] ❌ Build failed, checking issues..."
  
  # 检查主题
  if [ !  -d "themes/${THEME_NAME}/layout" ]; then
    echo "[hexo-container] Theme '${THEME_NAME}' layout directory missing!"
    echo "[hexo-container] Attempting to use default theme..."
    sed -i 's/^theme:.*/theme: landscape/' _config.yml
    npx hexo generate || echo "[hexo-container] Fallback build also failed"
  fi
fi

# 验证 public 目录
if [ -d public ] && [ "$(ls -A public 2>/dev/null)" ]; then
  file_count=$(find public -type f | wc -l)
  echo "[hexo-container] ✅ Build successful, public/ contains ${file_count} files"
  ls -lh public/ | head -10
  
  # 检查 index.html
  if [ -f public/index.html ]; then
    size=$(stat -c%s public/index.html 2>/dev/null || stat -f%z public/index.html)
    echo "[hexo-container] ✅ index.html exists (${size} bytes)"
    if [ "${size}" -gt 100 ]; then
      echo "[hexo-container] ✅ index.html has content"
    else
      echo "[hexo-container] ⚠️ Warning: index.html seems too small (${size} bytes)"
    fi
  else
    echo "[hexo-container] ⚠️ Warning: index.html not found in public/"
  fi
else
  echo "[hexo-container] ❌ ERROR: public/ directory is empty or missing!"
  echo "[hexo-container] Site will not be accessible!"
fi

# ========== 启动 Nginx ==========
echo "============================================"
echo "[hexo-container] Starting Nginx server"
echo "============================================"

# 测试 Nginx 配置
if nginx -t; then
  echo "[hexo-container] ✅ Nginx configuration OK"
else
  echo "[hexo-container] ❌ ERROR: Nginx configuration test failed!"
  exit 1
fi

echo "[hexo-container] Blog accessible at: http://localhost:4000"
echo "[hexo-container] Webhook endpoint at: http://localhost:${WEBHOOK_PORT}/webhook"
echo "============================================"

# 前台运行 Nginx（作为主进程）
exec nginx -g 'daemon off;'