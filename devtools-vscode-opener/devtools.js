// DevTools panel → IDE file opener
const CONFIG = {
  SEARCH_KEY: 'localhost:3000',
  AHK_LINE_URL: 'http://localhost:3000/line-number',
  AHK_START_URL: 'http://localhost:3000/start-bridge',
  AHK_TIMEOUT_MS: 1200
};

const tabId = chrome.devtools.inspectedWindow.tabId;
let port = null;
const state = { lastResource: null, lastLine: 1, lastCol: 1 };

function connectPort() {
  if (port) { try { port.disconnect(); } catch {} port = null; }
  try { port = chrome.runtime.connect({ name: 'devtools-vscode-opener' }); }
  catch { setTimeout(connectPort, 1000); return; }
  port.onMessage.addListener((msg) => {
    if (msg?.action === 'TRIGGER_OPEN') {
      const res = state.lastResource;
      if (res?.url) openInIde(res, msg.target || 'vscode');
    }
  });
  port.onDisconnect.addListener(() => { port = null; setTimeout(connectPort, 1000); });
  port.postMessage({ action: 'INIT', tabId });
}

function decodeSafe(s) { try { return decodeURIComponent(s); } catch { return s; } }

function isAllowedUrl(u, raw) {
  const key = (CONFIG.SEARCH_KEY || '').trim();
  if (!key) return true;
  const noProto = key.replace(/^https?:\/\//i, '');
  const hostPort = noProto.split('/')[0] || '';
  const hostOnly = hostPort.split(':')[0];
  if (hostOnly && u.hostname === hostOnly) return true;
  if (hostPort && u.host === hostPort) return true;
  return u.href.includes(key) || raw.includes(key);
}

function toOpenPath(url) {
  if (!url) return '';
  const raw = decodeSafe(url);
  if (raw.startsWith('file://')) {
    let p = decodeSafe(new URL(raw).pathname || '');
    if (/^[/][A-Za-z]:[/]/.test(p)) p = p.slice(1);
    return p.replace(/\\/g, '/');
  }
  if (/^[a-zA-Z]+:[/][/]/.test(raw) && !raw.startsWith('http://') && !raw.startsWith('https://')) {
    const segs = raw.replace(/^[a-zA-Z]+:[/][/]/, '').split('/').filter(Boolean);
    return (segs.length > 1 ? segs.slice(1) : segs).join('/').replace(/\\/g, '/');
  }
  try {
    const u = new URL(raw);
    if (!isAllowedUrl(u, raw)) return '';
    let p = decodeSafe(u.pathname || '');
    if (p.startsWith('/@fs/')) return p.slice('/@fs/'.length).replace(/\\/g, '/');
    return p.replace(/^[/]/, '').replace(/\\/g, '/');
  } catch { return ''; }
}

// ─── AHK Bridge (CDP → DevTools 内部光标位置) ─────────────────

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function fetchWithTimeout(url, timeoutMs) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try { return await fetch(url, { method: 'GET', cache: 'no-store', signal: controller.signal }); }
  finally { clearTimeout(timer); }
}

async function ensureBridgeRunning() {
  const lineUrl = (CONFIG.AHK_LINE_URL || '').trim();
  if (!lineUrl) return false;
  const ms = Number(CONFIG.AHK_TIMEOUT_MS) || 1200;
  try {
    const r = await fetchWithTimeout(lineUrl, ms);
    await r.text();
    if (r.ok) return true;
  } catch {}
  const startUrl = (CONFIG.AHK_START_URL || '').trim();
  if (startUrl) {
    try { const r = await fetchWithTimeout(startUrl, ms); await r.text(); } catch {}
  }
  for (let i = 0; i < 6; i++) {
    try {
      const r = await fetchWithTimeout(lineUrl, ms);
      await r.text();
      if (r.ok) return true;
    } catch {}
    await sleep(150);
  }
  return false;
}

async function fetchLineColFromBridge() {
  const url = (CONFIG.AHK_LINE_URL || '').trim();
  if (!url) return null;
  const ms = Number(CONFIG.AHK_TIMEOUT_MS) || 1200;
  if (!(await ensureBridgeRunning())) return null;
  try {
    const r = await fetchWithTimeout(url, ms);
    if (!r.ok) return null;
    const json = await r.json();
    const line = Number(json?.lineNumber ?? json?.line ?? json?.data?.lineNumber);
    const col = Number(json?.columnNumber ?? json?.column ?? json?.col ?? json?.data?.columnNumber);
    return {
      line: Number.isFinite(line) && line >= 1 ? line : null,
      col: Number.isFinite(col) && col >= 1 ? col : null
    };
  } catch { return null; }
}

// ─── Open in IDE ────────────────────────────────────────────────

async function openInIde(resource, target) {
  const openPath = toOpenPath(resource.url);
  if (!openPath) return;

  // 优先从 AHK Bridge 获取精确光标位置（CDP 直连 DevTools 内部）
  const bridge = await fetchLineColFromBridge();
  const line = bridge?.line || state.lastLine || 1;
  const col = bridge?.col || state.lastCol || 1;

  const action = target === 'qoder' ? 'OPEN_QODER' : 'OPEN_VSCODE';
  console.log('[IDE-Opener]', action, openPath, `L${line}:${col}`, bridge ? '(bridge)' : '(state)');
  try { port.postMessage({ action, tabId, path: openPath, line, col }); } catch {}
}

// 辅助：onSelectionChanged / setOpenResourceHandler 更新 state（作为 bridge 的 fallback）
function updateState(resource, lineNumber, columnNumber) {
  if (!resource) return;
  state.lastResource = resource;
  const ln = Math.floor(Number(lineNumber ?? resource?.lineNumber));
  if (Number.isFinite(ln) && ln >= 0) state.lastLine = ln + 1;
  const cn = Math.floor(Number(columnNumber ?? resource?.columnNumber));
  if (Number.isFinite(cn) && cn >= 0) state.lastCol = cn + 1;
}

if (chrome.devtools?.panels?.sources?.onSelectionChanged) {
  chrome.devtools.panels.sources.onSelectionChanged.addListener((resource, lineNumber, columnNumber) => {
    updateState(resource, lineNumber, columnNumber);
  });
}
if (chrome.devtools?.panels?.setOpenResourceHandler) {
  chrome.devtools.panels.setOpenResourceHandler((resource, lineNumber, columnNumber) => {
    updateState(resource, lineNumber, columnNumber);
  });
}

connectPort();
