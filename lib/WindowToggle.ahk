; ===============================================================
;  WindowToggle.ahk - 窗口切换与应用启动框架 (AHK v2)
;  从 hotkey.ahk 拆分而来
; ===============================================================
;
; 包含：
;   - SwapProgramsPrefix        程序路径前缀互换（C 盘 / D 盘）
;   - RunAppPathWithPrefixFallback 带路径回退的应用启动
;   - BlockWinPFor              临时屏蔽 Win+P
;   - ToggleWindow / ToggleWindowByTitle / ToggleWindow2
;   - GetMainWindowByExe        过滤可见+有标题的主窗口
;
; 依赖：无（仅使用 AHK v2 内置 API）
; ===============================================================


; 互换程序路径前缀：C:\ProgramData\...\Start Menu\Programs ↔ 当前用户的 Programs
SwapProgramsPrefix(path) {
    if InStr(path, A_ProgramsCommon, false) = 1 {
        return A_Programs SubStr(path, StrLen(A_ProgramsCommon) + 1)
    }
    if InStr(path, A_Programs, false) = 1 {
        return A_ProgramsCommon SubStr(path, StrLen(A_Programs) + 1)
    }
    return ""
}

; 启动应用，支持协议路径 / 主路径 / 互换前缀的回退路径
RunAppPathWithPrefixFallback(path) {
    ; 协议路径（如 ms-phone: / obsidian://）直接运行，不做文件存在判断
    if (RegExMatch(path, "i)^[a-z][a-z0-9+.-]*:(//)?") && !RegExMatch(path, "i)^[a-z]:\\")) {
        try {
            Run path
            return true
        } catch Error as e {
            MsgBox("协议启动失败：`n" path "`n`n" e.Message, "启动失败", 16)
            return false
        }
    }

    primary := path
    alternate := SwapProgramsPrefix(primary)

    if FileExist(primary) {
        try {
            Run primary
            return true
        } catch Error as e {
            MsgBox("启动失败：`n" primary "`n`n" e.Message, "启动失败", 16)
            return false
        }
    }

    if (alternate != "" && FileExist(alternate)) {
        try {
            Run alternate
            return true
        } catch Error as e {
            MsgBox("启动失败：`n" alternate "`n`n" e.Message, "启动失败", 16)
            return false
        }
    }

    if (alternate != "") {
        MsgBox("路径不存在：`n1) " primary "`n2) " alternate, "启动失败", 16)
    } else {
        MsgBox("路径不存在：`n" primary, "启动失败", 16)
    }

    return false
}

; 在指定毫秒内临时屏蔽 Win+P（避免显示器切换干扰）
BlockWinPFor(durationMs := 300) {
    static handler := (*) => 0
    Hotkey("#p", handler, "On")
    SetTimer(() => Hotkey("#p", handler, "Off"), -durationMs)
}

; 按进程名切换窗口：存在则激活/最小化切换，不存在则启动
ToggleWindow(ahk_exe, APP_PATH) {
    if WinExist("ahk_exe " ahk_exe) {
        if WinActive("ahk_exe " ahk_exe) {
            WinMinimize
        } else {
            WinActivate
        }
    } else {
        RunAppPathWithPrefixFallback(APP_PATH)
    }
}

; 按窗口标题切换窗口
ToggleWindowByTitle(ahk_exe, WinTitle, APP_PATH) {
    if WinExist(WinTitle) {
        if WinActive(WinTitle) {
            WinMinimize
        } else {
            WinActivate
        }
    } else {
        RunAppPathWithPrefixFallback(APP_PATH)
    }
}

; 按进程名+标题切换，排除 "Photos and Videos"（微信图片查看器）
ToggleWindow2(ahk_exe, WinTitle, APP_PATH) {
    if WinExist("ahk_exe " ahk_exe, WinTitle, "Photos and Videos") {
        if WinActive("ahk_exe " ahk_exe, WinTitle, "Photos and Videos") {
            WinMinimize
        } else {
            WinActivate
        }
    } else {
        RunAppPathWithPrefixFallback(APP_PATH)
    }
}

; 过滤「可见 + 有标题」的主窗口（排除后台隐藏窗口）
GetMainWindowByExe(ahk_exe, winTitle) {
    static WS_VISIBLE := 0x10000000
    hwnds := WinGetList("ahk_exe " ahk_exe)
    for hwnd in hwnds {
        title := WinGetTitle("ahk_id " hwnd)
        style := WinGetStyle("ahk_id " hwnd)
        if (title == winTitle && (style & WS_VISIBLE))
            return hwnd
    }
    return 0
}
