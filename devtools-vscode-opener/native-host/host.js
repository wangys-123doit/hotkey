#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const os = require('os');

// Debug: log when native host is invoked
fs.appendFileSync(path.join(os.tmpdir(), 'native-host-debug.log'),
  `[${new Date().toISOString()}] Native host started\n`);

// ─── Path Resolution ────────────────────────────────────────────

function resolveFilePath(inputPath) {
  const p = String(inputPath || '').replace(/\\/g, '/').trim();
  if (!p) return '';
  if (path.isAbsolute(p) || /^[A-Za-z]:[/\\]/.test(p)) return path.normalize(p);

  // BFS: search common project dirs + 1-level subdirs (max depth 2)
  const candidates = new Set([process.cwd()]);
  const home = process.env.USERPROFILE || process.env.HOME || '';
  if (home) {
    for (const sub of ['Desktop', 'Documents', 'code', 'workspace', 'projects', 'repos']) {
      const dir = path.join(home, sub);
      if (fs.existsSync(dir)) candidates.add(dir);
    }
  }
  if (process.platform === 'win32') {
    for (let c = 65; c <= 90; c++) {
      for (const sub of ['code', 'workspace', 'projects']) {
        const dir = `${String.fromCharCode(c)}:\\${sub}`;
        if (fs.existsSync(dir)) candidates.add(dir);
      }
    }
  }

  const rel = p.replace(/^\/+/, '');
  const skip = new Set(['.git', 'node_modules', 'dist', 'build', 'out', 'coverage', '.vscode']);
  for (const dir of candidates) {
    if (fs.existsSync(path.join(dir, rel))) return path.normalize(path.join(dir, rel));
    try {
      for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        if (entry.isDirectory() && !skip.has(entry.name)) {
          const full = path.join(dir, entry.name, rel);
          if (fs.existsSync(full)) return path.normalize(full);
        }
      }
    } catch {}
  }
  return '';
}

function pickQoderCmd() {
  const opts = [
    process.env.QODER_PATH,
    'C:/Program Files/Qoder/bin/qoder.cmd',
    'C:/Program Files (x86)/Qoder/bin/qoder.cmd',
    path.join(process.env.LOCALAPPDATA || '', 'Programs/Qoder/bin/qoder.cmd'),
    path.join(process.env.LOCALAPPDATA || '', 'Programs/qoder/bin/qoder.cmd'),
    'D:/Software/Qoder/bin/qoder.cmd'
  ];
  for (const o of opts) if (o && fs.existsSync(o)) return o;
  if (process.platform === 'win32') {
    for (let c = 65; c <= 90; c++) {
      const f = `${String.fromCharCode(c)}:/Software/Qoder/bin/qoder.cmd`;
      if (fs.existsSync(f)) return f;
    }
  }
  return 'qoder.cmd';
}

function pickCodeCmd() {
  for (const o of [process.env.VSCODE_PATH, 'C:/Program Files/Microsoft VS Code/bin/code.cmd', 'C:/Program Files (x86)/Microsoft VS Code/bin/code.cmd']) {
    if (o && fs.existsSync(o)) return o;
  }
  return 'code.cmd';
}

// ─── Open File (CLI --goto: reliable, no GUI automation) ─────────

function openFile(file, line, col, ide) {
  const debugLog = (s) => fs.appendFileSync(path.join(os.tmpdir(), 'native-host-debug.log'),
    `[${new Date().toISOString()}] ${s}\n`);
  debugLog(`openFile input: file=${file}, line=${line}, col=${col}, ide=${ide}`);

  const resolved = resolveFilePath(file);
  debugLog(`resolveFilePath result: ${resolved}`);
  if (!resolved) throw new Error(`cannot resolve: ${file}`);

  const lineNum = Math.max(1, Number(line) || 1);
  const colNum = Math.max(1, Number(col) || 1);
  const gotoArg = `${resolved}:${lineNum}:${colNum}`;

  // Pick CLI command based on IDE type
  const cmd = ide === 'qoder' ? pickQoderCmd() : pickCodeCmd();
  debugLog(`Spawning: ${cmd} --goto ${gotoArg}`);

  // CLI --goto handles: open file, jump to line:col, reuse existing window, activate window
  const child = spawn(cmd, ['--goto', gotoArg], {
    detached: true,
    stdio: 'ignore',
    windowsHide: true
  });
  child.unref();
  debugLog(`Spawned PID: ${child.pid}`);
}

// ─── Native Messaging Protocol ──────────────────────────────────

function readNative(cb) {
  let buf = Buffer.alloc(0);
  process.stdin.on('data', d => {
    buf = Buffer.concat([buf, d]);
    if (buf.length >= 4) {
      const len = buf.readUInt32LE(0);
      if (buf.length >= 4 + len) {
        try { cb(null, JSON.parse(buf.slice(4, 4 + len).toString('utf8'))); }
        catch (e) { cb(e); }
      }
    }
  });
}

function sendNative(obj) {
  const b = Buffer.from(JSON.stringify(obj));
  const h = Buffer.alloc(4);
  h.writeUInt32LE(b.length, 0);
  process.stdout.write(Buffer.concat([h, b]));
}

readNative((err, msg) => {
  const debugLog = (s) => fs.appendFileSync(path.join(os.tmpdir(), 'native-host-debug.log'),
    `[${new Date().toISOString()}] ${s}\n`);

  if (err) {
    debugLog(`Error reading message: ${err}`);
    return sendNative({ ok: false, error: String(err) });
  }
  debugLog(`Received message: ${JSON.stringify(msg)}`);

  if (!msg || msg.action !== 'open' || !msg.path) {
    debugLog(`Invalid message, rejecting`);
    return sendNative({ ok: false, error: 'invalid message' });
  }
  const ide = msg.ide === 'qoder' ? 'qoder' : 'vscode';
  debugLog(`Opening in ${ide}: ${msg.path}:${msg.line}:${msg.column}`);

  try {
    openFile(msg.path, msg.line, msg.column, ide);
    debugLog(`openFile completed successfully`);
    sendNative({ ok: true, ide, target: `${msg.path}:${msg.line || 1}:${msg.column || 1}` });
  } catch (e) {
    debugLog(`openFile error: ${e?.message}`);
    sendNative({ ok: false, ide, error: e?.message });
  }
});
