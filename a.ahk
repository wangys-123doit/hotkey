#Requires AutoHotkey v2.0

/**
 * 获取行号请求封装
 */
GetLineNumberFromBridge() {
    Http := ComObject("WinHttp.WinHttpRequest.5.1")
    try {
        Http.Open("GET", "http://localhost:3000/line-number", true)
        Http.Send()
        if !Http.WaitForResponse(1) ; 1秒超时
            return "Timeout"
            
        ; 简单的 JSON 解析逻辑（生产环境建议使用专用的 JSON 库）
        response := Http.ResponseText
        if RegExMatch(response, '"lineNumber":(\d+)', &match) {
            return match[1]
        }
        if RegExMatch(response, '"error"\s*:\s*"([^"]+)"', &errMatch) {
            return errMatch[1]
        }
        return "Not in Source Panel"    
    } catch Error as err {
        return "Offline"
    }
}

EnsureBridgeRunning() {
    if IsBridgeRunning() {
        return true
    }

    bridgeScript := A_ScriptDir "\run_bridge.ps1"
    if FileExist(bridgeScript) {
        try {
            Run('powershell -NoProfile -ExecutionPolicy Bypass -File "' bridgeScript '"', , "Hide")
        } catch {
        }
    }

    Loop 6 {
        if IsBridgeRunning() {
            return true
        }
        Sleep 150
    }

    return false
}

IsBridgeRunning() {
    Http := ComObject("WinHttp.WinHttpRequest.5.1")
    try {
        Http.Open("GET", "http://localhost:3000/line-number", false)
        Http.Send()
        return true
    } catch {
        return false
    }
}

; 热键绑定（仅在 Chrome 激活时生效）
#HotIf WinActive("ahk_exe chrome.exe")
!l:: {
    if !EnsureBridgeRunning() {
        ToolTip("Bridge 未启动")
        SetTimer () => ToolTip(), -2000
        return
    }

    line := GetLineNumberFromBridge()
    ToolTip("Line: " . line)
    SetTimer () => ToolTip(), -2000 ; 2秒后消失
}
#HotIf