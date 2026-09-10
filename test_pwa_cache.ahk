; ===============================================================
;  test_pwa_cache.ahk - PWA 窗口缓存诊断脚本（独立运行）
;  目的：验证 #d 激活 DMS 时"缓存有没有用、有没有复用已存在的 PWA"
;
;  检查三件事：
;    ① 进程级扫描：所有 chrome.exe 窗口按命令行 --app= 识别 PWA，
;       这是"已存在的 DMS 窗口"的真实存在情况（不依赖 UIA）；
;    ② UIA 路径验证：复现 BuildBrowserCache 的 UIA_Browser 取 URL 逻辑，
;       看 Chrome 更新后这条路径是否还能拿到 URL（拿不到 = 缓存建不起来
;       = #d 必然走 Run 新开窗口）；
;    ③ 缓存模拟：按 ActivateApp 的判断逻辑模拟一遍，
;       输出"命中缓存→激活"还是"未命中→会新开窗口"的最终结论。
;
;  运行：双击本文件（需已安装 AutoHotkey v2），不会修改任何东西，
;       只读诊断。结果弹窗展示。
; ===============================================================

#Include %A_ScriptDir%\lib\Jxon.ahk
#Include %A_ScriptDir%\lib\UIA.ahk
#Include %A_ScriptDir%\lib\UIA_Browser.ahk

; ChromeAppMgr.ahk 顶层会注册热键，测试脚本不需要，故不 Include，
; 这里复刻其最小依赖（配置读取 + 缓存构建）以便对照。

LoadConfigLocal() {
    json := FileRead(A_ScriptDir "\browser_apps.json", "UTF-8")
    return Jxon_Load(json)
}

global hwndCache := Map()

; ---------- ① 进程命令行识别（与 OpenControllerFromNetwork.ahk 同源实现） ----------
GetProcessCommandLine(pid) {
    try {
        hProcess := DllCall("OpenProcess", "UInt", 0x1010, "Int", 0, "UInt", pid, "Ptr")
        if !hProcess
            return ""
        buf := Buffer(32768, 0)
        status := DllCall("ntdll\NtQueryInformationProcess", "Ptr", hProcess, "UInt", 60, "Ptr", buf, "UInt", buf.Size, "UInt*", 0, "UInt")
        DllCall("CloseHandle", "Ptr", hProcess)
        if (status = 0) {
            strLen := NumGet(buf, 0, "UShort")
            strPtr := NumGet(buf, A_PtrSize == 8 ? 8 : 4, "Ptr")
            if (strLen > 0 && strPtr)
                return StrGet(strPtr, strLen // 2, "UTF-16")
        }
    }
    return ""
}

; 从 --app= 参数中提取 URL
ExtractAppUrl(cmdLine) {
    if RegExMatch(cmdLine, '--app="?([^"\s]+)', &m)
        return m[1]
    return ""
}

; ---------- ② UIA 路径验证（复现 BuildBrowserCache 取 URL） ----------
TryGetUrlViaUIA(hwnd) {
    result := {url: "", err: ""}
    try {
        cUIA := UIA_Browser("ahk_id " hwnd)
        url := cUIA.GetCurrentURL(false)
        if (url == "" || url == "https://")
            url := cUIA.JSExecute("window.location.href")
        result.url := Trim(url, " `"")
    } catch Error as e {
        result.err := e.Message
    }
    return result
}

; ---------- 主流程 ----------
RunDiagnosis() {
    config := LoadConfigLocal()
    out := "================ PWA 缓存诊断 ================`n`n"

    ; 目标 App 清单（与 ActivateApp 的键名映射规则一致）
    targets := []
    for app in config["apps"] {
        key := app["url"]
        if (InStr(key, "https://chatgpt.com"))
            key := "chatgpt"
        else if (InStr(key, "https://dms.aliyun.com"))
            key := "dms"
        targets.Push({key: key, name: app["name"], url: app["url"]})
    }

    ; ===== ① 扫描所有 chrome.exe 窗口 =====
    out .= "【① chrome.exe 窗口扫描（按命令行 --app= 识别 PWA）】`n"
    pwaWins := []   ; {hwnd, pid, title, appUrl}
    normalCount := 0
    for hwnd in WinGetList("ahk_exe chrome.exe") {
        title := ""
        try title := WinGetTitle("ahk_id " hwnd)
        if (title == "")
            continue
        pid := 0
        try pid := WinGetPID("ahk_id " hwnd)
        cmdLine := GetProcessCommandLine(pid)
        appUrl := ExtractAppUrl(cmdLine)
        if (appUrl != "") {
            pwaWins.Push({hwnd: hwnd, pid: pid, title: title, appUrl: appUrl})
            out .= "  [PWA] hwnd=" hwnd " pid=" pid "`n"
            out .= "        标题: " title "`n"
            out .= "        --app=: " appUrl "`n"
        } else {
            normalCount++
        }
    }
    out .= "  （普通浏览器窗口 " normalCount " 个，未列出）`n`n"

    ; ===== ② 对每个 PWA 窗口验证 UIA 取 URL（BuildBrowserCache 的核心路径） =====
    out .= "【② UIA 取 URL 验证（BuildBrowserCache 实际使用的路径）】`n"
    if (pwaWins.Length == 0)
        out .= "  无 PWA 窗口，跳过。`n"
    uiaOk := Map()  ; appUrl → hwnd（UIA 能取到 URL 的）
    for w in pwaWins {
        r := TryGetUrlViaUIA(w.hwnd)
        if (r.err != "") {
            out .= "  hwnd=" w.hwnd "  ✗ UIA 失败: " r.err "`n"
        } else if (r.url == "") {
            out .= "  hwnd=" w.hwnd "  ✗ UIA 返回空 URL`n"
        } else {
            out .= "  hwnd=" w.hwnd "  ✓ URL: " r.url "`n"
            uiaOk[r.url] := w.hwnd
        }
    }
    out .= "`n"

    ; ===== ③ 模拟 BuildBrowserCache + ActivateApp 判断 =====
    out .= "【③ 缓存命中模拟（与 BuildBrowserCache/ActivateApp 完全同规则）】`n"
    hwndCache.Clear()
    for w in pwaWins {
        r := TryGetUrlViaUIA(w.hwnd)
        url := r.url
        ; 与 BuildBrowserCache 相同的归类规则
        if (InStr(url, "https://chatgpt.com"))
            hwndCache["chatgpt"] := w.hwnd
        else if (InStr(url, "https://dms.aliyun.com"))
            hwndCache["dms"] := w.hwnd
    }
    out .= "  构建后的缓存条目数: " hwndCache.Count "`n"
    for k, v in hwndCache
        out .= "    [" k "] → hwnd=" v "`n"
    out .= "`n"

    for t in targets {
        ; 先看"真实存在"（①进程级），再看"缓存命中"（③）
        existHwnd := 0
        for w in pwaWins
            if (InStr(w.appUrl, t.name == "DMS" ? "dms.aliyun.com" : "chatgpt.com") || InStr(w.appUrl, t.url)) {
                existHwnd := w.hwnd
                break
            }
        if (existHwnd == 0) {
            ; 放宽匹配：命令行 URL 可能带参数，用域名前缀匹配
            host := RegExReplace(t.url, "^https?://([^/]+).*$", "$1")
            for w in pwaWins
                if InStr(w.appUrl, host) {
                    existHwnd := w.hwnd
                    break
                }
        }

        if (hwndCache.Has(t.key)) {
            out .= "  " t.name " (" t.key "): ✓ 缓存命中 → #快捷键 会【激活已有窗口】`n"
        } else if (existHwnd) {
            out .= "  " t.name " (" t.key "): ✗ 窗口真实存在(hwnd=" existHwnd ") 但缓存未命中`n"
            out .= "       → 按当前代码，#快捷键 会【新开一个窗口】！`n"
            if (!uiaOk.Count)
                out .= "       原因: UIA 取 URL 全部失败（见②），BuildBrowserCache 建不起缓存`n"
            else if (!uiaOk.Has(t.url))
                out .= "       原因: 该窗口的 UIA URL 获取失败或与配置 URL 不匹配（见②）`n"
        } else {
            out .= "  " t.name " (" t.key "): - 窗口不存在，按当前代码会【启动新窗口】（正常行为）`n"
        }
    }

    out .= "`n================ 诊断结束 ================`n"
    out .= "结论指引：`n"
    out .= "· 若①中能看到 DMS 的 [PWA] 条目，但②全部✗ → Chrome 更新破坏了 UIA 取 URL，`n"
    out .= "  BuildBrowserCache 失效，需改用进程命令行 --app= 识别（脚本可输出修复方案）`n"
    out .= "· 若①中没有 DMS 条目 → DMS 窗口其实不在运行`n"
    out .= "· 若③显示命中但实际按键仍新开 → 问题在 ActivateApp 的缓存生命周期（热键按下`n"
    out .= "  时缓存是脚本启动时建的，中途打开的窗口不在缓存里）`n"

    ShowResult(out)
}

ShowResult(text) {
    ; 同时写入文件，方便回看/反馈
    try {
        if FileExist(A_ScriptDir "\test_pwa_cache_result.txt")
            FileDelete(A_ScriptDir "\test_pwa_cache_result.txt")
        FileAppend(text, A_ScriptDir "\test_pwa_cache_result.txt", "UTF-8")
    }
    g := Gui("+AlwaysOnTop +Resize", "PWA 缓存诊断")
    ed := g.AddEdit("w700 h480 ReadOnly", text)
    g.OnEvent("Size", (guiObj, minMax, w, h) => ed.Move(,, w - 20, h - 20))
    g.Show()
}

RunDiagnosis()
