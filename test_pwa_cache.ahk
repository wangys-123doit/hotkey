; ===============================================================
;  test_pwa_cache.ahk - PWA 窗口缓存诊断脚本（独立运行）
;  目的：验证 #d 激活 DMS 时"缓存有没有用、有没有复用已存在的 PWA"
;
;  检查三件事：
;    ① 进程级扫描：所有 chrome.exe 窗口按命令行 --app= / --app-id= 识别 PWA，
;       这是"已存在的 DMS 窗口"的真实存在情况（不依赖 UIA）；
;    ② UIA 路径验证：复现旧 BuildBrowserCache 的 UIA_Browser 取 URL 逻辑。
;       注意：当前生产 ActivateApp 首选路径是进程级 FindExistingAppWindow，
;       UIA 只是兜底，故 UIA 失效不等于 #d 会新开窗口；
;    ③ 判定模拟：按当前 ActivateApp 的真实顺序跑一遍
;       （①进程级 FindExistingAppWindow 首选 → UIA 缓存兜底 → Run 新开），
;       明确输出实际会"激活已有窗口"还是"新开/被引到其他实例"。
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

; 从 --app= 参数中提取 URL（同时兼容已安装 PWA 的 --app-id=，与生产 pitfall 一致）
ExtractAppUrl(cmdLine) {
    if RegExMatch(cmdLine, '--app="?([^"\s]+)', &m)
        return m[1]
    if RegExMatch(cmdLine, '--app-id=([^"\s]+)', &m)
        return "app-id:" m[1]
    return ""
}

; 提取 URL 的 host（与 ChromeAppMgr.GetUrlHost 同规则），用于容忍参数差异的比对
GetUrlHost(url) {
    if RegExMatch(url, "^https?://([^/]+)", &m)
        return StrLower(m[1])
    return ""
}

; DWMWA_CLOAKED：非当前虚拟桌面的窗口 cloaked=1
IsCloaked(hwnd) {
    buf := Buffer(4, 0)
    hr := DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 14, "Ptr", buf, "UInt", 4, "Int")
    return (hr = 0 && NumGet(buf, 0, "Int"))
}

; 与 ChromeAppMgr.IsRegularBrowserWindowTitle 同规则：标题带浏览器产品名后缀的
; 是普通浏览器窗口（共享主进程里的普通标签），必须排除，否则会把
; 同 profile 的普通 Chrome 窗口误当成 DMS PWA。
IsRegularBrowserWindowTitle(title) {
    return InStr(title, " - Google Chrome") || InStr(title, " - Chrome")
        || InStr(title, " - Microsoft Edge") || InStr(title, " - Edge")
}

; 复刻生产 ChromeAppMgr.FindExistingAppWindow：纯命令行 host 匹配 + cloaked 检测，
; 这是当前 ActivateApp 的首选路径（不依赖 UIA）。返回命中的 hwnd 或 0。
FindExistingAppWindowLocal(app, pwaWins) {
    targetHost := GetUrlHost(app["url"])
    if (targetHost == "")
        return 0
    fallback := 0
    for w in pwaWins {
        ; 排除普通浏览器窗口（与生产同规则）
        if IsRegularBrowserWindowTitle(w.title)
            continue
        appUrl := w.appUrl
        ; --app-id 形式拿不到 host，退回按窗口标题粗匹配
        if (InStr(appUrl, "app-id:")) {
            if InStr(w.title, app["title"])
                appUrl := app["url"]
            else
                continue
        }
        if (GetUrlHost(appUrl) != targetHost)
            continue
        if !IsCloaked(w.hwnd)
            return w.hwnd
        if !fallback
            fallback := w.hwnd
    }
    return fallback
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
        targets.Push({key: key, name: app["name"], url: app["url"], title: app["title"], app: app})
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

    ; ===== ③ 模拟当前 ActivateApp 的真实判定顺序 =====
    ;   生产 ActivateApp：① FindExistingAppWindow（进程级 host 匹配，首选）
    ;                     → ② hwndCache（UIA 缓存，兜底）→ ③ Run .lnk 新开
    ;   这里同时跑两条路径，并明确标注实际生效的是哪条。
    out .= "【③ ActivateApp 判定模拟（①进程级首选 / UIA缓存兜底）】`n"

    ; 兜底路径：UIA 缓存（当前 Chrome 下多半建不起来）
    hwndCache.Clear()
    for w in pwaWins {
        r := TryGetUrlViaUIA(w.hwnd)
        url := r.url
        if (InStr(url, "https://chatgpt.com"))
            hwndCache["chatgpt"] := w.hwnd
        else if (InStr(url, "https://dms.aliyun.com"))
            hwndCache["dms"] := w.hwnd
    }
    out .= "  [兜底] UIA 缓存条目数: " hwndCache.Count
    for k, v in hwndCache
        out .= "  [" k "]→" v
    out .= "`n"

    ; 首选路径：进程级 FindExistingAppWindow
    out .= "  [首选] FindExistingAppWindow（进程级 host 匹配）:`n"
    for t in targets {
        hitHwnd := FindExistingAppWindowLocal(t.app, pwaWins)
        cloaked := hitHwnd ? IsCloaked(hitHwnd) : false
        if (hitHwnd) {
            out .= "    " t.name " (" t.key "): ✓ 命中 hwnd=" hitHwnd
            out .= cloaked ? "（在其他虚拟桌面 cloaked，会回退激活）`n" : "（当前桌面可见）`n"
            out .= "       → #快捷键 会【激活已有窗口】（走 ActivateApp ①，与 UIA 是否失效无关）`n"
        } else if (hwndCache.Has(t.key)) {
            out .= "    " t.name " (" t.key "): ✗ 进程级未命中，但 UIA 缓存命中 → 走兜底激活`n"
            out .= "       （罕见：说明该窗口命令行无 --app，是靠 UIA 认出来的）`n"
        } else {
            ; 两条路径都没命中：确认窗口是否真的存在
            existHwnd := 0
            host := GetUrlHost(t.url)
            for w in pwaWins
                if (GetUrlHost(w.appUrl) == host || InStr(w.title, t.title)) {
                    existHwnd := w.hwnd
                    break
                }
            if (existHwnd) {
                out .= "    " t.name " (" t.key "): ⚠ 窗口存在(hwnd=" existHwnd ")但两条路径都没认出`n"
                out .= "       → #快捷键 会【Run .lnk 新开/聚焦】，可能被 Chrome 引到其他实例！`n"
                out .= "       排查：该窗口 pid 的命令行是否真的带 --app / --app-id（见①）`n"
            } else {
                out .= "    " t.name " (" t.key "): - 窗口不存在 → #快捷键 会【启动新窗口】（正常）`n"
            }
        }
    }

    out .= "`n================ 诊断结束 ================`n"
    out .= "结论指引：`n"
    out .= "· 只要③[首选]对 DMS 显示 ✓命中，则当前 ActivateApp 会正确激活 DMS，`n"
    out .= "  UIA(②)失不失效都不影响；此时若实际按键仍切到别的 Chrome，`n"
    out .= "  多半是 hotkey.ahk 未重载（内存里跑的是旧版 ActivateApp）→ Ctrl+Alt+R 重载`n"
    out .= "· 若③[首选]未命中但①能看到 DMS 的 [PWA] 条目 → host 比对或 --app 解析有问题`n"
    out .= "· 若①根本没有 DMS 条目 → DMS 窗口不在运行，或它复用了无 --app 的主进程`n"
    out .= "  （已安装 PWA 走快捷方式启动时的情况，需靠窗口标题判据补充）`n"

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
