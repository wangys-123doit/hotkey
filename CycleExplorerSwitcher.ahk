


AppHotkeyMap := Map(
    "#^e", Map("class", "XLMAIN",         "run", "Excel"),
    "#e",  Map("class", "CabinetWClass",  "run", "explorer"),
    "#a",  Map("class", "windowsApp",  "run", "windowsApp")

)

; 必须放在首个热键定义之前，确保自动执行段会初始化
global g_ExplorerSwitcher := Map(
    "active", false,
    "windows", [],
    "index", 1
)

global g_ExplorerDraw := Map(
    "hooked", false,
    "fontNormal", 0,
    "fontBold", 0,
    "colorNormal", 0x727272,
    "colorSelected", 0x1F1F1F
)

#^e::HandleAppHotkey(A_ThisHotkey) ;~ 打开Excel
#e::CycleExplorerSwitcher() ;~ 类 Alt+Tab：轮询文件资源管理器
; #a:: HandleAppHotkey(A_ThisHotkey) ;~ 打开文件资源管理器

#HotIf IsExplorerSwitcherActive()
Esc::CloseExplorerSwitcher()
#HotIf

EnsureExplorerSwitcherGlobals() {
    global g_ExplorerSwitcher, g_ExplorerDraw

    if !IsSet(g_ExplorerSwitcher) || !IsObject(g_ExplorerSwitcher) {
        g_ExplorerSwitcher := Map(
            "active", false,
            "windows", [],
            "index", 1
        )
    }

    if !IsSet(g_ExplorerDraw) || !IsObject(g_ExplorerDraw) {
        g_ExplorerDraw := Map(
            "hooked", false,
            "fontNormal", 0,
            "fontBold", 0,
            "colorNormal", 0x727272,
            "colorSelected", 0x1F1F1F
        )
    }
}

IsExplorerSwitcherActive() {
    global g_ExplorerSwitcher
    EnsureExplorerSwitcherGlobals()
    return g_ExplorerSwitcher.Has("active") && g_ExplorerSwitcher["active"]
}

CycleExplorerSwitcher() {
    global g_ExplorerSwitcher
    EnsureExplorerSwitcherGlobals()

    windows := GetExplorerWindows()
    if (windows.Length = 0) {
        Run("explorer")
        return
    }

    if (windows.Length = 1) {
        hwnd := windows[1]
        if WinActive("ahk_id " hwnd) {
            WinMinimize("ahk_id " hwnd)
        } else {
            WinActivate("ahk_id " hwnd)
        }
        return
    }

    if !g_ExplorerSwitcher["active"] {
        StartExplorerSwitcher(windows)
        return
    }

    RefreshExplorerSwitcherList(windows)
    g_ExplorerSwitcher["index"] := Mod(g_ExplorerSwitcher["index"], windows.Length) + 1
    HighlightExplorerSwitcherSelection()
}

StartExplorerSwitcher(windows) {
    global g_ExplorerSwitcher
    EnsureExplorerSwitcherGlobals()

    CloseExplorerSwitcher(false)

    g_ExplorerSwitcher["active"] := true
    g_ExplorerSwitcher["windows"] := windows

    activeHwnd := WinActive("A")
    startIndex := 1
    for i, hwnd in windows {
        if (hwnd = activeHwnd) {
            startIndex := (i = windows.Length) ? 1 : (i + 1)
            break
        }
    }
    g_ExplorerSwitcher["index"] := startIndex

    switcherGui := Gui("+AlwaysOnTop -Caption +ToolWindow +Border", "Explorer Switcher")
    switcherGui.BackColor := "FFFFFF"
    switcherGui.MarginX := 10
    switcherGui.MarginY := 10
    ; 默认字体设为普通字重，选中加粗由 CustomDraw 动态处理
    switcherGui.SetFont("s14 c6A6A6A", "Microsoft YaHei UI")

    rowCount := windows.Length
    if (rowCount > 9)
        rowCount := 9

    ; +LV0x8 = LVS_SHOWSELALWAYS，确保当前项底条在 NoActivate 场景也能可见
    ; 使用固定箭头列，避免选中切换时标题抖动
    lv := switcherGui.AddListView("w360 r" rowCount " -Multi -Hdr +LV0x8", ["", "窗口"])
    lv.ModifyCol(1, 24)
    lv.ModifyCol(2, 310)
    ; 使用系统 Explorer 主题，使选中高亮接近 Win11 文件管理器
    try DllCall("uxtheme\SetWindowTheme", "ptr", lv.Hwnd, "str", "Explorer", "ptr", 0)
    EnsureExplorerSwitcherCustomDraw(lv)

    for i, hwnd in windows {
        title := GetExplorerWindowDisplayTitle(hwnd, i)
        lv.Add("", "", title)
    }

    lv.OnEvent("Click", ExplorerSwitcherListClick)

    ; 让 ListView 处于活动态以使用更深的系统选中高亮色
    switcherGui.Show("AutoSize Center")

    g_ExplorerSwitcher["gui"] := switcherGui
    g_ExplorerSwitcher["lv"] := lv
    HighlightExplorerSwitcherSelection()

    ; 使用键状态轮询而不是 Win Up 热键，避免偶发漏触发
    SetTimer(WatchExplorerModifierRelease, 20)
}

WatchExplorerModifierRelease() {
    global g_ExplorerSwitcher

    if !g_ExplorerSwitcher["active"] {
        SetTimer(WatchExplorerModifierRelease, 0)
        return
    }

    if !GetKeyState("LWin", "P") && !GetKeyState("RWin", "P") {
        SetTimer(WatchExplorerModifierRelease, 0)
        CommitExplorerSwitcher()
    }
}

EnsureExplorerSwitcherCustomDraw(lv) {
    global g_ExplorerDraw

    if !g_ExplorerDraw["fontNormal"] {
        g_ExplorerDraw["fontNormal"] := DllCall(
            "CreateFontW",
            "int", -22,
            "int", 0,
            "int", 0,
            "int", 0,
            "int", 400,
            "uint", 0,
            "uint", 0,
            "uint", 0,
            "uint", 1,
            "uint", 0,
            "uint", 0,
            "uint", 5,
            "uint", 0,
            "str", "Microsoft YaHei UI",
            "ptr"
        )
    }

    if !g_ExplorerDraw["fontBold"] {
        g_ExplorerDraw["fontBold"] := DllCall(
            "CreateFontW",
            "int", -22,
            "int", 0,
            "int", 0,
            "int", 0,
            "int", 700,
            "uint", 0,
            "uint", 0,
            "uint", 0,
            "uint", 1,
            "uint", 0,
            "uint", 0,
            "uint", 5,
            "uint", 0,
            "str", "Microsoft YaHei UI",
            "ptr"
        )
    }

    if (g_ExplorerDraw["fontNormal"]) {
        ; WM_SETFONT
        DllCall("SendMessage", "ptr", lv.Hwnd, "uint", 0x30, "ptr", g_ExplorerDraw["fontNormal"], "ptr", 1)
    }

    if !g_ExplorerDraw["hooked"] {
        OnMessage(0x4E, ExplorerSwitcher_OnNotify)
        g_ExplorerDraw["hooked"] := true
    }
}

ExplorerSwitcher_OnNotify(wParam, lParam, msg, hwnd) {
    global g_ExplorerSwitcher, g_ExplorerDraw

    if !g_ExplorerSwitcher.Has("lv") {
        return 0
    }

    lv := g_ExplorerSwitcher["lv"]
    if !IsObject(lv) {
        return 0
    }

    hwndFrom := NumGet(lParam, 0, "ptr")
    if (hwndFrom != lv.Hwnd) {
        return 0
    }

    code := NumGet(lParam, A_PtrSize * 2, "int")
    ; NM_CLICK = -2，直接在通知里处理鼠标点击
    if (code = -2) {
        offItem := (A_PtrSize = 8) ? 24 : 12
        rowNumber := NumGet(lParam, offItem, "int") + 1
        ExplorerSwitcherActivateRow(rowNumber, "NM_CLICK")
        return 0
    }
    ; NM_CUSTOMDRAW
    if (code != -12) {
        return 0
    }

    offDrawStage := (A_PtrSize = 8) ? 24 : 12
    offHdc := (A_PtrSize = 8) ? 32 : 16
    offItemState := (A_PtrSize = 8) ? 64 : 40
    offClrText := (A_PtrSize = 8) ? 80 : 48

    drawStage := NumGet(lParam, offDrawStage, "uint")
    
    ; CDDS_PREPAINT (0x1) -> 请求行级绘制通知
    if (drawStage = 1) {
        return 0x20  ; CDRF_NOTIFYITEMDRAW
    }

    ; CDDS_ITEMPREPAINT (0x10001) -> 行绘制，直接在此应用颜色和字体
    if (drawStage = 0x10001) {
        itemState := NumGet(lParam, offItemState, "uint")
        isSelected := (itemState & 0x0001) != 0
        hdc := NumGet(lParam, offHdc, "ptr")

        if isSelected {
            ; 选中：纯黑+加粗
            NumPut("uint", g_ExplorerDraw["colorSelected"], lParam, offClrText)
            if (g_ExplorerDraw["fontBold"])
                DllCall("SelectObject", "ptr", hdc, "ptr", g_ExplorerDraw["fontBold"])
        } else {
            ; 未选中：灰色+普通字重
            NumPut("uint", g_ExplorerDraw["colorNormal"], lParam, offClrText)
            if (g_ExplorerDraw["fontNormal"])
                DllCall("SelectObject", "ptr", hdc, "ptr", g_ExplorerDraw["fontNormal"])
        }

        return 0x2  ; CDRF_NEWFONT
    }

    return 0
}

ExplorerSwitcherActivateRow(rowNumber, source := "") {
    global g_ExplorerSwitcher

    if (rowNumber < 1)
        return

    windows := g_ExplorerSwitcher.Has("windows") ? g_ExplorerSwitcher["windows"] : []
    if !windows.Length || (rowNumber > windows.Length)
        return
    ; 调试用提示，正式使用可注释掉
    /* lv := g_ExplorerSwitcher.Has("lv") ? g_ExplorerSwitcher["lv"] : 0
    if IsObject(lv) {
        title := lv.GetText(rowNumber, 2)
        ToolTip(source " 触发`n行号: " . rowNumber . "`n标题: " . title)
        SetTimer(() => ToolTip(), -2500)
    } */

    targetHwnd := windows[rowNumber]
    CloseExplorerSwitcher(false)

    if WinExist("ahk_id " targetHwnd) {
        WinActivate("ahk_id " targetHwnd)
    }
}

RefreshExplorerSwitcherList(windows) {
    global g_ExplorerSwitcher

    if !g_ExplorerSwitcher.Has("lv") {
        return
    }

    g_ExplorerSwitcher["windows"] := windows

    lv := g_ExplorerSwitcher["lv"]
    lv.Delete()

    for i, hwnd in windows {
        title := GetExplorerWindowDisplayTitle(hwnd, i)
        lv.Add("", "", title)
    }

    if (g_ExplorerSwitcher["index"] > windows.Length) {
        g_ExplorerSwitcher["index"] := 1
    }
}

HighlightExplorerSwitcherSelection() {
    global g_ExplorerSwitcher

    if !g_ExplorerSwitcher.Has("lv") {
        return
    }

    lv := g_ExplorerSwitcher["lv"]
    idx := g_ExplorerSwitcher["index"]

    if (idx < 1 || idx > lv.GetCount()) {
        return
    }

    windows := g_ExplorerSwitcher["windows"]
    Loop lv.GetCount() {
        i := A_Index
        if (i > windows.Length)
            break
        title := GetExplorerWindowDisplayTitle(windows[i], i)
        arrow := (i = idx) ? "▶" : ""
        lv.Modify(i, "", arrow, title)
    }

    lv.Modify(0, "-Select")
    lv.Modify(idx, "Select Focus Vis")
}

GetExplorerWindowDisplayTitle(hwnd, index) {
    title := WinGetTitle("ahk_id " hwnd)
    if (title = "") {
        return "文件资源管理器 " index
    }
    return RegExReplace(title, "\s*-\s*文件资源管理器$")
}

ExplorerSwitcherListClick(ctrl, RowNumber) {
    global g_ExplorerSwitcher

    rowNumber := Integer(RowNumber)
    if (rowNumber < 1)
        rowNumber := ctrl.GetNext(0, "S")
    ExplorerSwitcherActivateRow(rowNumber, "Click")
}

CommitExplorerSwitcher(forceIndex := 0) {
    global g_ExplorerSwitcher

    if !g_ExplorerSwitcher["active"] {
        return
    }

    windows := g_ExplorerSwitcher["windows"]
    idx := (forceIndex > 0) ? forceIndex : g_ExplorerSwitcher["index"]
    targetHwnd := 0

    if (idx >= 1 && idx <= windows.Length) {
        targetHwnd := windows[idx]
    }

    CloseExplorerSwitcher(false)

    ; 让 GUI 先销毁，再激活目标窗口，减少焦点竞争
    if (targetHwnd) {
        SetTimer(() => ActivateExplorerWindow(targetHwnd), -10)
    }
}

CloseExplorerSwitcher(showTip := true) {
    global g_ExplorerSwitcher

    SetTimer(WatchExplorerModifierRelease, 0)

    if g_ExplorerSwitcher.Has("gui") {
        try g_ExplorerSwitcher["gui"].Destroy()
    }

    g_ExplorerSwitcher := Map(
        "active", false,
        "windows", [],
        "index", 1
    )

    if showTip {
        ToolTip("已取消切换")
        SetTimer(() => ToolTip(), -800)
    }
}

GetExplorerWindows() {
    return WinGetList("ahk_class CabinetWClass")
}

ActivateExplorerWindow(hwnd) {
    if !WinExist("ahk_id " hwnd) {
        return
    }

    state := WinGetMinMax("ahk_id " hwnd)
    if (state = -1) {
        WinRestore("ahk_id " hwnd)
    }

    ; 激活带重试，降低焦点竞争导致的失败概率
    Loop 2 {
        WinActivate("ahk_id " hwnd)
        if WinWaitActive("ahk_id " hwnd, , 0.2) {
            return
        }
        Sleep 30
    }

    ; 少数情况下需要先发送一次 Alt 再激活
    SendEvent "{Alt}"
    WinActivate("ahk_id " hwnd)
}


HandleAppHotkey(hotkey) {
    global AppHotkeyMap

    if !AppHotkeyMap.Has(hotkey)
        return

    cfg := AppHotkeyMap[hotkey]
    global Switcher
    if (Switcher.Has("initialized")) {
        CloseSwitcher()
    } else {  ; GUI 不存在 → 显示
        InitSwitcher(cfg["class"])

    }
    if (cfg["class"] == "windowsApp") {
        return
    }
    ;~ 如果未启动
    if !WinExist("ahk_class " cfg["class"]){
        ;~ 未启动时发送指令键启动程序
        Run(cfg["run"])
    }
}



; ==============================
; 窗口选择器对象
; ==============================
global Switcher := Map()

; ==============================
; 初始化 窗口选择器对象
; ahk_class:
; CabinetWClass：文件资源管理器
; XLMAIN：Excel
; ==============================
InitSwitcher(ahk_class) {
    global Switcher
    ;~ ToolTip(ahk_class)
    ; 获取所有符合条件的窗口句柄（按类名“CabinetWClass”）
    windows := []
    Switch ahk_class
    {
    ;~ 判断如果是标点符号则发送shift left 只复制光标前一位标点符号
    Case "windowsApp":

    Case "pinyin":
        ;~ 非标点符号则则发送ctrl+shift left复制整个拼音字母
        SendInput "{Ctrl Down}{Shift Down}{Left}{Ctrl Up}{Shift Up}"
    Default:
        windows := WinGetList("ahk_class " ahk_class)

    }
    ; 如果只有一个窗口，则return不显示窗口列表弹窗
    if (windows.Length = 1) {
        hwnd := windows[1]

        if WinActive("ahk_id " hwnd) {
            WinMinimize "ahk_id " hwnd
        } else {
            WinActivate "ahk_id " hwnd
        }
        return
    }
    ;~ appMap := Map()
    ;~ appMap["CabinetWClass"] := "文件资源管理器"
    ;~ appMap["XLMAIN"] := "Excel"
    ;~ 查找如果有AutoHotkeyGUI则先WinClose，然后重新生成AppListView
    ;~ if WinExist("ahk_class AutoHotkeyGUI"){

        ;~ windows_gui := WinGetList("ahk_class AutoHotkeyGUI")
        ;~ for winID in windows_gui {
            ;~ ;
            ;~ if(WinGetTitle(winID) == appMap[ahk_class] and WinExist("ahk_id " winID)){
                 ;~ WinClose
                ;~ break
            ;~ }
        ;~ }

    ;~ }


    if Switcher.Has("initialized")
        return

    Switcher["initialized"] := true

    ; 创建 GUI
    Switcher.gui := Gui()
    Switcher.gui.Opt("+AlwaysOnTop -Caption +ToolWindow")
    ; 显示窗口列表（调试用）
    LV := Switcher.gui.AddListView("r8 w200 vColorChoice", ["#", "文件名"])
    Switcher.LV := LV   ; 保存到 Switcher 对象里

    winList := []
    for winID in windows {
        ;MsgBox WinGetTitle(winID)
        word_array := StrSplit(WinGetTitle(winID), " - ")
        if(A_Index == 1){
            ;~ MyGuiSwitcher.gui.Title := word_array[2]
        }
        LV.Add(, A_Index, word_array[1])

        winList.Push(A_Index)
    }
    Switcher["winListLength"] := winList.Length

    LV.OnEvent("Click", LV_Click)
    LV_Click(LV, RowNumber)
    {
        if (!RowNumber) {
            return
        }
        HotkeyActivateWindow(RowNumber)
    }
    ;~ 数字热键绑定激活对应窗口 todo
    ;~ Loop winList.Length {
        ;~ if (A_Index > 9)
            ;~ break
        ;~ Hotkey("~" . A_Index, HotkeyActivateWindow)
    ;~ }

    HotkeyActivateWindow(ThisHotkey) {
        index := RegExReplace(ThisHotkey, "^\D+")

        if windows.Has(index) && WinExist("ahk_id " windows[index]) {
            WinActivate("ahk_id " windows[index])
        } else {
            LV.Delete(index)
        }
    }


    ; 尺寸 & 位置
    Switcher.w := 200
    Switcher.h := 160
    Switcher.showX := 0
    Switcher.hiddenX := -Switcher.w
    Switcher.y := (A_ScreenHeight - Switcher.h) // 2

    ; 状态
    Switcher["visible"] := false
    Switcher.sliding := false
    Switcher.lastHover := 0

    SlideIn()
    ;~ Switcher.gui.Show("NoActivate")

    ; 初始隐藏
    ;~ Switcher.gui.Show("x" Switcher.hiddenX " y" Switcher.y " w" Switcher.w " h" Switcher.h " NoActivate")

    ; 开启定时器检查鼠标
    SetTimer(CheckMouse, 30)
}

; ==============================
; 滑入动画
; ==============================
SlideIn() {
    global Switcher

    if (Switcher["visible"] || Switcher.sliding)
        return

    Switcher.sliding := true
    Switcher.gui.Show("NoActivate")
    ;~ Switcher.gui.Show()

    x := Switcher.hiddenX
    while (x < Switcher.showX) {
        x += 20
        if (x > Switcher.showX)
            x := Switcher.showX
        Switcher.gui.Move(x, Switcher.y)
        Sleep 10
    }

    Switcher["visible"] := true
    Switcher.sliding := false

    ; 初始化 lastHover 防止立即滑出
    Switcher.lastHover := A_TickCount

    ; 动画结束后确保第一个项目被选中
    LV := Switcher.LV
    if LV.GetCount() > 0 {
        LV.Modify(1, "Select")
        LV.Focus()
        LV.Modify(1, "Focus")

        ;~ hwnd := LV.Hwnd
        ;~ x1 := 0, y1 := 0, w := 0, h := 0
        ;~ LV_GetItemRect(hwnd, 1, &x1, &y1, &w, &h)

        ;~ mouseX := Switcher.gui.X + x1 + w // 2
        ;~ mouseY := Switcher.gui.Y + y1 + h // 2

        ;~ MouseMove(mouseX, mouseY, 0)
    }
}

; ==============================
; 滑出动画
; ==============================
SlideOut() {
    global Switcher

    if (!Switcher["visible"] || Switcher.sliding)
        return

    Switcher.sliding := true

    x := Switcher.showX
    while (x > Switcher.hiddenX) {
        x -= 20
        if (x < Switcher.hiddenX)
            x := Switcher.hiddenX
        Switcher.gui.Move(x, Switcher.y)
        Sleep 10
    }

    Switcher.gui.Hide()
    Switcher["visible"] := false
    Switcher.sliding := false
}

; ==============================
; 检查鼠标位置，决定滑入/滑出
; ==============================
CheckMouse() {
    global Switcher

    static EDGE_TRIGGER := 3          ; 离屏幕左侧 px
    static EDGE_HOLD_TIME := 200      ; 停留 ms 才算有意图
    static GUI_HOVER_PAD := 10
    static HIDE_DELAY := 500

    static edgeEnterTime := 0

    ; 坐标模式：屏幕绝对坐标
    CoordMode("Mouse", "Screen")
    MouseGetPos &mx, &my
    now := A_TickCount

    ; ==============================
    ; ① GUI 未显示：靠近屏幕左侧才滑入
    ; ==============================
    if (!Switcher["visible"] && !Switcher.sliding) {

        if (mx <= EDGE_TRIGGER) {
            if (edgeEnterTime = 0)
                edgeEnterTime := now

            if (now - edgeEnterTime >= EDGE_HOLD_TIME) {
                SlideIn()
                edgeEnterTime := 0
            }
        } else {
            edgeEnterTime := 0
        }
        return
    }

    ; ==============================
    ; ② GUI 已显示：鼠标在 GUI 内 → 永不隐藏
    ; ==============================
    if (Switcher["visible"] && !Switcher.sliding) {

        ; 获取 GUI 坐标和尺寸
        Switcher.gui.GetPos(&x, &y, &w, &h)
        ;~ ToolTip("x" X . "y" Y . "Width " Width . "Height" Height)
        ; 判断鼠标是否在 GUI 内
        if (mx >= x - GUI_HOVER_PAD
            && mx <= x + w + GUI_HOVER_PAD
            && my >= y - GUI_HOVER_PAD
            && my <= y + h + GUI_HOVER_PAD) {

                Switcher.lastHover := now
                return
            }

            ; ==============================
            ; ③ GUI 离开延迟隐藏
            ; ==============================
            if (now - Switcher.lastHover > HIDE_DELAY) {
                SlideOut()
            }
    }
}

CloseSwitcher() {
    global Switcher
    if (!Switcher.Has("initialized")) {
        return
    }
    ; 隐藏 GUI
    ;~ Switcher.gui.Hide()
    Switcher.gui.Destroy()

    ;~ Loop Switcher["winListLength"] {
        ;~ if (A_Index > 9)
            ;~ break
        ;~ Hotkey("~" . A_Index, "Off")
    ;~ }
    ;~ 清空map
    Switcher.Clear()

    ; 停掉鼠标监听定时器
    SetTimer(CheckMouse, 0)
    ; 显示提示
    ToolTip("已关闭窗口选择器")

    ; 1 秒后自动消失
    SetTimer(() => ToolTip(), -1000)  ; -1000 表示一次性计时器
}