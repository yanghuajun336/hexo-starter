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
    git fetch origin "${REPO_BRANCH}" || true
    git reset --hard "origin/${REPO_BRANCH}" || git pull origin "${REPO_BRANCH}" || true
  else
    echo "[hexo-container] Cloning ${REPO_URL} (branch ${REPO_BRANCH})..."
    git clone --single-branch --branch "${REPO_BRANCH}" "${REPO_URL}" . || git clone "${REPO_URL}" .
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

# Start webhook server in background
echo "[hexo-container] Starting webhook listener on port ${WEBHOOK_PORT}..."
export PORT=${WEBHOOK_PORT}
node /usr/local/bin/webhook.js &

# Background periodic poller
(while true; do
  sleep "${PULL_INTERVAL}"
  if [ -n "${REPO_URL}" ]; then
    echo "[hexo-container] Periodic pull: checking for updates..."
    git fetch origin "${REPO_BRANCH}" || true
    LOCAL=$(git rev-parse HEAD 2>/dev/null || true)
    REMOTE=$(git rev-parse "origin/${REPO_BRANCH}" 2>/dev/null || true)
    if [ "${LOCAL}" != "${REMOTE}" ]; then
      echo "[hexo-container] Changes detected — pulling and rebuilding"
      git reset --hard "origin/${REPO_BRANCH}" || git pull origin "${REPO_BRANCH}" || true
      npm install --no-audit --no-fund || true
      ${BUILD_CMD} || true
      echo "[hexo-container] Restarting Hexo server to apply config changes..."
      stop_hexo || true
      start_hexo_bg || true
    else
      echo "[hexo-container] No changes found."
    fi
  fi
done) &

# Initial build
echo "[hexo-container] Running initial build..."
${BUILD_CMD} || true

echo "[hexo-container] Starting Hexo server (managed background)..."
start_hexo_bg
# Keep container alive by waiting on the Hexo server PID
if [ -f /tmp/hexo-server.pid ]; then
  wait "$(cat /tmp/hexo-server.pid)"
else
  # Fallback: tail the log if PID missing
  tail -f /tmp/hexo-server.log
fi
