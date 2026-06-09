; ===============================================================
;  AppLauncher.ahk - 应用启动框架（普通权限启动 / 路径回退）(AHK v2)
;  从 hotkey.ahk 拆分而来
; ===============================================================
;
; 包含：
;   - openVSCode                    打开 / 切换 VS Code
;   - LaunchVSCodeAsStandardUser    以普通权限启动 VS Code
;   - LaunchQoderAsStandardUser     以普通权限启动 Qoder
;   - ResolveAppPath                路径解析（支持 C/D 盘互换）
;   - LaunchViaLimitedScheduledTask 通过任务计划（LIMITED）启动
;   - ShellExecuteAsStandardUser    通过 Shell.Application 普通权限启动
;   - ResolveShortcutTarget         解析 .lnk 实际目标
;   - QuoteArg                      Windows 参数安全引号
;
; 依赖：
;   - WindowToggle.ahk 提供的 SwapProgramsPrefix
; ===============================================================


; 打开或切换 VS Code：已打开则激活/最小化，否则以普通权限启动
openVSCode(ahkExe, appPath, workspace := "") {
    hwnd := WinExist("ahk_exe " ahkExe)
    if hwnd {
        if WinActive("ahk_id " hwnd) {
            WinMinimize("ahk_id " hwnd)
        } else {
            WinShow("ahk_id " hwnd)
            WinActivate("ahk_id " hwnd)
        }
        return
    }

    LaunchVSCodeAsStandardUser(appPath, workspace)

    ; 启动后尝试激活
    if WinWait("ahk_exe " ahkExe, , 6) {
        WinActivate("ahk_exe " ahkExe)
    }
}

; 以普通权限启动 VS Code（避免管理员权限下打开的文件无法被普通权限访问）
LaunchVSCodeAsStandardUser(appPath, workspace := "") {
    try {
        launchPath := ResolveAppPath(appPath)

        args := "--reuse-window"
        if (workspace != "") {
            args .= " " QuoteArg(workspace)
        }

        launchTarget := ResolveShortcutTarget(launchPath)
        if !LaunchViaLimitedScheduledTask(launchTarget, args, "AHK_LaunchVSCode_Unelevated") {
            throw Error("无法通过任务计划（LIMITED）启动 VS Code。")
        }
    } catch Error as e {
        MsgBox "启动 VSCode 失败:`n" e.Message, "错误", "Iconx"
    }
}

; 以普通权限启动 Qoder
LaunchQoderAsStandardUser(appPath) {
    try {
        launchPath := ResolveAppPath(appPath)
        launchTarget := ResolveShortcutTarget(launchPath)
        if !LaunchViaLimitedScheduledTask(launchTarget, , "AHK_LaunchQoder_Unelevated") {
            throw Error("无法通过任务计划（LIMITED）启动 Qoder。")
        }
    } catch Error as e {
        MsgBox "启动 Qoder 失败:`n" e.Message, "错误", "Iconx"
    }
}

; 解析应用路径，支持 C:/D: 盘前缀回退（依赖 WindowToggle 的 SwapProgramsPrefix）
ResolveAppPath(appPath) {
    primary := appPath
    alternate := SwapProgramsPrefix(primary)

    if FileExist(primary)
        return primary
    if (alternate != "" && FileExist(alternate))
        return alternate

    if (alternate != "") {
        throw Error("路径不存在:`n1) " primary "`n2) " alternate)
    }
    throw Error("路径不存在:`n" primary)
}

; 通过任务计划（LIMITED 权限）启动应用
LaunchViaLimitedScheduledTask(target, args := "", taskName := "AHK_LaunchApp_Unelevated") {
    taskRun := '\"' target '\"'
    if (args != "") {
        taskRun .= " " args
    }

    createCmd := 'schtasks /create /tn "' taskName '" /tr "' taskRun '" /sc ONCE /st 00:00 /rl LIMITED /it /f'
    runCmd := 'schtasks /run /tn "' taskName '"'

    createExitCode := RunWait(createCmd, , "Hide")
    if (createExitCode != 0) {
        return false
    }

    runExitCode := RunWait(runCmd, , "Hide")
    return (runExitCode = 0)
}

; 通过 Shell.Application（Explorer 进程）发起启动，保持普通权限
ShellExecuteAsStandardUser(target, args := "", workDir := "") {
    try {
        if (workDir = "") {
            SplitPath(target, , &workDir)
        }

        shellApp := ComObject("Shell.Application")
        shellApp.ShellExecute(target, args, workDir, "open", 1)
        return true
    } catch {
        return false
    }
}

; 解析 .lnk 快捷方式的实际目标路径
ResolveShortcutTarget(path) {
    if !RegExMatch(path, "i)\.lnk$") {
        return path
    }

    try {
        shortcut := ComObject("WScript.Shell").CreateShortcut(path)
        target := shortcut.TargetPath
        if (target != "" && FileExist(target)) {
            return target
        }
    } catch {
    }

    return path
}

; Windows 参数安全引号（转义内部双引号）
QuoteArg(s) {
    return '"' StrReplace(s, '"', '\"') '"'
}
