const CDP = require('chrome-remote-interface');
const http = require('http');
const fs = require('fs');
const path = require('path');

const CDP_PORT = 9223;
const BRIDGE_PORT = 3000;

// ─── DevServer URL → Absolute Path ───────────────────────────
// 读取 config.ini [DevServer] 端口→项目根映射，把 CDP 拿到的 dev-server 根相对 URL
// （如 http://localhost:9999/src/xxx.vue）还原为磁盘绝对路径，使扩展链路打开更精准
const CONFIG_INI = path.join(__dirname, '..', 'config.ini');

function loadDevServerMap() {
    const map = {};
    try {
        const text = fs.readFileSync(CONFIG_INI, 'utf8');
        let inSection = false;
        for (const raw of text.split(/\r?\n/)) {
            const line = raw.trim();
            if (!line || line.startsWith(';') || line.startsWith('#')) continue;
            if (line.startsWith('[') && line.endsWith(']')) {
                inSection = line.slice(1, -1).toLowerCase() === 'devserver';
                continue;
            }
            if (!inSection) continue;
            const eq = line.indexOf('=');
            if (eq <= 0) continue;
            const key = line.slice(0, eq).trim();
            const val = line.slice(eq + 1).trim();
            if (key && val) map[key] = val;
        }
    } catch { /* config.ini 缺失时保持空表 */ }
    return map;
}

function resolveAbsolutePath(fileUrl) {
    if (!fileUrl) return '';
    const url = String(fileUrl).trim();
    try {
        // file:// → 直接取 pathname
        if (url.startsWith('file://')) {
            let p = decodeURIComponent(new URL(url).pathname || '');
            if (/^\/[A-Za-z]:\//.test(p)) p = p.slice(1);
            return p.replace(/\//g, '\\');
        }
        // dev-server 根相对 URL：按端口查 [DevServer] 项目根后拼接
        const m = url.match(/^https?:\/\/(?:localhost|127\.0\.0\.1):(\d+)\/(.+)$/);
        if (m) {
            const rel = decodeURIComponent(m[2]).split(/[?#]/)[0];
            const root = loadDevServerMap()[m[1]];
            if (root) return path.join(root, rel.replace(/\//g, path.sep));
        }
        // 已是绝对盘符路径
        if (/^[A-Za-z]:[\\/]/.test(url)) return path.normalize(url);
    } catch { }
    return '';
}

// 统一输出 line-number 响应：补充 absolutePath 字段
function sendLineNumber(res, data) {
    data.absolutePath = resolveAbsolutePath(data.fileUrl);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(data));
}

// Cache last successful result; auto-restart after consecutive failures
let lastResult = null;
let consecutiveFailures = 0;
const MAX_FAILURES = 3;

// ─── CDP: Get Cursor Position from DevTools Sources Panel ───────

async function getDevToolsLineNumber() {
    let client;
    try {
        const targets = await CDP.List({ port: CDP_PORT });
        const devtoolsTarget = targets.find(t => t.type === 'devtools' || t.url.includes('devtools://'));
        if (!devtoolsTarget) return { lineNumber: 0, columnNumber: 0, fileUrl: '' };

        client = await CDP({ port: CDP_PORT, target: devtoolsTarget });
        const { Runtime } = client;

        const expression = `
            (() => {
                const panel = UI.panels && UI.panels.sources;
                if (!panel) return { lineNumber: 0, columnNumber: 0, fileUrl: '' };

                const svRaw = panel.sourcesViewInternal || panel.sourcesView || panel._sourcesView || panel._sourcesViewInternal;
                const sv = (typeof svRaw === 'function') ? svRaw.call(panel) : svRaw;
                if (!sv || !sv.currentSourceFrame) return { lineNumber: 0, columnNumber: 0, fileUrl: '' };

                const frame = sv.currentSourceFrame();
                if (!frame || !frame.textEditorInternal) return { lineNumber: 0, columnNumber: 0, fileUrl: '' };

                let fileUrl = '';
                try {
                    const usc = (typeof frame.uiSourceCode === 'function') ? frame.uiSourceCode() : frame.uiSourceCode;
                    if (usc) fileUrl = (typeof usc.url === 'function') ? usc.url() : (usc._url || usc.url || '');
                } catch(e) {}

                const state = frame.textEditorInternal.state;
                const sel = state && state.selection;
                const main = sel && (sel.main || (sel.ranges && sel.ranges[sel.mainIndex || 0]));
                const from = main ? main.from : null;
                const doc = state && state.doc;

                if (doc && typeof from === 'number' && doc.lineAt) {
                    const info = doc.lineAt(from);
                    return { lineNumber: info.number, columnNumber: from - info.from + 1, fileUrl };
                }
                return { lineNumber: 0, columnNumber: 0, fileUrl };
            })()
        `;

        const result = await Runtime.evaluate({ expression, returnByValue: true });
        const val = result?.result?.value;
        if (val && val.lineNumber > 0) lastResult = { ...val };
        return val || { lineNumber: 0, columnNumber: 0, fileUrl: '' };
    } catch (err) {
        return { lineNumber: 0, columnNumber: 0, fileUrl: '', error: err.message };
    } finally {
        if (client) await client.close();
    }
}

// ─── HTTP Server ────────────────────────────────────────────────

const server = http.createServer(async (req, res) => {
    const pathname = new URL(req.url, `http://127.0.0.1:${BRIDGE_PORT}`).pathname;

    if (pathname === '/health' || pathname === '/health/') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: true, pid: process.pid }));
        return;
    }

    if (pathname === '/line-number' || pathname === '/line-number/') {
        const data = await getDevToolsLineNumber();

        if (data.lineNumber > 0) {
            consecutiveFailures = 0;
            sendLineNumber(res, data);
            return;
        }

        // CDP returned 0 → use cache, auto-restart after MAX_FAILURES
        consecutiveFailures++;
        if (consecutiveFailures >= MAX_FAILURES) {
            console.log(`[bridge] Auto-restart after ${consecutiveFailures} failures`);
            const fallback = lastResult
                ? { ...lastResult, _cached: true, _restarting: true }
                : { lineNumber: 0, columnNumber: 0, fileUrl: '', _restarting: true };
            sendLineNumber(res, fallback);
            setTimeout(() => process.exit(0), 100);
            return;
        }

        if (lastResult) {
            sendLineNumber(res, { ...lastResult, _cached: true });
            return;
        }

        sendLineNumber(res, data);
        return;
    }

    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Not found' }));
});

// ─── Startup ────────────────────────────────────────────────────

server.on('error', async (err) => {
    if (err?.code === 'EADDRINUSE') {
        // Check if an existing bridge is healthy
        try {
            await new Promise((resolve) => {
                const req = http.get(`http://127.0.0.1:${BRIDGE_PORT}/health`, (res) => {
                    resolve(res.statusCode === 200);
                    res.resume();
                });
                req.setTimeout(800, () => { req.destroy(); resolve(false); });
                req.on('error', () => resolve(false));
            }).then(healthy => {
                if (healthy) { console.log(`Bridge already running`); process.exit(0); }
                else { console.error(`Port ${BRIDGE_PORT} in use`); process.exit(1); }
            });
        } catch { process.exit(1); }
        return;
    }
    throw err;
});

server.listen(BRIDGE_PORT, () => {
    console.log(`Bridge running at http://localhost:${BRIDGE_PORT}`);
});
