# Native Host 快速开始

此目录包含 Chrome 扩展使用的 Native Messaging 主机。

## 文件说明

- `host.js` - Native Host 主程序
- `host.cmd` - Windows 启动脚本，由安装脚本生成
- `install-native-host.ps1` - 安装和注册脚本，需要管理员权限

## 安装

```powershell
cd devtools-vscode-opener\native-host
.\install-native-host.ps1 -ExtensionId <your-extension-id>
```

## 验证

先确认 `host.js` 语法没有问题：

```powershell
node -c host.js
```

再手动验证 VSCode 命令链路：

```powershell
cd D:\code\jd-tduck-x-front
& 'C:\Users\yinsh\AppData\Local\Programs\Microsoft VS Code\bin\code.cmd' --reuse-window --goto 'src/views/system/customTable/documentField.vue:264:1'
```

## 故障排查

### 文件没打开

1. 重新运行 `install-native-host.ps1`
2. 刷新 Chrome 扩展
3. 再执行一次上面的 `code.cmd --goto` 命令

### 需要临时日志

如果要排查 native host 行为，可以在 `host.js` 里临时加 `console.error`；生产版建议保持精简。