; ===============================================================
;  ChromeAppMgr.ahk - Chrome PWA 应用管理 + 缓存 (AHK v2)
;  从 hotkey.ahk 拆分而来
; ===============================================================
;
; 包含：
;   - LoadConfig / CONFIG / APP_DIR / AppMgr
;   - GuiAppManager             管理 GUI
;   - GenerateSelected / DeleteSelected / DeleteWithTrayTip
;   - GenerateApp / BuildChromeArgs / CreateChromeApp / CreateWithTrayTip
;   - BuildBrowserCache / DumpMap / ActivateApp
;   - BindActivateApp + 顶层 for 循环注册热键
;
; 依赖（必须在 hotkey.ahk 中先 #Include）：
;   - lib\Jxon.ahk          （Jxon_Load）
;   - lib\UIA_Browser.ahk   （UIA_Browser 类）
; ===============================================================


; 浏览器窗口句柄缓存（URL/App 标识 → hwnd）
global hwndCache := Map()

; 读取 browser_apps.json 配置
LoadConfig() {
    json := FileRead(A_ScriptDir "\browser_apps.json", "UTF-8")
    return Jxon_Load(json)
}

; 全局配置与应用目录
global CONFIG := LoadConfig()
global APP_DIR := A_ScriptDir "\apps"

; AppMgr 对象（GUI 容器）
global AppMgr := {}


; ==========================
; 管理 GUI
; ==========================
GuiAppManager() {
    global CONFIG, AppMgr

    AppMgr.gui := Gui("+AlwaysOnTop", "Browser App Manager")

    lv := AppMgr.gui.AddListView("w520 r10", ["App", "⭐", "Hotkey", "Browser"])

    for app in CONFIG["apps"] {
        stars := ""
        Loop app["memory"]
            stars .= "⭐"

        lv.Add(
            "",
            app["name"],
            stars,
            app["hotkey"],
            app["browser"],
            app["aumid"],
        )
    }

    btnGen := AppMgr.gui.AddButton("x10 y+10 w120", "生成 App")
    btnDel := AppMgr.gui.AddButton("x+10 w120", "删除 App")

    btnGen.OnEvent("Click", (*) => GenerateSelected(lv))
    btnDel.OnEvent("Click", (*) => DeleteSelected(lv))

    AppMgr.gui.Show()
}


; ==========================
; 生成 / 删除
; ==========================
GenerateSelected(lv) {
    row := lv.GetNext()
    if !row
        return
    app := CONFIG["apps"][row]
    CreateChromeApp(app)
}

DeleteSelected(lv) {
    row := lv.GetNext()
    if !row
        return

    app := CONFIG["apps"][row]
    file := APP_DIR "\run_" app["name"] ".ps1"
    isDelete := DeleteWithTrayTip(file)
    if (isDelete) {
        file := APP_DIR "\" app["name"] ".lnk"
        DeleteWithTrayTip(file)
    }
}

DeleteWithTrayTip(file) {
    if !FileExist(file)
        return false

    try {
        FileDelete(file)
        SplitPath(file, &name)
        TrayTip("文件已删除", name)
        return true
    } catch Error as e {
        TrayTip("删除失败", e.Message)
        return false
    }
}


; ==========================
; 生成 CMD / Chrome App
; ==========================
; 生成 CMD（旧逻辑，保留以兼容）
GenerateApp(app) {
    global CONFIG, APP_DIR

    DirCreate(APP_DIR)

    browser := CONFIG["browsers"][app["browser"]]
    args := StrJoin(" ", CONFIG["commonArgs"])

    cmd := Format(
        '"{}" --profile-directory={} --app={} {}',
        browser["path"],
        browser["profile"],
        app["url"],
        args
    )

    file := APP_DIR "\run_" app["name"] ".cmd"
    if FileExist(file) {
        FileDelete(file)
    }
    FileAppend(cmd, file, "UTF-8")
}

BuildChromeArgs(app) {
    global CONFIG

    browser := CONFIG["browsers"][app["browser"]]

    args := []
    args.Push("--profile-directory=" browser["profile"])
    args.Push("--app=" app["url"])

    for a in CONFIG["commonArgs"]
        args.Push(a)

    return StrJoin(" ", args)
}

CreateChromeApp(app) {
    global CONFIG

    browser := CONFIG["browsers"][app["browser"]]
    chromeArgs := BuildChromeArgs(app)

    ps := Format(("$Target = '{1}'`n"
    "$Arguments   = '{2}'`n"
    "$Lnk    = '{3}'`n"
    "$AUMID  = '{4}'`n`n"

    "$Wsh = New-Object -ComObject WScript.Shell`n"
    "$S = $Wsh.CreateShortcut($Lnk)`n"
    "$S.TargetPath = $Target`n"
    "$S.Arguments  = $Arguments`n"
    "$S.IconLocation = `"$Target,0`"`n"
    "$S.WorkingDirectory = Split-Path $Target`n"
    "$S.Save()`n`n"

    "$bytes = [System.Text.Encoding]::Unicode.GetBytes(`"`0$AUMID`")`n"
    "$stream = [System.IO.File]::Open($Lnk, 'Open', 'ReadWrite')`n"
    "$stream.Seek(0x800, 'Begin') | Out-Null`n"
    "$stream.Write($bytes, 0, $bytes.Length)`n"
    "$stream.Close()"
    ),
    browser["path"], chromeArgs, APP_DIR "\" app["name"] ".lnk", app["aumid"]
    )

    file :=  APP_DIR "\run_" app["name"] ".ps1"
    isCreate := CreateWithTrayTip(ps, file, "UTF-8")
    if (isCreate) {
        RunWait 'powershell -NoProfile -ExecutionPolicy Bypass -File "' file '"', , "Hide"
        TrayTip("点击" app["hotkey"] "按键可激活" app["name"])
    }
}

CreateWithTrayTip(ps, file, encode) {
    try {
        if FileExist(file) {
            FileDelete(file)
        }
        FileAppend(ps, file, encode)
        SplitPath(file, &name)
        TrayTip("文件创建成功", name)
        return true
    } catch Error as e {
        TrayTip("文件创建失败", e.Message)
        return false
    }
}


; ==========================
; 浏览器缓存与 App 激活
; ==========================
; 根据 App 配置 URL 推导缓存键名（与 ActivateApp 的映射规则统一）
GetAppCacheKey(url) {
    if (InStr(url, "https://chatgpt.com"))
        return "chatgpt"
    else if (InStr(url, "https://dms.aliyun.com"))
        return "dms"
    return ""
}

; 重建浏览器窗口缓存（App 标识 → hwnd）
; 完全基于进程命令行构建，彻底不碰 UIA：直接复用 FindExistingAppWindow
; （内部用 GetAppProcessCommandLine 读 --app=/--app-id= + host 匹配 + 窗口标题判据），
; 既避免 UIA 的 JSExecute 往地址栏写 javascript: 的副作用，也不受 Chrome 更新/UIA 失效影响。
BuildBrowserCache() {
    global hwndCache, CONFIG
    if !IsSet(hwndCache) || !hwndCache
        hwndCache := Map()
    hwndCache.Clear()

    for app in CONFIG["apps"] {
        key := GetAppCacheKey(app["url"])
        if (key == "")
            continue
        hwnd := FindExistingAppWindow(app)
        if hwnd
            hwndCache[key] := hwnd
    }
}

DumpMap(hwndCache) {
    i := 1
    out := ""
    for url, hwnd in hwndCache {
        out .= i ".key:`n" url "`nvalue:`n" hwnd "`n`n"
        i++
    }

    local _gui := Gui("+AlwaysOnTop", "Dump")
    _gui.AddEdit("w400 h300 ReadOnly", out)
    _gui.Show()
}

; 获取进程命令行（NtQueryInformationProcess，不走 WMI；与 OpenControllerFromNetwork.ahk 同源，
; 独立命名避免重复定义）
GetAppProcessCommandLine(pid) {
    try {
        hProcess := DllCall("OpenProcess", "UInt", 0x1010, "Int", 0, "UInt", pid, "Ptr")
        if !hProcess
            return ""
        buf := Buffer(32768, 0)
        ; ProcessCommandLineInformation = 60
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

; 从命令行 --app= 参数提取 URL；非 PWA 窗口返回空串
ExtractAppUrlFromCmd(cmdLine) {
    if RegExMatch(cmdLine, '--app="?([^"\s]+)', &m)
        return m[1]
    return ""
}

; 提取 URL 的 host，用于容忍参数差异的同一应用比对（如 ?accounttraceid=...）
GetUrlHost(url) {
    if RegExMatch(url, "^https?://([^/]+)", &m)
        return StrLower(m[1])
    return ""
}

; 判断是否为"普通浏览器窗口"标题（带浏览器产品名后缀）。
; 关键：--app 启动的 Chrome 是该 profile 的共享主进程，用户在同一 profile 里
; 打开的普通窗口也归属这个 pid（命令行仍带 --app=），仅靠进程命令行会把普通
; 窗口误当成 PWA。真正的 App/PWA 窗口标题不带这些后缀（如 "DMS - Data
; Management Service"），据此过滤掉普通浏览器窗口。
IsRegularBrowserWindowTitle(title) {
    return InStr(title, " - Google Chrome") || InStr(title, " - Chrome")
        || InStr(title, " - Microsoft Edge") || InStr(title, " - Edge")
}

; 查找已存在的 PWA 窗口：按进程命令行 --app= 匹配（毫秒级，不受 Chrome 更新、
; UIA 失败、缓存生命周期影响）。优先返回当前桌面可见窗口（DWMWA_CLOAKED=0），
; 都不在当前桌面时回退首个匹配窗口。
FindExistingAppWindow(app) {
    exe := app["browser"] = "chrome" ? "chrome.exe" : "msedge.exe"
    targetHost := GetUrlHost(app["url"])
    if (targetHost == "")
        return 0

    fallback := 0
    cmdCache := Map()  ; 同一进程的多个窗口共享命令行，避免重复读内核
    for hwnd in WinGetList("ahk_exe " exe) {
        title := ""
        try title := WinGetTitle("ahk_id " hwnd)
        if (title == "")
            continue
        ; 排除普通浏览器窗口（共享主进程里的普通标签窗口，标题带产品名后缀）
        if IsRegularBrowserWindowTitle(title)
            continue
        pid := 0
        try pid := WinGetPID("ahk_id " hwnd)
        if !pid
            continue
        if !cmdCache.Has(pid)
            cmdCache[pid] := ExtractAppUrlFromCmd(GetAppProcessCommandLine(pid))
        appUrl := cmdCache[pid]
        if (appUrl == "" || GetUrlHost(appUrl) != targetHost)
            continue

        ; DWMWA_CLOAKED：非当前桌面的窗口 cloaked=1
        buf := Buffer(4, 0)
        hr := DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 14, "Ptr", buf, "UInt", 4, "Int")
        if (hr = 0 && !NumGet(buf, 0, "Int"))
            return hwnd
        if !fallback
            fallback := hwnd
    }
    return fallback
}

; 根据 browser_apps.json 配置激活对应 Chrome App 窗口；只能复用已有窗口，没有才新开
ActivateApp(app) {
    global hwndCache
    if !IsSet(hwndCache) || !hwndCache
        hwndCache := Map()

    ; ① 首选进程级识别：命令行 --app= 匹配，实时扫描，永远只复用已存在的窗口。
    ;    （旧方案只靠启动时建一次缓存，脚本启动后打开的窗口不在缓存里，
    ;      导致 #快捷键总是新开；UIA 取 URL 失败时缓存也建不起来）
    existing := FindExistingAppWindow(app)
    if existing {
        if WinActive("ahk_id " existing)
            WinMinimize("ahk_id " existing)
        else
            WinActivate("ahk_id " existing)
        return
    }

    ; ② 兜底路径：缓存里已有该 App 的窗口句柄时直接激活
    ;    （缓存现由 BuildBrowserCache 基于进程命令行构建，只收录真正的 PWA 窗口）
    exe := app["browser"] = "chrome" ? "chrome.exe" : "msedge.exe"

    targetURL := GetAppCacheKey(app["url"])

    ; 精准匹配 URL
    if hwndCache.Has(targetURL) {
        ahk_id := hwndCache[targetURL]
        if !WinExist("ahk_id " ahk_id) {
            ; 窗口已关闭，重建缓存
            BuildBrowserCache()
            if hwndCache.Has(targetURL) {
                ahk_id := hwndCache[targetURL]
            } else {
                return
            }
        }
        if WinActive("ahk_id " ahk_id) {
            WinMinimize("ahk_id " ahk_id)
        } else {
            WinActivate("ahk_id " ahk_id)
        }
        return
    }
    ; ③ 确实没有任何已存在的窗口 → 启动 App 并等待窗口出现，并重建缓存
    Run APP_DIR "\" app["name"] ".lnk"
    winTitle := app["title"]
    if WinWait(winTitle " ahk_exe " exe,, 5) {
        BuildBrowserCache()
        if hwndCache.Has(targetURL) {
            ahk_id := hwndCache[targetURL]
            WinActivate("ahk_id " ahk_id)
        } else {
            WinActivate(winTitle)
        }
    }
}

; 绑定热键闭包
BindActivateApp(app) {
    return (*) => ActivateApp(app)
}

; 顶层：为 CONFIG 中所有 App 注册配置的热键
for app in CONFIG["apps"] {
    Hotkey app["hotkey"], BindActivateApp(app)
}
