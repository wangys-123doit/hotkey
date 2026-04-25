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
        return "Error"    
    } catch Error as err {
        return "Offline"
    }
}

; 热键绑定
/* ~^!l:: {
    line := GetLineNumberFromBridge()
    ToolTip("Line: " . line)
    SetTimer () => ToolTip(), -2000 ; 2秒后消失
} */