#!/usr/bin/env bash
set -e

echo "[hexo-container] Starting with REPO_URL=${REPO_URL:-<none>}"

# Graceful Hexo server stop/start helpers (avoid pkill dependency)
stop_hexo() {
  if [ -f /tmp/hexo-server.pid ]; then
    pid=$(cat /tmp/hexo-server.pid 2>/dev/null || true)
    if [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null; then
      echo "[hexo-container] Stopping Hexo server (pid ${pid})..."
      kill "${pid}" 2>/dev/null || true
      sleep 2
    fi
    rm -f /tmp/hexo-server.pid || true
  else
    echo "[hexo-container] No PID file found; nothing to stop."
  fi
}

start_hexo_bg() {
  echo "[hexo-container] Starting Hexo server (background) ..."
  nohup sh -c "${START_CMD}" >/tmp/hexo-server.log 2>&1 &
  echo $! >/tmp/hexo-server.pid
}

# Configure git identity
git config --global user.name "${GIT_USER:-hexo}"
git config --global user.email "${GIT_EMAIL:-hexo@example.com}"

cd /var/www/hexo

if [ -n "${REPO_URL}" ]; then
  if [ -d .git ]; then
    echo "[hexo-container] Existing repo detected — fetching ${REPO_BRANCH}..."
    git fetch origin || true
    # Determine branch: use REPO_BRANCH if valid, else remote default HEAD
    remote_head=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)
    branch_to_use="${REPO_BRANCH}"
    if ! git show-ref --verify --quiet "refs/remotes/origin/${branch_to_use}"; then
      if [ -n "${remote_head}" ]; then
        echo "[hexo-container] Remote branch '${REPO_BRANCH}' not found; falling back to default '${remote_head}'."
        branch_to_use="${remote_head}"
      else
        echo "[hexo-container] Remote default branch detection failed; proceeding without reset."
        branch_to_use="${REPO_BRANCH}"
      fi
    fi
    git reset --hard "origin/${branch_to_use}" || git pull origin "${branch_to_use}" || true
  else
    echo "[hexo-container] Cloning ${REPO_URL} (branch ${REPO_BRANCH})..."
    if git ls-remote --heads "${REPO_URL}" "${REPO_BRANCH}" >/dev/null 2>&1; then
      git clone --single-branch --branch "${REPO_BRANCH}" "${REPO_URL}" . || git clone "${REPO_URL}" .
    else
      # Fallback to remote HEAD
      default_branch=$(git ls-remote --symref "${REPO_URL}" HEAD 2>/dev/null | awk '/^ref:/ {sub(/refs\/heads\//,"",$2); print $2; exit}')
      echo "[hexo-container] Remote branch '${REPO_BRANCH}' not found; cloning default '${default_branch}'."
      if [ -n "${default_branch}" ]; then
        git clone --single-branch --branch "${default_branch}" "${REPO_URL}" . || git clone "${REPO_URL}" .
      else
        git clone "${REPO_URL}" .
      fi
    fi
  fi
else
  if [ ! -f package.json ] && [ ! -d source ]; then
    echo "[hexo-container] No REPO_URL — initializing new hexo site..."
    npx hexo init . || true
  fi
fi

# Install dependencies if package.json present
if [ -f package.json ]; then
  echo "[hexo-container] Installing npm dependencies..."
  npm install --no-audit --no-fund || true
fi

# ========== Theme setup (env-driven, idempotent) ==========
THEME_MODE=${THEME_MODE:-auto}
THEME_NAME=${THEME_NAME:-butterfly}
THEME_REPO=${THEME_REPO:-https://github.com/jerryc127/hexo-theme-butterfly.git}
DEFAULT_SITE_THEME=${DEFAULT_SITE_THEME:-landscape}
ALLOW_CONFIG_INIT=${ALLOW_CONFIG_INIT:-true}

echo "[hexo-container] Theme control: mode=${THEME_MODE} name=${THEME_NAME} defaultSiteTheme=${DEFAULT_SITE_THEME}"

# Ensure theme directory exists (install if missing)
if [ -d "themes/${THEME_NAME}" ]; then
  echo "[hexo-container] Theme '${THEME_NAME}' already present — skip clone."
else
  echo "[hexo-container] Cloning theme '${THEME_NAME}' from ${THEME_REPO}..."
  git clone -b master "${THEME_REPO}" "themes/${THEME_NAME}" || true
fi

# Initialize theme-specific config if allowed and missing
if [ "${ALLOW_CONFIG_INIT}" = "true" ] && [ ! -f "_config.${THEME_NAME}.yml" ] && [ -f "themes/${THEME_NAME}/_config.yml" ]; then
  cp "themes/${THEME_NAME}/_config.yml" "_config.${THEME_NAME}.yml"
  echo "[hexo-container] Initialized _config.${THEME_NAME}.yml from theme default."
fi

# Read current site theme from _config.yml (if exists)
current_site_theme=""
if [ -f _config.yml ]; then
  current_site_theme=$(awk -F': ' '/^theme:/ {gsub(/\r/, "", $2); print $2; exit}' _config.yml || true)
fi

should_switch="false"
case "${THEME_MODE}" in
  keep)
    echo "[hexo-container] THEME_MODE=keep — not changing site theme."
    ;;
  force-butterfly|force)
    should_switch="true"
    ;;
  auto|*)
    if [ -z "${current_site_theme}" ] || [ "${current_site_theme}" = "${DEFAULT_SITE_THEME}" ]; then
      should_switch="true"
    else
      echo "[hexo-container] Existing non-default theme '${current_site_theme}' — keeping user's choice."
    fi
    ;;
esac

if [ "${should_switch}" = "true" ]; then
  echo "[hexo-container] Switching site theme to '${THEME_NAME}' (with backup)."
  if [ -f _config.yml ]; then
    cp _config.yml "_config.yml.bak.$(date +%Y%m%d%H%M%S)" || true
    if grep -qE '^theme:' _config.yml 2>/dev/null; then
      sed -i "s/^theme:.*/theme: ${THEME_NAME}/" _config.yml || true
    else
      echo "theme: ${THEME_NAME}" >> _config.yml
    fi
  else
    echo "theme: ${THEME_NAME}" > _config.yml
  fi
else
  echo "[hexo-container] Theme switch skipped (mode=${THEME_MODE})."
fi

# ==========================================================

# If project is mounted from host, node_modules from image are hidden.
# Ensure project has required renderers locally so Hexo can render pug/stylus.
if [ -f package.json ] || [ -d node_modules ]; then
  need_install="false"
  if [ ! -d "node_modules/hexo-renderer-pug" ]; then
    need_install="true"
  fi
  if [ ! -d "node_modules/hexo-renderer-stylus" ]; then
    need_install="true"
  fi
  if [ "${need_install}" = "true" ]; then
    echo "[hexo-container] Installing missing renderers into project node_modules (so Hexo can render templates)..."
    npm install --no-audit --no-fund --no-save hexo-renderer-pug hexo-renderer-stylus || true
  else
    echo "[hexo-container] Required renderers present in project node_modules."
  fi
fi

# Start webhook server in background (generator only)
echo "[hexo-container] Starting webhook listener on port ${WEBHOOK_PORT} (generator mode)..."
export PORT=${WEBHOOK_PORT}
node /usr/local/bin/webhook.js &

# Background periodic poller (pull + generate, no server restart)
(while true; do
  sleep "${PULL_INTERVAL}"
  if [ -n "${REPO_URL}" ]; then
    echo "[hexo-container] Periodic pull: checking for updates..."
    git fetch origin || true
    # Resolve branch to use
    remote_head=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)
    branch_to_use="${REPO_BRANCH}"
    if ! git show-ref --verify --quiet "refs/remotes/origin/${branch_to_use}"; then
      branch_to_use="${remote_head:-${REPO_BRANCH}}"
      echo "[hexo-container] Using branch '${branch_to_use}' for periodic pull."
    fi
    LOCAL=$(git rev-parse HEAD 2>/dev/null || true)
    REMOTE=$(git rev-parse "origin/${branch_to_use}" 2>/dev/null || true)
    if [ "${LOCAL}" != "${REMOTE}" ]; then
      echo "[hexo-container] Changes detected — pulling and regenerating"
      if git reset --hard "origin/${branch_to_use}" || git pull origin "${branch_to_use}"; then
        npm install --no-audit --no-fund || true
        ${BUILD_CMD} || true
        echo "[hexo-container] Regeneration complete; Nginx serves updated public/."
      else
        echo "[hexo-container] Pull/reset failed — skip regeneration this cycle."
      fi
    else
      echo "[hexo-container] No changes found."
    fi
  fi
done) &

# Initial generate and start Nginx in foreground
echo "[hexo-container] Running initial generate (hexo build)..."
${BUILD_CMD} || true

echo "[hexo-container] Starting Nginx (foreground as PID 1) ..."
mkdir -p /run/nginx || true
nginx -t -c /etc/nginx/nginx.conf || true
exec nginx -g 'daemon off;' -c /etc/nginx/nginx.conf
