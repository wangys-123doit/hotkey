#Requires AutoHotkey v2.0
#SingleInstance Force

/**
 * 1. 背景配置 (Background Configuration)
 */
global CHROME_PATH := "C:\Program Files\Google\Chrome\Application\chrome.exe"
global REMOTE_PORT := "9222"
global BRIDGE_URL := "http://localhost:3000/line-number"
global NODE_SCRIPT := A_ScriptDir "\bridge.js"

/**
 * 2. 初始化环境：启动 Chrome 与 Bridge
 */
InitEnvironment() {
    ; 检查 Chrome 是否已经以调试模式启动
    if !ProcessExist("chrome.exe") {
        Run(CHROME_PATH . ' --remote-debugging-port=' . REMOTE_PORT)
    } else {
        ; 如果 Chrome 已运行但未开启调试端口，尝试以独立用户数据目录启动一个可用的调试实例并重试
        try {
            Http := ComObject("WinHttp.WinHttpRequest.5.1")
            Http.Open("GET", "http://localhost:" . REMOTE_PORT . "/json/version", false)
            Http.Send()
        } catch {
            ; 回退：尝试用临时用户数据目录启动独立 Chrome 实例
            tempDir := A_Temp "\\chrome_debug_profile"
            try {
                FileCreateDir(tempDir)
            } catch {
            }

            cmd := CHROME_PATH . ' --remote-debugging-port=' . REMOTE_PORT
                . ' --user-data-dir="' . tempDir . '" --no-first-run --no-default-browser-check'
            try {
                Run(cmd, , "Hide")
            } catch {
            }

            ; 重试探测（最多等待约 2 秒）
            ok := false
            Loop 6 {
                try {
                    Http2 := ComObject("WinHttp.WinHttpRequest.5.1")
                    Http2.Open("GET", "http://localhost:" . REMOTE_PORT . "/json/version", false)
                    Http2.Send()
                    ok := true
                    break
                } catch {
                    Sleep(350)
                }
            }

            if !ok {
                MsgBox("Chrome 正在运行但未开启调试端口。请完全关闭 Chrome 后重新运行此脚本，或允许本脚本以独立用户数据目录启动 Chrome。")
                return
            }
        }
    }

    ; 启动 Node.js Bridge (后台静默启动)
    if !IsBridgeRunning() {
        Run('node "' NODE_SCRIPT '"', , "Hide")
        Sleep(1000) ; 等待服务拉起
    }
}

/**
 * 3. 核心功能：获取行号
 */
GetLineNumber() {
    Http := ComObject("WinHttp.WinHttpRequest.5.1")
    try {
        Http.Open("GET", BRIDGE_URL, true)
        Http.Send()
        if !Http.WaitForResponse(1)
            return "Timeout"
            
        if RegExMatch(Http.ResponseText, '"lineNumber":(\d+)', &match) {
            return match[1]
        }
        return "Not in Source Panel"
    } catch Error as err {
        return "Bridge Offline"
    }
}

; 辅助检查 Bridge 状态
IsBridgeRunning() {
    try {
        Http := ComObject("WinHttp.WinHttpRequest.5.1")
        Http.Open("GET", "http://localhost:3000/line-number", false)
        Http.Send()
        return true
    } catch {
        return false
    }
}

/**
 * 4. 热键绑定 (Hotkey Bindings)
 */

; 初始化环境 (建议手动或随脚本启动)
F10::InitEnvironment()

; 获取行号热键
^!l:: {
    line := GetLineNumber()
    ToolTip("DevTools Line: " . line)
    SetTimer () => ToolTip(), -2000
}

; 强力重启 Chrome 模式 (用于调试环境重置)
+F10:: {
    ProcessClose("chrome.exe")
    Sleep(500)
    InitEnvironment()
}
; 按下 F12 检查全系统链路状态
^F12:: {
    statusReport := "--- 系统链路检查 ---`n"
    
    ; 1. 检查 Chrome 进程
    statusReport .= "Chrome 进程: " . (ProcessExist("chrome.exe") ? "运行中" : "未启动") . "`n"
    
    ; 2. 检查 9222 端口 (CDP)
    try {
        HttpCDP := ComObject("WinHttp.WinHttpRequest.5.1")
        HttpCDP.Open("GET", "http://localhost:9222/json", false)
        HttpCDP.Send()
        statusReport .= "Chrome 调试端口 (9222): 开启`n"
    } catch {
        statusReport .= "Chrome 调试端口 (9222): 关闭 (!!!)`n"
    }
    
    ; 3. 检查 Node.js Bridge
    try {
        HttpBridge := ComObject("WinHttp.WinHttpRequest.5.1")
        HttpBridge.Open("GET", "http://localhost:3000/line-number", false)
        HttpBridge.Send()
        statusReport .= "Node Bridge 服务 (3000): 在线`n"
    } catch {
        statusReport .= "Node Bridge 服务 (3000): 离线 (!!!)`n"
    }
    
    MsgBox(statusReport, "系统诊断", "Iconi")
}