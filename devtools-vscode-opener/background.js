const devtoolsPorts = new Map();
const NATIVE_HOST_NAME = 'com.tduck.vscode_opener';

function launchIdeViaNativeHost(filePath, line, col, ide, callback) {
  if (typeof callback !== 'function' || typeof filePath !== 'string' || !filePath.trim()) {
    if (typeof callback === 'function') callback(false, 'invalid params');
    return;
  }
  let port;
  try { port = chrome.runtime.connectNative(NATIVE_HOST_NAME); }
  catch (e) { callback(false, `native host unavailable: ${e?.message || 'unknown'}`); return; }

  let responded = false;
  const respond = (ok, detail) => {
    if (responded) return;
    responded = true;
    clearTimeout(timer);
    try { port.disconnect(); } catch {}
    callback(ok, detail);
  };

  port.onMessage.addListener((msg) => {
    if (msg?.ok) respond(true, `${filePath}:${line}`);
    else respond(false, msg?.error || 'native host error');
  });
  port.onDisconnect.addListener(() => {
    if (!responded) respond(false, chrome.runtime.lastError?.message || 'disconnected');
  });

  try {
    port.postMessage({ action: 'open', path: filePath, line: Math.max(1, Number(line) || 1), column: Math.max(1, Number(col) || 1), ide });
  } catch (e) { respond(false, `post failed: ${e?.message || 'unknown'}`); }

  const timer = setTimeout(() => respond(false, 'timeout (10s)'), 10000);
}

chrome.runtime.onConnect.addListener((port) => {
  if (port.name !== 'devtools-vscode-opener') return;

  port.onMessage.addListener((msg) => {
    if (msg?.action === 'INIT' && Number.isInteger(msg.tabId)) {
      devtoolsPorts.set(msg.tabId, port);
      return;
    }
    if (msg?.action === 'KEEPALIVE' && Number.isInteger(msg.tabId)) {
      devtoolsPorts.set(msg.tabId, port);
      try { port.postMessage({ action: 'PONG' }); } catch { devtoolsPorts.delete(msg.tabId); }
      return;
    }
    if (msg?.action === 'OPEN_VSCODE' || msg?.action === 'OPEN_QODER') {
      const targetPath = String(msg?.path || '').trim();
      const line = Number.isFinite(Number(msg?.line)) ? Number(msg.line) : 1;
      const col = Number.isFinite(Number(msg?.col)) ? Number(msg.col) : 1;
      const ide = msg.action === 'OPEN_QODER' ? 'qoder' : 'vscode';
      launchIdeViaNativeHost(targetPath, line, col, ide, (ok, detail) => {
        if (!ok) console.warn(`[IDE-Opener] ${ide} open failed:`, detail, targetPath, line);
      });
    }
  });

  port.onDisconnect.addListener(() => {
    for (const [tabId, p] of devtoolsPorts) {
      if (p === port) { devtoolsPorts.delete(tabId); break; }
    }
  });
});

chrome.commands.onCommand.addListener((command) => {
  const target = command === 'open-in-qoder' ? 'qoder' : command === 'open-in-vscode' ? 'vscode' : null;
  if (!target) return;
  chrome.tabs.query({ active: true, lastFocusedWindow: true }, (tabs) => {
    const activeTabId = tabs?.[0]?.id;
    if (!Number.isInteger(activeTabId)) return;
    const p = devtoolsPorts.get(activeTabId);
    if (p) { try { p.postMessage({ action: 'TRIGGER_OPEN', target }); } catch { devtoolsPorts.delete(activeTabId); } return; }
    if (devtoolsPorts.size === 1) {
      const [fbId, fbPort] = [...devtoolsPorts][0];
      try { fbPort.postMessage({ action: 'TRIGGER_OPEN', target }); } catch { devtoolsPorts.delete(fbId); }
    }
  });
});
