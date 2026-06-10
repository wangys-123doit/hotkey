const CDP = require('chrome-remote-interface');
const http = require('http');

const CDP_PORT = 9223;
const BRIDGE_PORT = 3000;

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
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify(data));
            return;
        }

        // CDP returned 0 → use cache, auto-restart after MAX_FAILURES
        consecutiveFailures++;
        if (consecutiveFailures >= MAX_FAILURES) {
            console.log(`[bridge] Auto-restart after ${consecutiveFailures} failures`);
            const fallback = lastResult
                ? { ...lastResult, _cached: true, _restarting: true }
                : { lineNumber: 0, columnNumber: 0, fileUrl: '', _restarting: true };
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify(fallback));
            setTimeout(() => process.exit(0), 100);
            return;
        }

        if (lastResult) {
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ ...lastResult, _cached: true }));
            return;
        }

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(data));
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
