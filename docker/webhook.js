#!/usr/bin/env node
const http = require('http');
const crypto = require('crypto');
const { exec } = require('child_process');

const port = process.env.WEBHOOK_PORT || 9001;
const secret = process.env.WEBHOOK_SECRET || '';
let branch = process.env.REPO_BRANCH || 'main';
const buildCmd = process.env.BUILD_CMD || 'npx hexo generate';
// In Nginx architecture, we only generate; no server restart needed

function verifySignature(buf, signature) {
  if (!secret) return true;
  const hmac = crypto.createHmac('sha1', secret).update(buf).digest('hex');
  return ('sha1=' + hmac) === (signature || '');
}

const server = http.createServer((req, res) => {
  if (req.method !== 'POST' || req.url !== '/payload') {
    res.writeHead(404, {'Content-Type':'text/plain'});
    res.end('Not found');
    return;
  }
  const chunks = [];
  req.on('data', chunk => chunks.push(chunk));
  req.on('end', () => {
    const body = Buffer.concat(chunks);
    const sig = req.headers['x-hub-signature'] || '';
    if (!verifySignature(body, sig)) {
      res.writeHead(401, {'Content-Type':'text/plain'});
      res.end('Invalid signature');
      console.error('[webhook] Invalid signature');
      return;
    }
    res.writeHead(202, {'Content-Type':'text/plain'});
    res.end('Accepted');
    console.log('[webhook] Received payload, triggering pull & build...');

    // Determine branch to use: prefer configured branch; if missing, fallback to origin/HEAD
    const detectBranch = `git fetch origin || true; BH=${branch}; HEADREF=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's/^origin\///' || true); git show-ref --verify --quiet "refs/remotes/origin/${branch}" || BH="$HEADREF"; echo "[webhook] Using branch: $BH"; git reset --hard origin/$BH || git pull origin $BH || true`;
    const cmd = `${detectBranch} && npm install --no-audit --no-fund || true && ${buildCmd}`;
    exec(cmd, {cwd: process.cwd(), env: process.env, shell: '/bin/bash'}, (err, stdout, stderr) => {
      if (err) console.error('[webhook] error:', err);
      if (stdout) console.log('[webhook] stdout:', stdout);
      if (stderr) console.error('[webhook] stderr:', stderr);
      console.log('[webhook] Regeneration complete; Nginx serves updated public/.');
    });
  });
});

server.listen(port, '0.0.0.0', () => console.log(`[webhook] Listening on 0.0.0.0:${port}`));
