#!/usr/bin/env bash
set -e

echo "[hexo-container] Starting with REPO_URL=${REPO_URL:-<none>}"

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

# ========== Theme: Butterfly auto-setup (only when theme is 'landscape') ==========
echo "[hexo-container] Checking project theme to decide whether to install Butterfly..."

# Determine current theme by scanning all _config*.yml files.
# If any config file specifies a non-default theme (not 'landscape'),
# we should skip installing Butterfly to avoid overwriting the user's choice.
skip_install="false"
found_any="false"
current_theme=""
nondefault_theme=""
nondefault_file=""
for cfg in _config*.yml; do
  if [ -f "${cfg}" ]; then
    val=$(awk -F': ' '/^theme:/ {gsub(/\r/, "", $2); print $2; exit}' "${cfg}" || true)
    if [ -n "${val}" ]; then
      found_any="true"
      # If any config sets a theme that is not the default 'landscape', skip installation
      if [ "${val}" != "landscape" ]; then
        skip_install="true"
        nondefault_theme="${val}"
        nondefault_file="${cfg}"
        current_theme="${val}"
        break
      else
        # record that we saw the default explicitly
        current_theme="${val}"
      fi
    fi
  fi
done

if [ "${skip_install}" = "true" ]; then
  echo "[hexo-container] Found non-default theme '${nondefault_theme}' in ${nondefault_file} — skipping Butterfly installation to avoid overwriting user's theme."
else
  if [ "${found_any}" = "true" ]; then
    echo "[hexo-container] No non-default theme found; proceeding since theme is '${current_theme:-<none>}'"
  else
    echo "[hexo-container] No theme found in any _config*.yml (treating as not set)"
  fi

  # Proceed with installation because no explicit non-default theme was found
  echo "[hexo-container] Proceeding to install Butterfly theme (safe)."
  # mkdir -p themes

  if [ -d "themes/butterfly" ]; then
    echo "[hexo-container] 'themes/butterfly' already exists — skipping clone."
  else
    echo "[hexo-container] Cloning butterfly theme into themes/butterfly..."
    git clone -b master https://github.com/jerryc127/hexo-theme-butterfly.git themes/butterfly || true
  fi

  # Copy theme's default config to project's _config.butterfly.yml if it doesn't exist
  if [ ! -f _config.butterfly.yml ] && [ -f themes/butterfly/_config.yml ]; then
    cp themes/butterfly/_config.yml _config.butterfly.yml
    echo "[hexo-container] Created _config.butterfly.yml from theme default."
  fi

  # Back up and set theme to butterfly
  if [ -f _config.yml ]; then
    echo "[hexo-container] Backing up existing _config.yml to _config.yml.bak and setting theme: butterfly"
    cp _config.yml _config.yml.bak || true
    if grep -qE '^theme:' _config.yml 2>/dev/null; then
      sed -i 's/^theme:.*/theme: butterfly/' _config.yml || true
    else
      echo "theme: butterfly" >> _config.yml
    fi
  else
    echo "[hexo-container] No _config.yml found — creating one with theme: butterfly"
    echo "theme: butterfly" > _config.yml
  fi

  # Renderers are preinstalled in the image at build time; no runtime install needed.
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
    else
      echo "[hexo-container] No changes found."
    fi
  fi
done) &

# Initial build
echo "[hexo-container] Running initial build..."
${BUILD_CMD} || true

echo "[hexo-container] Starting Hexo server (foreground)..."
exec sh -c "${START_CMD}"
