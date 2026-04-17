如何使用 17.rdp 并保存凭据

步骤：
1. 打开文件：在资源管理器双击 `templates\\17.rdp`，或在命令行运行：

   mstsc "%CD%\\templates\\17.rdp"

2. 在远程桌面连接窗口，点击 “显示选项”(Show Options)。
3. 在 "用户名" 一栏填入你的用户名（例如 `YOURDOMAIN\\YourUser` 或 `\\.\\YourUser`）。
4. 勾选 "允许我保存凭据"（若该选项不可见或不可勾选，说明本机/域策略可能禁止保存网络凭据）。
5. 点击 "连接"，在凭据弹窗中输入密码，并勾选 "记住我的凭据"（Remember my credentials）后确认。
6. 完成后，打开 控制面板 → Credential Manager → Windows Credentials，确认存在 `TERMSRV/17`（或 `TERMSRV/192.168.x.y`）条目。

命令行检查已保存凭据：

```
cmdkey /list
```

若策略禁止保存：
- 运行 `secpol.msc`（本地策略）或 `rsop.msc`（结果集策略）查看 “Network access: Do not allow storage of passwords and credentials for network authentication”。
- 若是域 GPO 控制，需要联系域管理员调整策略。

脚本自动化提示：
- 可以使用 `cmdkey /generic:TERMSRV/17 /user:User /pass:Password` 手动或脚本中保存凭据（注意明文密码风险）。
- 我可以把保存凭据的 `cmdkey` 调用加入 `rdp.ahk` / `rdp-connect.ps1`（需要你确认是否接受在脚本或配置中提供凭据）。
