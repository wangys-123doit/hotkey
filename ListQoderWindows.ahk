; 列出当前虚拟桌面上所有 Qoder 窗口实例
; 使用 DWMWA_CLOAKED 检测（不依赖 COM，兼容性更好）

#Requires AutoHotkey v2.0
#SingleInstance Off

; === 主逻辑 ===
out := "=== Qoder 窗口列表 ===`n"
out .= "检测方法: DWMWA_CLOAKED (非cloaked = 当前桌面)`n"
out .= "========================================`n"

results := []
total := 0
onCurrentCount := 0

for exeName in ["Qoder IDE.exe", "Code.exe"] {
    winList := WinGetList("ahk_exe " exeName)
    out .= exeName " 窗口数: " winList.Length "`n"
    
    for hwnd in winList {
        total++
        title := ""
        try title := WinGetTitle("ahk_id " hwnd)
        pid := 0
        try pid := WinGetPID("ahk_id " hwnd)

        ; DWMWA_CLOAKED (14) - 非0表示窗口被隐藏（不在当前桌面）
        buf := Buffer(4, 0)
        DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 14, "Ptr", buf, "UInt", 4, "Int")
        cloaked := NumGet(buf, 0, "Int")

        ; 尝试获取桌面ID（可能失败）
        winDesktopId := ""
        try {
            vdm := ComObject("{AA509086-5CA9-4C25-8F95-589D3C07B48A}", "{F3163840-895E-45CF-8C8B-37F5E93E22FC}")
            desktopId := Buffer(16)
            ComCall(5, vdm, "Ptr", hwnd, "Ptr", desktopId)
            buf2 := Buffer(39 * 2)
            DllCall("ole32\StringFromGUID2", "Ptr", desktopId, "Ptr", buf2, "Int", 39)
            winDesktopId := StrGet(buf2, "UTF-16")
        } catch {
            winDesktopId := "(COM不可用)"
        }

        ; 判断是否在当前桌面：非cloaked = 当前桌面
        onCurrent := (!cloaked)

        results.Push({
            exe: exeName,
            hwnd: hwnd,
            pid: pid,
            title: title,
            desktopId: winDesktopId,
            cloaked: cloaked,
            onCurrent: onCurrent
        })
    }
}

out .= "========================================`n"

for w in results {
    marker := w.onCurrent ? "✓ 当前桌面" : "  (其他桌面/cloaked)"
    out .= Format("{} `n", marker)
    out .= Format("  exe:     {}`n", w.exe)
    out .= Format("  hwnd:    {}`n", w.hwnd)
    out .= Format("  pid:     {}`n", w.pid)
    out .= Format("  title:   {}`n", w.title)
    out .= Format("  desktop: {}`n", w.desktopId)
    out .= Format("  cloaked: {}`n", w.cloaked)
    out .= "----------------------------------------`n"
    if w.onCurrent
        onCurrentCount++
}

out .= Format("`n总计: {} 个窗口，当前桌面: {} 个`n", total, onCurrentCount)

; 写入文件
FileAppend(out, A_ScriptDir "\qoder_windows.txt", "UTF-8")
MsgBox("结果已写入: " A_ScriptDir "\qoder_windows.txt`n`n" out, "Qoder 窗口列表", "Iconi")
