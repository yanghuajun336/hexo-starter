#!/usr/bin/env node
const http = require('http');
const crypto = require('crypto');
const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');

const PORT = process.env.PORT || process.env.WEBHOOK_PORT || 9001;
const SECRET = process.env.WEBHOOK_SECRET || '';
const REPO_BRANCH = process.env.REPO_BRANCH || 'main';
const BUILD_CMD = process.env.BUILD_CMD || 'npx hexo generate';
const WORKDIR = process.env.WORKDIR || '/var/www/hexo';

console.log('[webhook] ============================================');
console.log('[webhook] Webhook Server Configuration');
console.log(`[webhook] Port: ${PORT}`);
console. log(`[webhook] Secret configured: ${SECRET ?  'YES' : 'NO (Warning: No signature verification! )'}`);
console.log(`[webhook] Target branch: ${REPO_BRANCH}`);
console.log(`[webhook] Build command: ${BUILD_CMD}`);
console.log(`[webhook] Working directory: ${WORKDIR}`);
console.log('[webhook] ============================================');

// 验证签名（支持 GitHub 的 sha1 和 sha256）
function verifySignature(payload, signature) {
  if (!SECRET) {
    console. log('[webhook] Warning: No secret configured, skipping signature verification');
    return true;
  }
  
  if (!signature) {
    return false;
  }
  
  // 支持 sha1 (GitHub 传统) 和 sha256 (GitHub 推荐)
  let algorithm = 'sha1';
  let expected = signature;
  
  if (signature.startsWith('sha256=')) {
    algorithm = 'sha256';
    expected = signature.substring(7);
  } else if (signature.startsWith('sha1=')) {
    expected = signature.substring(5);
  }
  
  const hmac = crypto.createHmac(algorithm, SECRET);
  const digest = hmac.update(payload).digest('hex');
  
  try {
    return crypto.timingSafeEqual(
      Buffer.from(digest, 'utf8'),
      Buffer.from(expected, 'utf8')
    );
  } catch (e) {
    return false;
  }
}

// 检测正确的分支
function detectBranch(callback) {
  const checkCmd = `
    git fetch origin --prune 2>&1 || true;
    if git show-ref --verify --quiet "refs/remotes/origin/${REPO_BRANCH}" 2>/dev/null; then
      echo "${REPO_BRANCH}";
    else
      git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || echo "${REPO_BRANCH}";
    fi
  `. trim();
  
  exec(checkCmd, { cwd: WORKDIR, shell: '/bin/bash' }, (err, stdout, stderr) => {
    const branch = (stdout || '').trim() || REPO_BRANCH;
    callback(branch);
  });
}

// 执行重建
function rebuild() {
  const startTime = Date.now();
  console.log('[webhook] ============================================');
  console.log(`[webhook] Rebuild triggered at ${new Date().toISOString()}`);
  console. log('[webhook] ============================================');
  
  detectBranch((branch) => {
    console.log(`[webhook] Using branch: ${branch}`);
    
    const fullCmd = `
      set -e;
      echo "[webhook] Resetting to origin/${branch}... ";
      git reset --hard origin/${branch} || git pull origin ${branch} || exit 1;
      echo "[webhook] Installing dependencies...";
      npm install --no-audit --no-fund --loglevel=error || true;
      echo "[webhook] Running build command...";
      ${BUILD_CMD} || exit 1;
      echo "[webhook] Build completed successfully! ";
    `.trim();
    
    exec(fullCmd, {
      cwd: WORKDIR,
      shell: '/bin/bash',
      maxBuffer: 10 * 1024 * 1024 // 10MB buffer
    }, (err, stdout, stderr) => {
      const duration = ((Date.now() - startTime) / 1000).toFixed(2);
      
      if (stdout) {
        console.log('[webhook] STDOUT:', stdout);
      }
      if (stderr) {
        console.error('[webhook] STDERR:', stderr);
      }
      
      if (err) {
        console. error('[webhook] ❌ Rebuild FAILED! ');
        console.error('[webhook] Error:', err. message);
        console.error(`[webhook] Duration: ${duration}s`);
        console.log('[webhook] ============================================');
      } else {
        console.log('[webhook] ✅ Rebuild SUCCESS!');
        console.log(`[webhook] Duration: ${duration}s`);
        console.log('[webhook] Nginx will serve the updated public/ directory');
        console.log('[webhook] ============================================');
      }
    });
  });
}

// HTTP 服务器
const server = http.createServer((req, res) => {
  const requestTime = new Date().toISOString();
  
  // 健康检查端点
  if (req.method === 'GET' && req. url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      status: 'ok',
      service: 'hexo-webhook',
      uptime: process.uptime(),
      timestamp: requestTime
    }));
    return;
  }
  
  // Webhook 端点
  if (req.method === 'POST' && (req.url === '/webhook' || req.url === '/payload')) {
    console.log(`[webhook] Received ${req.method} ${req.url} from ${req.socket.remoteAddress}`);
    
    const chunks = [];
    
    req.on('data', chunk => {
      chunks.push(chunk);
    });
    
    req.on('end', () => {
      const body = Buffer.concat(chunks);
      const signature = req.headers['x-hub-signature-256'] || req.headers['x-hub-signature'] || '';
      
      // 验证签名
      if (!verifySignature(body, signature)) {
        console.error('[webhook] ❌ Invalid signature!');
        res.writeHead(401, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Invalid signature' }));
        return;
      }
      
      // 解析 payload
      let payload;
      try {
        payload = JSON.parse(body. toString('utf8'));
      } catch (e) {
        console.error('[webhook] ❌ Invalid JSON payload:', e.message);
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Invalid JSON' }));
        return;
      }
      
      // 记录事件信息
      const event = req.headers['x-github-event'] || req.headers['x-gitee-event'] || 'unknown';
      console.log(`[webhook] Event: ${event}`);
      console.log(`[webhook] Ref: ${payload.ref || 'N/A'}`);
      console.log(`[webhook] Repository: ${payload.repository?. full_name || 'N/A'}`);
      
      // 检查是否是目标分支（如果提供了 ref）
      if (payload.ref) {
        const targetRef = `refs/heads/${REPO_BRANCH}`;
        if (payload.ref !== targetRef) {
          console.log(`[webhook] ⚠️  Ignoring push to ${payload.ref} (watching ${targetRef})`);
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res. end(JSON.stringify({ status: 'ignored', reason: 'branch mismatch' }));
          return;
        }
      }
      
      // 接受请求并触发重建
      res.writeHead(202, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        status: 'accepted',
        message: 'Rebuild triggered',
        timestamp: requestTime
      }));
      
      // 异步执行重建（避免阻塞响应）
      setImmediate(() => rebuild());
    });
    
    return;
  }
  
  // 其他请求返回 404
  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON. stringify({
    error: 'Not Found',
    endpoints: {
      webhook: 'POST /webhook',
      health: 'GET /health'
    }
  }));
});

// 错误处理
server.on('error', (err) => {
  console.error('[webhook] Server error:', err);
  process.exit(1);
});

// 优雅关闭
process. on('SIGTERM', () => {
  console.log('[webhook] Received SIGTERM, shutting down gracefully...');
  server.close(() => {
    console.log('[webhook] Server closed');
    process.exit(0);
  });
});

process.on('SIGINT', () => {
  console.log('[webhook] Received SIGINT, shutting down gracefully...');
  server.close(() => {
    console.log('[webhook] Server closed');
    process.exit(0);
  });
});

// 启动服务器
server.listen(PORT, '0.0.0.0', () => {
  console.log(`[webhook] ✅ Server listening on 0.0.0.0:${PORT}`);
  console.log(`[webhook] Webhook URL: http://0.0.0.0:${PORT}/webhook`);
  console.log(`[webhook] Health check: http://0.0.0.0:${PORT}/health`);
  console.log('[webhook] ============================================');
});