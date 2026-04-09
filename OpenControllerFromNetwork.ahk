;~ 1、配置区
global CONFIG := {
    projectRoot: "D:\code\jd-tduck-x-platform",   ; 你的项目路径
    ideaPath: "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\JetBrains\IntelliJ IDEA 2023.2.3.lnk"
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

        ;~ MsgBox A_Clipboard

        /* file := FindController(path)

        if (file = "")
            throw Error("Controller not found")

        OpenInIDE(file)

        ToolTip "Opened: " path
        SetTimer () => ToolTip(), -1000
        */


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
        ; 优先模拟 DevTools 常规操作：右键 -> 复制 -> 复制 URL
        url := DevTools_CopyURLViaContextMenu()

        if (url = "")
            url := DevTools_GetSelectedURL()

        if (url = "")
            url := DevTools_GetSelectedURLFromClipboard()

        if (url = "")
            throw Error("No selected request URL found in DevTools Network.`n请将鼠标停在 Network 请求行上后再按热键。")

        ; A_Clipboard := url
        ; 解析 URL，提取 path 部分并放入剪贴板 供后续使用
        A_Clipboard := ParseAPIPath(url)
        ; ToolTip "Copied URL: " url
        ; SetTimer () => ToolTip(), -1200
    }
    catch Error as err
    {
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
    clipBak := A_Clipboard
    A_Clipboard := ""

    opened := DevTools_OpenContextMenuOnSelectedRequest(&mx, &my)

    ; 若未拿到选中行，则回退到鼠标位置右键
    if !opened
    {
        MouseGetPos &mx, &my
        Click "Right"
        Sleep 180
    }

    ; 严格按手工路径：先 Copy/复制，再 Copy URL/复制网址
    if DevTools_WaitAndInvokeMenuItem("copy", mx, my)
    {
        Sleep 180
        if DevTools_WaitAndInvokeMenuItem("url", mx, my)
        {
            ClipWait 0.5
            copied := Trim(A_Clipboard)
            A_Clipboard := clipBak
            if RegExMatch(copied, "i)https?://[^\s]+", &m)
                return m[0]
        }
    }

    ; 兜底：部分版本会直接出现 Copy URL 一级菜单
    if DevTools_WaitAndInvokeMenuItem("url", mx, my)
    {
        ClipWait 0.5
        copied := Trim(A_Clipboard)
        A_Clipboard := clipBak
        if RegExMatch(copied, "i)https?://[^\s]+", &m)
            return m[0]
    }

    ; 取消菜单
    Send "{Esc}"
    A_Clipboard := clipBak
    return ""
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

    try br := row.BoundingRectangle
    catch
        return false

    mx := br.l + ((br.r - br.l) // 2)
    my := br.t + ((br.b - br.t) // 2)

    try
    {
        row.Click("Right")
        Sleep 180
        return true
    }
    catch
    {
    }

    ; 兼容某些页面/控件，回退到屏幕坐标右键
    MouseGetPos &oldX, &oldY
    MouseMove mx, my, 0
    Click "Right"
    MouseMove oldX, oldY, 0
    Sleep 180
    return true
}

DevTools_WaitAndInvokeMenuItem(mode, mx, my, retries := 5)
{
    loop retries
    {
        if DevTools_InvokeBestMenuItem(mode, mx, my)
            return true
        Sleep 80
    }
    return false
}

DevTools_InvokeBestMenuItem(mode, mx, my)
{
    root := UIA.GetRootElement()
    cond := UIA.CreatePropertyCondition(UIA.Property.ControlType, UIA.Type.MenuItem)
    items := root.FindAll(cond, UIA.TreeScope.Subtree)

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
        nearCursor := (Abs(cx - mx) <= 700 && Abs(cy - my) <= 500)
        if !nearCursor
            continue

        score := 0
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

        score += 2

        if (score > bestScore)
        {
            bestScore := score
            best := item
        }
    }

    if (bestScore < 6)
        return false

    try
    {
        best.Click()
        return true
    }
    catch
    {
    }

    try
    {
        best.Invoke()
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