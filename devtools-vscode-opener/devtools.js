// DevTools panel → IDE file opener
const CONFIG = {
  BRIDGE_URL: 'http://localhost:3000/line-number',
  BRIDGE_START: 'http://localhost:3000/start-bridge',
  TIMEOUT_MS: 1200
};

const tabId = chrome.devtools.inspectedWindow.tabId;
let port = null;
const state = { lastResource: null, lastLine: 1, lastCol: 1 };

// ─── Port Connection ────────────────────────────────────────────

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

// ─── URL → Path Conversion ─────────────────────────────────────

function decodeSafe(s) { try { return decodeURIComponent(s); } catch { return s; } }

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
    let p = decodeSafe(u.pathname || '');
    if (p.startsWith('/@fs/')) return p.slice('/@fs/'.length).replace(/\\/g, '/');
    return p.replace(/^[/]/, '').replace(/\\/g, '/');
  } catch { return ''; }
}

// ─── CDP Bridge ─────────────────────────────────────────────────

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function fetchWithTimeout(url, timeoutMs) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try { return await fetch(url, { method: 'GET', cache: 'no-store', signal: controller.signal }); }
  finally { clearTimeout(timer); }
}

async function ensureBridgeRunning() {
  const ms = CONFIG.TIMEOUT_MS;
  try {
    const r = await fetchWithTimeout(CONFIG.BRIDGE_URL, ms);
    await r.text();
    if (r.ok) return true;
  } catch {}
  if (CONFIG.BRIDGE_START) {
    try { const r = await fetchWithTimeout(CONFIG.BRIDGE_START, ms); await r.text(); } catch {}
  }
  for (let i = 0; i < 6; i++) {
    try {
      const r = await fetchWithTimeout(CONFIG.BRIDGE_URL, ms);
      await r.text();
      if (r.ok) return true;
    } catch {}
    await sleep(150);
  }
  return false;
}

async function fetchLineColFromBridge() {
  if (!(await ensureBridgeRunning())) return null;
  try {
    const r = await fetchWithTimeout(CONFIG.BRIDGE_URL, CONFIG.TIMEOUT_MS);
    if (!r.ok) return null;
    const json = await r.json();

    const line = Number(json?.lineNumber ?? json?.line);
    const col = Number(json?.columnNumber ?? json?.col);

    let filePath = '';
    const rawUrl = json?.fileUrl || '';
    if (rawUrl && rawUrl.startsWith('file://')) {
      try {
        let p = decodeSafe(new URL(rawUrl).pathname || '');
        if (/^[/][A-Za-z]:[/]/.test(p)) p = p.slice(1);
        filePath = p.replace(/\\/g, '/');
      } catch {}
    }

    return {
      line: Number.isFinite(line) && line >= 1 ? line : null,
      col: Number.isFinite(col) && col >= 1 ? col : null,
      filePath: filePath || null
    };
  } catch { return null; }
}

// ─── Open in IDE ────────────────────────────────────────────────

async function openInIde(resource, target) {
  const fallbackPath = toOpenPath(resource.url);
  const bridge = await fetchLineColFromBridge();

  const line = bridge?.line || state.lastLine || 1;
  const col = bridge?.col || state.lastCol || 1;
  const openPath = bridge?.filePath || fallbackPath;
  if (!openPath) return;

  const action = target === 'qoder' ? 'OPEN_QODER' : 'OPEN_VSCODE';
  try { port.postMessage({ action, tabId, path: openPath, line, col }); } catch {}
}

// ─── State Tracking (fallback when bridge unavailable) ──────────

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
