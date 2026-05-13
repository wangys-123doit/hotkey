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
        // 1. 获取所有目标，寻找类型为 'devtools' 的页面
        const targets = await CDP.List({ port: CDP_PORT });
        const devtoolsTarget = targets.find(t => t.type === 'devtools' || t.url.includes('devtools://'));

        if (!devtoolsTarget) {
            return { error: 'DevTools not open', targetCount: targets.length };
        }

        // 2. 连接到 DevTools 自身的调试实例
        client = await CDP({ port: CDP_PORT, target: devtoolsTarget });
        const { Runtime } = client;

        // 3. 执行 JS。DevTools 内部通过 UI.panels 暴露状态
        const expression = `
            (() => {
                const panel = UI.panels && UI.panels.sources;
                const editor = panel && panel.sourcesViewInternal && panel.sourcesViewInternal.currentSourceEditor();
                return {
                    hasPanel: !!panel,
                    hasEditor: !!editor,
                    line: editor ? (editor.selection().startLine + 1) : 0
                };
            })()
        `;

        const result = await Runtime.evaluate({ expression, returnByValue: true });
        if (!result || !result.result) {
            return { error: 'No eval result' };
        }

        if (result.result.value && typeof result.result.value === 'object') {
            return {
                lineNumber: result.result.value.line,
                hasPanel: result.result.value.hasPanel,
                hasEditor: result.result.value.hasEditor
            };
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