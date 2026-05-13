const CDP = require('chrome-remote-interface');
const http = require('http');

const CDP_PORT = 9223;

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

// 暴露 HTTP 服务
http.createServer(async (req, res) => {
    if (req.url === '/line-number') {
        const data = await getDevToolsLineNumber();
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(data));
    }
}).listen(3000);

console.log('Bridge service running at http://localhost:3000');