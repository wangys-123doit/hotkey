/* SuperFlow.ahk
包含常用的工具自动化操作，如用 Bandizip 解压选中压缩文件
 */
; 用 Bandizip 解压选中压缩文件的公共函数
; targetMode: "here" = 解压到当前目录，"folder" = 解压到同名文件夹
ExtractWithBandizip(targetMode) {
    BandizipPath := "C:\Program Files\Bandizip\Bandizip.exe"
    if !FileExist(BandizipPath) {
        ToolTip("未找到 Bandizip: " BandizipPath)
        SetTimer(() => ToolTip(), -2000)
        return
    }

    ; 备份剪贴板
    backup := ClipboardAll()
    A_Clipboard := ""

    ; 复制选中文件路径
    SendEvent "{Ctrl Down}{Insert}{Ctrl Up}"
    if !ClipWait(1) {
        A_Clipboard := backup
        ToolTip("未选中文件或复制失败")
        SetTimer(() => ToolTip(), -2000)
        return
    }

    selectedFile := Trim(A_Clipboard, " `t`r`n")
    A_Clipboard := backup

    ; 根据模式决定解压目标路径
    SplitPath(selectedFile, , &parentDir, , &nameNoExt)
    targetDir := (targetMode = "folder") ? parentDir "\" nameNoExt : parentDir

    ; Bandizip x: 解压文件，-aoa 覆盖已有文件，-y 自动关闭
    cmd := Format('"{1}" x -aoa -y "{2}" "{3}"', BandizipPath, selectedFile, targetDir)
    Run(cmd, , "Hide")
}

#HotIf WinActive("ahk_class CabinetWClass")
; Alt+E 解压到当前目录
!e::ExtractWithBandizip("here")
; Ctrl+Alt+E 解压到同名文件夹
^!e::ExtractWithBandizip("folder")
#HotIf


; ^!+1 执行git commit,实现在不同开发工具中触发不同的快捷键（Code.exe 触发 Alt+9，idea64.exe 触发 Ctrl+K）              
#HotIf WinActive("ahk_exe Code.exe") || WinActive("ahk_exe Qoder.exe")
    ^!+1::Send "!9"
#HotIf

#HotIf WinActive("ahk_exe idea64.exe")
    ^!+1::Send "^k"
#HotIf

/* SC137::
RCtrl Up:: {
    chromeHwnd := GetChromeHwndOnCurrentDesktop()
    if chromeHwnd && IsChromeDebugPortReady(9223) {
        if WinActive("ahk_id " chromeHwnd) {
            WinMinimize("ahk_id " chromeHwnd)
        } else {
            WinActivate("ahk_id " chromeHwnd)
        }
    } else {
        LaunchChromeWithDebugPort()
    }
} */



