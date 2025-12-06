#!/usr/bin/env node
const http = require('http');
const crypto = require('crypto');
const { exec } = require('child_process');

const port = process.env.WEBHOOK_PORT || 9001;
const secret = process.env.WEBHOOK_SECRET || '';
const branch = process.env.REPO_BRANCH || 'main';
const buildCmd = process.env.BUILD_CMD || 'npx hexo generate';
const startCmd = process.env.START_CMD || 'npx hexo server -i 0.0.0.0 -p 4000';

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

    const cmd = `git fetch origin ${branch} || true && git reset --hard origin/${branch} || git pull origin ${branch} || true && npm install --no-audit --no-fund || true && ${buildCmd}`;
    exec(cmd, {cwd: process.cwd(), env: process.env, shell: '/bin/bash'}, (err, stdout, stderr) => {
      if (err) console.error('[webhook] error:', err);
      if (stdout) console.log('[webhook] stdout:', stdout);
      if (stderr) console.error('[webhook] stderr:', stderr);

      // After build, restart Hexo server to ensure config changes take effect
      // Hexo server does not hot-reload _config.yml; restart on each webhook.
      const restart = `pkill -f "hexo server" || true && nohup sh -c "${startCmd}" >/tmp/hexo-server.log 2>&1 &`;
      exec(restart, {cwd: process.cwd(), env: process.env, shell: '/bin/bash'}, (rErr, rOut, rErrOut) => {
        if (rErr) console.error('[webhook] restart error:', rErr);
        if (rOut) console.log('[webhook] restart stdout:', rOut);
        if (rErrOut) console.error('[webhook] restart stderr:', rErrOut);
        console.log('[webhook] Hexo server restarted to apply config changes.');
      });
    });
  });
});

server.listen(port, '0.0.0.0', () => console.log(`[webhook] Listening on 0.0.0.0:${port}`));
