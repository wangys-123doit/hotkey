;~ 1、配置区
global PERF_LOG_ENABLED := true
global DEVTOOLS_MENU_RETRIES := 2
global DEVTOOLS_MENU_RETRIES_FAST := 1
global DEVTOOLS_MENU_RETRY_SLEEP_MS := 35
global DEVTOOLS_MENU_RETRY_SLEEP_MS_FAST := 22
global DEVTOOLS_CONTEXTMENU_SLEEP_MS := 90
global DEVTOOLS_POST_COPY_SLEEP_MS := 60
global DEVTOOLS_CLIPWAIT_SEC := 0.2
global DEVTOOLS_MENU_RETRIES_FALLBACK := 6
global DEVTOOLS_MENU_RETRY_SLEEP_MS_FALLBACK := 70
global DEVTOOLS_CLIPWAIT_SEC_FALLBACK := 0.45
global DEVTOOLS_TRIPLE_C_DISABLE_AFTER_FAILS := 2
global DEVTOOLS_TRIPLE_C_FAIL_STREAK := 0
global DEVTOOLS_TRIPLE_C_SKIP_MODE := false
global DEVTOOLS_MENU_CACHE_TTL_MS := 15000
global DEVTOOLS_MENU_CACHE_DRIFT_X := 520
global DEVTOOLS_MENU_CACHE_DRIFT_Y := 420
global DEVTOOLS_MENU_CALL_ROUND := 0
global DEVTOOLS_MENU_CACHE_DISABLED_ROUND := {copy: 0, url: 0}
global DEVTOOLS_MENU_ANCHOR_CACHE := {
    hwnd: 0,
    copy: {valid: false, x: 0, y: 0, mx: 0, my: 0, ts: 0},
    url: {valid: false, x: 0, y: 0, mx: 0, my: 0, ts: 0}
}

;~ 2、主入口
^!g::OpenControllerFromNetwork()
^!u::CopyDevToolsSelectedRequestURL()

;~ ^+g::OpenControllerFromNetwork()

;~ 3、主流程
OpenControllerFromNetwork()
{
    try
    {
        url := DevTools_GetSelectedURL()

        if (url = "")
            url := DevTools_GetSelectedURLFromClipboard()

        if (url = "")
            throw Error("No URL selected")

        path := ParseAPIPath(url)

        A_Clipboard := path

    }
    catch Error as err
    {
        MsgBox "Error:`n" err.Message
    }
}
; ~ 4、DevTools 读取 URL（核心） 
CopyDevToolsSelectedRequestURL()
{
    try
    {
        t0 := A_TickCount
        PerfLog("CopyDevToolsSelectedRequestURL start")

        ; 优先模拟 DevTools 常规操作：右键 -> 复制 -> 复制 URL
        t := A_TickCount
        url := DevTools_CopyURLViaContextMenu()
        PerfLog(Format("after DevTools_CopyURLViaContextMenu (+{1} ms)", A_TickCount - t))

        if (url = "")
        {
            t := A_TickCount
            url := DevTools_GetSelectedURL()
        }

        if (url = "")
        {
            t := A_TickCount
            url := DevTools_GetSelectedURLFromClipboard()
        }

        if (url = "")
            throw Error("No selected request URL found in DevTools Network.`n请将鼠标停在 Network 请求行上后再按热键。")

        ; A_Clipboard := url
        ; 解析 URL，提取 path 部分并放入剪贴板 供后续使用
        A_Clipboard := ParseAPIPath(url)
        PerfLog(Format("CopyDevToolsSelectedRequestURL done total={1} ms", A_TickCount - t0))
        ; ToolTip "Copied URL: " url
        ; SetTimer () => ToolTip(), -1200
    }
    catch Error as err
    {
        PerfLog("CopyDevToolsSelectedRequestURL error: " err.Message)
        MsgBox "Error:`n" err.Message
    }
}




;~ 4、DevTools 读取 URL（核心）
DevTools_GetSelectedURL()
{
    row := DevTools_GetSelectedRequestRowElement()
    if !row
        return ""

    try name := Trim(row.CurrentName)
    catch
        return ""

    if RegExMatch(name, "i)https?://[^\s]+", &m)
        return m[0]

    ; 有些 DevTools 行名不是完整 URL（可能是 path/状态列拼接），这里返回原文本给上层继续走复制兜底
    return name
}

DevTools_GetSelectedURLFromClipboard()
{
    clipBak := A_Clipboard
    A_Clipboard := ""

    Send "^c"
    ClipWait 0.25

    copied := Trim(A_Clipboard)
    A_Clipboard := clipBak

    if (copied = "")
        return ""

    if RegExMatch(copied, "i)https?://[^\s]+", &m)
        return m[0]

    return ""
}

DevTools_CopyURLViaContextMenu()
{
    totalStart := A_TickCount
    PerfLog("DevTools_CopyURLViaContextMenu start")

    clipBak := A_Clipboard
    A_Clipboard := ""

    ; 快速路径：优先在聚焦/选中请求行上右键；失败再退回鼠标位置
    MouseGetPos &mx, &my
    t := A_TickCount
    opened := DevTools_OpenContextMenuOnFocusedOrSelectedRequest(&mx, &my)
    if !opened
    {
        DevTools_OpenContextMenuAtPoint(mx, my, DEVTOOLS_CONTEXTMENU_SLEEP_MS)
    }

    ; 鼠标快速路径：允许一次 full-scan，尽量首轮命中，避免二次开菜单
    copiedUrl := DevTools_TryCopyURLFromOpenedMenu(mx, my, true)
    if (copiedUrl != "")
    {
        A_Clipboard := clipBak
        PerfLog(Format("DevTools_CopyURLViaContextMenu done total={1} ms (mouse fast path)", A_TickCount - totalStart))
        return copiedUrl
    }

    Send "{Esc}"

    ; 次级兜底：尝试按选中请求行打开菜单后再次复制
    opened := DevTools_OpenContextMenuOnSelectedRequest(&mx, &my)

    if opened
    {
        copiedUrl := DevTools_TryCopyURLFromOpenedMenu(mx, my, true)
        if (copiedUrl != "")
        {
            A_Clipboard := clipBak
            PerfLog(Format("DevTools_CopyURLViaContextMenu done total={1} ms (row fallback path)", A_TickCount - totalStart))
            return copiedUrl
        }
    }

    ; 极限兜底：聚焦鼠标所在请求行后直接 Ctrl+C
    copiedUrl := DevTools_TryCopyURLViaCtrlCAtMouse(mx, my)
    if (copiedUrl != "")
    {
        A_Clipboard := clipBak
        PerfLog(Format("DevTools_CopyURLViaContextMenu done total={1} ms (ctrl+c fallback)", A_TickCount - totalStart))
        return copiedUrl
    }

    ; 取消菜单
    Send "{Esc}"
    A_Clipboard := clipBak
    PerfLog(Format("DevTools_CopyURLViaContextMenu done total={1} ms (empty)", A_TickCount - totalStart))
    return ""
}

DevTools_TryCopyURLFromOpenedMenu(mx, my, allowFullScan := true)
{
    global DEVTOOLS_POST_COPY_SLEEP_MS
    global DEVTOOLS_CLIPWAIT_SEC
    global DEVTOOLS_MENU_RETRIES_FAST
    global DEVTOOLS_MENU_RETRY_SLEEP_MS_FAST
    global DEVTOOLS_MENU_RETRIES_FALLBACK
    global DEVTOOLS_MENU_RETRY_SLEEP_MS_FALLBACK
    global DEVTOOLS_CLIPWAIT_SEC_FALLBACK
    global DEVTOOLS_TRIPLE_C_DISABLE_AFTER_FAILS
    global DEVTOOLS_TRIPLE_C_FAIL_STREAK
    global DEVTOOLS_TRIPLE_C_SKIP_MODE
    global DEVTOOLS_MENU_CALL_ROUND

    DEVTOOLS_MENU_CALL_ROUND += 1

    ; 自适应快速键：连续失败后进入 skip 模式，稳定优先不自动 probe
    shouldTryTripleC := true
    if DEVTOOLS_TRIPLE_C_SKIP_MODE
    {
        shouldTryTripleC := false
    }

    if shouldTryTripleC
    {
        Send "c"
        Sleep 40
        Send "c"
        Sleep 40
        Send "c"
        Sleep DEVTOOLS_POST_COPY_SLEEP_MS
        ClipWait DEVTOOLS_CLIPWAIT_SEC
        copied := Trim(A_Clipboard)
        if RegExMatch(copied, "i)https?://[^\s]+", &m)
        {
            DEVTOOLS_TRIPLE_C_FAIL_STREAK := 0
            DEVTOOLS_TRIPLE_C_SKIP_MODE := false
            return m[0]
        }

        DEVTOOLS_TRIPLE_C_FAIL_STREAK += 1
        if (DEVTOOLS_TRIPLE_C_FAIL_STREAK >= DEVTOOLS_TRIPLE_C_DISABLE_AFTER_FAILS)
        {
            DEVTOOLS_TRIPLE_C_SKIP_MODE := true
        }
    }

    ; 常规路径：UIA 定位 Copy 后双 Enter 选中子菜单首项（通常是 Copy URL）
    if DevTools_WaitAndInvokeMenuItem("copy", mx, my, DEVTOOLS_MENU_RETRIES_FAST, DEVTOOLS_MENU_RETRY_SLEEP_MS_FAST, allowFullScan)
    {
        Sleep DEVTOOLS_POST_COPY_SLEEP_MS

        ; 快速路径：点击 Copy 后，直接双 Enter 选择子菜单首项（通常是 Copy URL）
        Send "{Enter}{Enter}"
        ClipWait DEVTOOLS_CLIPWAIT_SEC
        copied := Trim(A_Clipboard)
        if RegExMatch(copied, "i)https?://[^\s]+", &m)
            return m[0]

        ; 双 Enter 未命中时，回退到原 URL 菜单查找
        if DevTools_WaitAndInvokeMenuItem("url", mx, my, DEVTOOLS_MENU_RETRIES_FAST, DEVTOOLS_MENU_RETRY_SLEEP_MS_FAST, allowFullScan)
        {
            ClipWait DEVTOOLS_CLIPWAIT_SEC
            copied := Trim(A_Clipboard)
            if RegExMatch(copied, "i)https?://[^\s]+", &m)
                return m[0]
        }
    }

    ; 轻量兜底：尝试一级菜单中的 Copy URL（仅局部查找，不做全局扫描）
    if DevTools_WaitAndInvokeMenuItem("url", mx, my, 1, DEVTOOLS_MENU_RETRY_SLEEP_MS_FAST, false)
    {
        ClipWait DEVTOOLS_CLIPWAIT_SEC
        copied := Trim(A_Clipboard)
        if RegExMatch(copied, "i)https?://[^\s]+", &m)
            return m[0]
    }

    ; 强兜底：放宽重试与等待，兼容慢机器/菜单渲染慢
    PerfLog("enter reliable fallback menu flow")

    if DevTools_WaitAndInvokeMenuItem("copy", mx, my, DEVTOOLS_MENU_RETRIES_FALLBACK, DEVTOOLS_MENU_RETRY_SLEEP_MS_FALLBACK, allowFullScan)
    {
        Sleep 120

        ; 可靠模式也优先尝试双 Enter，减少一次菜单扫描
        Send "{Enter}{Enter}"
        ClipWait DEVTOOLS_CLIPWAIT_SEC_FALLBACK
        copied := Trim(A_Clipboard)
        if RegExMatch(copied, "i)https?://[^\s]+", &m)
            return m[0]

        if DevTools_WaitAndInvokeMenuItem("url", mx, my, DEVTOOLS_MENU_RETRIES_FALLBACK, DEVTOOLS_MENU_RETRY_SLEEP_MS_FALLBACK, allowFullScan)
        {
            ClipWait DEVTOOLS_CLIPWAIT_SEC_FALLBACK
            copied := Trim(A_Clipboard)
            if RegExMatch(copied, "i)https?://[^\s]+", &m)
                return m[0]
        }
    }

    return ""
}

PerfLog(msg)
{
    global PERF_LOG_ENABLED

    if !PERF_LOG_ENABLED
        return

    line := Format("[{1}] {2}`n", A_TickCount, msg)
    OutputDebug line
    FileAppend line, A_ScriptDir "\\ahk_devtools_perf.log", "UTF-8"
}

DevTools_GetSelectedRequestRowElement()
{
    hwnd := WinActive("A")
    if !hwnd
        return ""

    root := UIA.ElementFromHandle(hwnd)
    cond := UIA.CreatePropertyCondition(UIA.Property.ControlType, UIA.Type.DataItem)
    rows := root.FindAll(cond, UIA.TreeScope.Subtree)

    best := ""
    bestScore := -1


    for row in rows
    {
        try name := Trim(row.CurrentName)
        catch
            continue

        if (name = "")
            continue

        try br := row.BoundingRectangle
        catch
            continue

        w := br.r - br.l
        h := br.b - br.t
        if (w < 20 || h < 10)
            continue

        score := 0

        try if row.CurrentIsSelected
            score += 10

        try if row.HasKeyboardFocus
            score += 8

        if RegExMatch(name, "i)^https?://")
            score += 12
        if InStr(name, "api")
            score += 2

        if (score > bestScore)
        {
            best := row
            bestScore := score
        }
    }

    return (bestScore >= 8) ? best : ""
}

DevTools_OpenContextMenuOnSelectedRequest(&mx, &my)
{
    row := DevTools_GetSelectedRequestRowElement()
    if !row
        return false

    return DevTools_OpenContextMenuOnRow(row, &mx, &my, 180)
}

DevTools_GetFocusedRequestRowElement()
{
    try focused := UIA.GetFocusedElement()
    catch
        return ""

    if !IsObject(focused)
        return ""

    el := focused
    loop 8
    {
        try ct := el.CurrentControlType
        catch
            break

        if (ct = UIA.Type.DataItem)
            return el

        try el := UIA.TreeWalkerTrue.GetParentElement(el)
        catch
            break

        if !IsObject(el)
            break
    }

    return ""
}

DevTools_OpenContextMenuOnFocusedOrSelectedRequest(&mx, &my)
{
    row := DevTools_GetFocusedRequestRowElement()
    if !row
        row := DevTools_GetSelectedRequestRowElement()

    if !row
        return false

    return DevTools_OpenContextMenuOnRow(row, &mx, &my, DEVTOOLS_CONTEXTMENU_SLEEP_MS)
}

DevTools_OpenContextMenuOnRow(row, &mx, &my, waitMs)
{
    try br := row.BoundingRectangle
    catch
        return false

    mx := br.l + ((br.r - br.l) // 2)
    my := br.t + ((br.b - br.t) // 2)

    try
    {
        row.Click("Right")
        Sleep waitMs
        return true
    }
    catch
    {
    }

    return DevTools_OpenContextMenuAtPoint(mx, my, waitMs)
}

DevTools_OpenContextMenuAtPoint(mx, my, waitMs := 120)
{
    MouseGetPos &oldX, &oldY
    MouseMove mx, my, 0
    Click "Right"
    MouseMove oldX, oldY, 0
    Sleep waitMs
    return true
}

DevTools_TryCopyURLViaCtrlCAtMouse(mx, my)
{
    MouseGetPos &oldX, &oldY
    MouseMove mx, my, 0
    Click
    Sleep 40
    Send "^c"
    ClipWait 0.25
    MouseMove oldX, oldY, 0

    copied := Trim(A_Clipboard)
    if (copied = "")
        return ""

    if RegExMatch(copied, "i)https?://[^\s]+", &m)
        return m[0]

    return ""
}

DevTools_WaitAndInvokeMenuItem(mode, mx, my, retries := "", sleepMs := "", enableFinalFullScan := true)
{
    global DEVTOOLS_MENU_RETRIES
    global DEVTOOLS_MENU_RETRY_SLEEP_MS

    if (retries = "")
        retries := DEVTOOLS_MENU_RETRIES

    if (sleepMs = "")
        sleepMs := DEVTOOLS_MENU_RETRY_SLEEP_MS

    loop retries
    {
        if DevTools_InvokeBestMenuItem(mode, mx, my, false)
            return true
        Sleep sleepMs
    }

    if enableFinalFullScan
    {
        if DevTools_InvokeBestMenuItem(mode, mx, my, true)
            return true
    }

    return false
}

DevTools_InvokeBestMenuItem(mode, mx, my, allowFullScan := true)
{
    cond := UIA.CreatePropertyCondition(UIA.Property.ControlType, UIA.Type.MenuItem)
    ; 优先在焦点和鼠标附近做局部查找，避免全桌面 Subtree 扫描
    anchors := []

    ; 命中缓存时先单独尝试，若失败则本轮禁用缓存避免重复命中空耗
    cachedAnchor := DevTools_GetCachedMenuAnchor(mode, mx, my)
    if IsObject(cachedAnchor)
    {
        best := DevTools_FindBestMenuItemNearAnchor(cachedAnchor, cond, mode, mx, my)
        if IsObject(best)
            return DevTools_ClickOrInvoke(best, mode, mx, my)

        if allowFullScan
        {
            best := DevTools_FindBestMenuItemNearAnchor(cachedAnchor, cond, mode, mx, my, 980, 760)
            if IsObject(best)
            {
                PerfLog("DevTools_InvokeBestMenuItem fallback anchor-wide-scan")
                return DevTools_ClickOrInvoke(best, mode, mx, my)
            }
        }

        DevTools_DisableMenuCacheForCurrentRound(mode)
    }

    try
    {
        focused := UIA.GetFocusedElement()
        if IsObject(focused)
            anchors.Push(focused)
    }
    catch
    {
    }

    ; 补充更多菜单常见偏移点，提高局部命中率，降低触发 full-scan 概率
    for offset in [[18, 12], [10, 22], [0, 0], [60, 18], [96, 22], [132, 30], [72, 44], [118, 56], [-18, 16]]
    {
        try
        {
            el := UIA.ElementFromPoint(mx + offset[1], my + offset[2],, 0)
            if IsObject(el)
                anchors.Push(el)
        }
        catch
        {
        }
    }

    for anchor in anchors
    {
        best := DevTools_FindBestMenuItemNearAnchor(anchor, cond, mode, mx, my)
        if IsObject(best)
            return DevTools_ClickOrInvoke(best, mode, mx, my)
    }

    if allowFullScan
    {
        ; 先做锚点子树的宽范围扫描，减少直接全桌面扫描的概率
        for anchor in anchors
        {
            best := DevTools_FindBestMenuItemNearAnchor(anchor, cond, mode, mx, my, 980, 760)
            if IsObject(best)
            {
                PerfLog("DevTools_InvokeBestMenuItem fallback anchor-wide-scan")
                return DevTools_ClickOrInvoke(best, mode, mx, my)
            }
        }
    }

    if allowFullScan
    {
        ; 最后兜底：若局部查找失败，再做一次全局扫描
        PerfLog("DevTools_InvokeBestMenuItem fallback full-scan")
        root := UIA.GetRootElement()
        best := DevTools_FindBestMenuItemInElement(root, cond, mode, mx, my, 1100, 760)
        if IsObject(best)
            return DevTools_ClickOrInvoke(best, mode, mx, my)
    }

    return false
}

DevTools_GetCachedMenuAnchor(mode, mx, my)
{
    global DEVTOOLS_MENU_ANCHOR_CACHE
    global DEVTOOLS_MENU_CACHE_TTL_MS
    global DEVTOOLS_MENU_CACHE_DRIFT_X
    global DEVTOOLS_MENU_CACHE_DRIFT_Y
    global DEVTOOLS_MENU_CALL_ROUND
    global DEVTOOLS_MENU_CACHE_DISABLED_ROUND

    if !IsObject(DEVTOOLS_MENU_ANCHOR_CACHE)
        return ""

    hwnd := WinActive("A")
    if !hwnd
        return ""

    if (DEVTOOLS_MENU_ANCHOR_CACHE.hwnd != hwnd)
        return ""

    slotName := (mode = "url") ? "url" : "copy"

    if IsObject(DEVTOOLS_MENU_CACHE_DISABLED_ROUND)
    {
        if (DEVTOOLS_MENU_CACHE_DISABLED_ROUND.%slotName% = DEVTOOLS_MENU_CALL_ROUND)
            return ""
    }

    slot := DEVTOOLS_MENU_ANCHOR_CACHE.%slotName%
    if !IsObject(slot)
        return ""

    if !slot.valid
        return ""

    if (A_TickCount - slot.ts > DEVTOOLS_MENU_CACHE_TTL_MS)
        return ""

    if (Abs(slot.mx - mx) > DEVTOOLS_MENU_CACHE_DRIFT_X || Abs(slot.my - my) > DEVTOOLS_MENU_CACHE_DRIFT_Y)
        return ""

    try anchor := UIA.ElementFromPoint(slot.x, slot.y,, 0)
    catch
        return ""

    return IsObject(anchor) ? anchor : ""
}

DevTools_DisableMenuCacheForCurrentRound(mode)
{
    global DEVTOOLS_MENU_CALL_ROUND
    global DEVTOOLS_MENU_CACHE_DISABLED_ROUND

    slotName := (mode = "url") ? "url" : "copy"
    if !IsObject(DEVTOOLS_MENU_CACHE_DISABLED_ROUND)
        DEVTOOLS_MENU_CACHE_DISABLED_ROUND := {copy: 0, url: 0}

    DEVTOOLS_MENU_CACHE_DISABLED_ROUND.%slotName% := DEVTOOLS_MENU_CALL_ROUND
}

DevTools_RememberMenuAnchor(mode, item, mx, my)
{
    global DEVTOOLS_MENU_ANCHOR_CACHE

    if !IsObject(item)
        return

    try br := item.BoundingRectangle
    catch
        return

    cx := br.l + ((br.r - br.l) // 2)
    cy := br.t + ((br.b - br.t) // 2)

    slotName := (mode = "url") ? "url" : "copy"
    slot := DEVTOOLS_MENU_ANCHOR_CACHE.%slotName%
    if !IsObject(slot)
        slot := {}

    slot.valid := true
    slot.x := cx
    slot.y := cy
    slot.mx := mx
    slot.my := my
    slot.ts := A_TickCount

    DEVTOOLS_MENU_ANCHOR_CACHE.%slotName% := slot
    DEVTOOLS_MENU_ANCHOR_CACHE.hwnd := WinActive("A")
}

DevTools_FindBestMenuItemNearAnchor(anchor, cond, mode, mx, my, nearX := 500, nearY := 360)
{
    bases := []

    if IsObject(anchor)
        bases.Push(anchor)

    try
    {
        p1 := UIA.TreeWalkerTrue.GetParentElement(anchor)
        if IsObject(p1)
            bases.Push(p1)

        p2 := UIA.TreeWalkerTrue.GetParentElement(p1)
        if IsObject(p2)
            bases.Push(p2)
    }
    catch
    {
    }

    for base in bases
    {
        best := DevTools_FindBestMenuItemInElement(base, cond, mode, mx, my, nearX, nearY)
        if IsObject(best)
            return best
    }

    return ""
}

DevTools_FindBestMenuItemInElement(base, cond, mode, mx, my, nearX := 700, nearY := 500)
{
    try items := base.FindAll(cond, UIA.TreeScope.Subtree)
    catch
        return ""

    best := ""
    bestScore := -1

    for item in items
    {
        try name := StrLower(Trim(item.CurrentName))
        catch
            continue

        if (name = "")
            continue

        try br := item.BoundingRectangle
        catch
            continue

        w := br.r - br.l
        h := br.b - br.t
        if (w < 8 || h < 8)
            continue

        cx := br.l + (w // 2)
        cy := br.t + (h // 2)
        if !(Abs(cx - mx) <= nearX && Abs(cy - my) <= nearY)
            continue

        score := DevTools_ScoreMenuItemName(mode, name)

        if (score > bestScore)
        {
            best := item
            bestScore := score
        }
    }

    return (bestScore >= 6) ? best : ""
}

DevTools_ScoreMenuItemName(mode, name)
{
    score := 2

    if (mode = "url")
    {
        if (InStr(name, "复制") || InStr(name, "copy")) && (InStr(name, "url") || InStr(name, "网址") || InStr(name, "链接"))
            score += 20
        if InStr(name, "url")
            score += 8
        if InStr(name, "网址") || InStr(name, "链接")
            score += 7
        if InStr(name, "复制") || InStr(name, "copy")
            score += 4
        if InStr(name, "curl") || InStr(name, "har") || InStr(name, "fetch") || InStr(name, "powershell") || InStr(name, "open") || InStr(name, "source")
            score -= 3
    }
    else
    {
        if (name = "复制" || name = "copy")
            score += 16
        if InStr(name, "复制") || InStr(name, "copy")
            score += 5
        if InStr(name, "url") || InStr(name, "网址") || InStr(name, "链接")
            score -= 8
    }

    return score
}

DevTools_ClickOrInvoke(item, mode := "", mx := 0, my := 0)
{
    try
    {
        item.Click()
        if (mode != "")
            DevTools_RememberMenuAnchor(mode, item, mx, my)
        return true
    }
    catch
    {
    }

    try
    {
        item.Invoke()
        if (mode != "")
            DevTools_RememberMenuAnchor(mode, item, mx, my)
        return true
    }
    catch
    {
        return false
    }
}
;~ 5、URL 解析
ParseAPIPath(url)
{
    pos := InStr(url, "/", false, InStr(url, "://") + 3)
    if !pos
        return ""

    path := SubStr(url, pos)

    qpos := InStr(path, "?")
    if qpos
        path := SubStr(path, 1, qpos - 1)

    return TrimFirstPathSegmentFast(path)
}

TrimFirstPathSegmentFast(path)
{
    if (path = "" || SubStr(path, 1, 1) != "/")
        return path

    pos := InStr(path, "/", false, 2)

    if (pos = 0)
        return ""   ; 只有一层

    return SubStr(path, pos)
}

;~ 6、Controller 搜索（fd + rg）
FindController(path)
{
    global CONFIG

    try
    {
        ; 转换 REST path → 关键词
        keyword := StrReplace(path, "/", " ")

        cmd := Format(
            'cmd /c fd -t f -e java -e ts "{1}" "{2}"',
            keyword,
            CONFIG.projectRoot
        )

        result := ExecCmd(cmd)

        if (result != "")
        {
            lines := StrSplit(result, "`n")
            return lines[1]
        }
    }
    catch
    {
    }

    return ""
}

;~ 7、打开 IDEA
OpenInIDE(file)
{
    global CONFIG

    Run Format('"{1}" "{2}"', CONFIG.ideaPath, file)
}
;~ 8、执行命令工具
ExecCmd(cmd)
{
    shell := ComObject("WScript.Shell")
    exec := shell.Exec(cmd)

    result := exec.StdOut.ReadAll()
    return result
}