FROM node:20-bullseye-slim

ENV REPO_URL="" \
	REPO_BRANCH="main" \
	PULL_INTERVAL="60" \
	HEXO_PORT="4000" \
	WEBHOOK_PORT="9001" \
	WEBHOOK_SECRET="" \
	GIT_USER="hexo" \
	GIT_EMAIL="hexo@example.com" \
	START_CMD="npx hexo server -i 0.0.0.0 -p $HEXO_PORT" \
	BUILD_CMD="npx hexo generate"

WORKDIR /var/www/hexo

RUN apt-get update && apt-get install -y --no-install-recommends \
	git \
	openssh-client \
	ca-certificates \
	curl \
	build-essential \
	python3 \
	&& rm -rf /var/lib/apt/lists/* \
	&& npm set progress=false \
	&& npm install -g hexo-cli@6 hexo-renderer-pug hexo-renderer-stylus >/dev/null 2>&1 || true

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY webhook.js /usr/local/bin/webhook.js
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE ${HEXO_PORT}
EXPOSE ${WEBHOOK_PORT}

CMD ["/usr/local/bin/entrypoint.sh"]
