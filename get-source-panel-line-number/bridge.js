const CDP = require('chrome-remote-interface');
const http = require('http');

const CDP_PORT = 9223;
const BRIDGE_PORT = 3000;

/**
 * 核心逻辑：从 DevTools 内部上下文中获取行号
 * 注意：DevTools 本身也是一个 Web 页面，需要找到其对应的 Target
 */
async function getDevToolsLineNumber() {
    let client;
    try {
        const targets = await CDP.List({ port: CDP_PORT });
        const devtoolsTarget = targets.find(t => t.type === 'devtools' || t.url.includes('devtools://'));

        if (!devtoolsTarget) return { error: 'DevTools not open' };

        client = await CDP({ port: CDP_PORT, target: devtoolsTarget });
        const { Runtime } = client;

        const expression = `
            (() => {
                const panel = UI.panels && UI.panels.sources;
                if (!panel) return 0;

                const sourcesViewRaw = panel.sourcesViewInternal || panel.sourcesView || panel._sourcesView || panel._sourcesViewInternal;
                const sourcesView = (typeof sourcesViewRaw === 'function')
                    ? sourcesViewRaw.call(panel)
                    : sourcesViewRaw;
                if (!sourcesView || !sourcesView.currentSourceFrame) return 0;

                const frame = sourcesView.currentSourceFrame();
                if (!frame || !frame.textEditorInternal) return 0;

                const state = frame.textEditorInternal.state;
                const sel = state && state.selection;
                const main = sel && (sel.main || (sel.ranges && sel.ranges[sel.mainIndex || 0]));
                const from = main ? main.from : null;
                const doc = state && state.doc;

                if (doc && typeof from === 'number' && doc.lineAt) {
                    return doc.lineAt(from).number;
                }

                return 0;
            })()
        `;

        const result = await Runtime.evaluate({ expression, returnByValue: true });
        if (!result || !result.result) {
            return { error: 'No eval result' };
        }

        if (result.result.value !== undefined) {
            return { lineNumber: result.result.value };
        }

        return { error: 'Unexpected eval result' };
    } catch (err) {
        return { error: (err && err.message) ? err.message : 'Unknown error' };
    } finally {
        if (client) await client.close();
    }
}

function probeExistingBridge(port) {
    return new Promise((resolve) => {
        const req = http.get(`http://127.0.0.1:${port}/health`, (res) => {
            resolve(res.statusCode === 200);
            res.resume();
        });

        req.setTimeout(800, () => {
            req.destroy();
            resolve(false);
        });

        req.on('error', () => resolve(false));
    });
}

// 暴露 HTTP 服务
const server = http.createServer(async (req, res) => {
    const pathname = new URL(req.url, `http://127.0.0.1:${BRIDGE_PORT}`).pathname;

    if (pathname === '/health' || pathname === '/health/') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: true, pid: process.pid }));
        return;
    }

    if (pathname === '/line-number' || pathname === '/line-number/') {
        const data = await getDevToolsLineNumber();
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(data));
        return;
    }

    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Not found' }));
});

server.on('error', async (err) => {
    if (err && err.code === 'EADDRINUSE') {
        const healthy = await probeExistingBridge(BRIDGE_PORT);
        if (healthy) {
            console.log(`Bridge already running at http://localhost:${BRIDGE_PORT}`);
            process.exit(0);
        }

        console.error(`Port ${BRIDGE_PORT} is in use by another process.`);
        process.exit(1);
        return;
    }

    throw err;
});

server.listen(BRIDGE_PORT, () => {
    console.log(`Bridge service running at http://localhost:${BRIDGE_PORT}`);
});