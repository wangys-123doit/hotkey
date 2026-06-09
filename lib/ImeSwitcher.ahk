; ===============================================================
;  ImeSwitcher.ahk - 智能中英文输入法自动切换引擎 (AHK v2)
;  从 hotkey.ahk 拆分而来
; ===============================================================
;
; 功能：
;   1. 输入自然语言 → 自动切中文
;   2. 输入代码符号 → 自动切英文
;   3. 行首字母 → 自动切英文（函数、变量命名）
;   4. 不影响 Ctrl / Alt / Win / Shift 组合键
;   5. 所有逻辑只在“普通文本输入”时触发
;
; 依赖：
;   - hotkey.ahk 定义的 ShellGroup（用于区分终端/普通窗口复制方式）
;   - hotkey.ahk 在文件末尾绑定 LWin & z 热键调用 ConvertCharacter()
; ===============================================================


; 输入法当前状态：zh=中文 / en=英文
global g_IME := "zh"

; 切换到中文输入法（如果当前不是中文，则按 Shift 切换）
SwitchToChinese() {
    global g_IME
    if g_IME != "zh" {
        Send "{Shift}"
        ; 确保输入法已进入拼音组合态
        EnsurePinyinReady()
        g_IME := "zh"
    }
}

; 切换到英文输入法（如果当前不是英文，则按 Shift 切换）
SwitchToEnglish() {
    global g_IME
    if g_IME != "en" {
        Send "{Shift}"
        g_IME := "en"
    }
}

; 末尾是字母/数字/下划线 → 代码环境
IsCodeContext() {
    text := GetLeftText("")
    return RegExMatch(text, "[A-Za-z0-9_]$")
}

; 末尾不是字母/数字 → 自然语言环境
IsNaturalContext() {
    return !IsCodeContext()
}

; 行首时输入字母 → 多数情况是写代码
IsLineStart() {
    backup := A_Clipboard
    A_Clipboard := ""

    Send "+{Left}"
    Send WinActive("ahk_group ShellGroup") ? "^{insert}" : "^c"
    ClipWait 0.2
    char := A_Clipboard

    A_Clipboard := backup
    Send "{Right}"

    return (char = "" || char = "`n")
}

; ============================
;    InputHook 输入拦截引擎
; ============================
; global ih := InputHook("V")   ; 'V' = OnChar 事件
; ih.OnChar := (ihObj, char) => HandleChar(char)
; ih.Start()

; 核心策略：根据输入字符和上下文决定输入法状态
HandleChar(char) {
    ; 1. 如果是 Ctrl / Alt / Win 组合，不处理
    if GetKeyState("Ctrl", "P") || GetKeyState("Alt", "P") || GetKeyState("LWin", "P")
        return

    ; 2. 输入字母：判断环境
    if RegExMatch(char, "[A-Za-z]") {
        ; 行首输入字母 = 基本是代码
        if IsLineStart() {
            SwitchToEnglish()
            return
        }
        ; 光标前是代码上下文 → 英文
        if IsCodeContext() {
            SwitchToEnglish()
            return
        }
        ; 否则是自然语言 → 中文
        SwitchToChinese()
        return
    }

    ; 3. 输入代码符号 → 强制英文
    if RegExMatch(char, "[\(\)\{\}\[\]\<\>\=\+\-\*\/\.\:]") {
        SwitchToEnglish()
        return
    }

    ; 4. 中文标点或空格 → 切中文
    if RegExMatch(char, "[，。；：？！、 ]") {
        SwitchToChinese()
        return
    }
}

; 上下文检测：获取光标前内容
; switchType: "" / "punctuation" / "pinyin"
GetLeftText(switchType) {
    backup := A_Clipboard
    A_Clipboard := ""
    Switch switchType {
        Case "punctuation":
            ; 标点符号：只复制光标前一位
            SendEvent "{Shift Down}{Left}{Shift Up}"
        Case "pinyin":
            ; 拼音：复制整个拼音字母
            SendEvent "{Ctrl Down}{Shift Down}{Left}{Ctrl Up}{Shift Up}"
        Default:
            SendEvent "{Ctrl Down}{Shift Down}{Left}{Ctrl Up}{Shift Up}"
    }

    Sleep 20
    ; 终端环境走 Ctrl+Insert，普通窗口走 Ctrl+C
    if WinActive("ahk_group ShellGroup")
        SendEvent "{Ctrl Down}{Insert}{Ctrl Up}"
    else
        SendEvent "{Ctrl Down}{c}{Ctrl Up}"

    if !ClipWait(0.3) {
        A_Clipboard := backup
        return ""
    }
    text := A_Clipboard
    A_Clipboard := backup
    return text
}

; 模拟两次空输入，确保 IME 进入拼音 composing 状态
EnsurePinyinReady() {
    Loop 2 {
        Send "a"
        Sleep 50
        Send "{Backspace}"
        Sleep 20
    }
}

; 转换字符：1. 中文标点 → 英文标点  2. 拼音 → 中文
ConvertCharacter() {
    ; --- 第一步：尝试标点转换 ---
    switchType := "punctuation"
    lastChar := GetLeftText(switchType)

    ; 中文标点集合
    static CN_PUNCT := "，。！？；：、（）【】《》“”‘’·￥—"
    if InStr(CN_PUNCT, lastChar) {
        Switch lastChar {
            Case "…":
            Case "—":
            Case "、":
                Send "+{Left}"
        }
        SwitchPunctuation(true, lastChar)
        return
    }

    ; 英文标点集合：Chr(34)=" Chr(96)=`
    static ENG_PUNCT := ",.;:?!()[]<>\\$" . Chr(34) . Chr(96)
    if InStr(ENG_PUNCT, lastChar) {
        SwitchPunctuation(false, lastChar)
        return
    }

    ; --- 第二步：拼音 → 中文 ---
    switchType := "pinyin"
    text := GetLeftText(switchType)

    ; 匹配末尾连续的英文字母
    word := ""
    if RegExMatch(text, "([A-Za-z]+)$", &m)
        word := m[1]
    if word = ""
        return

    ; 触发 IME 进入拼音 composing
    SendEvent "a"
    Sleep 20
    SendEvent "{Backspace}"
    Sleep 20

    ; 逐字符输入拼音
    for ch in StrSplit(word) {
        SendEvent ch
        Sleep 10
    }
    Sleep 50
    SendInput "{Space}"
}

; 中英文标点互转
; cnToEng: true=中文转英文  false=英文转中文
; char:    待转换的标点字符
SwitchPunctuation(cnToEng, char) {
    static punctuationMap := [
        "，", ",",
        "。", ".",
        "；", ";",
        "：", ":",
        "？", "?",
        "！", "!",
        "（", "(",
        "）", ")",
        "【", "[",
        "】", "]",
        "《", "<",
        "》", ">",
        "、", "// ",
        "“", '"',
        "”", '"',
        "‘", "'",
        "·", Chr(96),   ; 中文点 → 反引号
        "￥", "$",
        "—", "_",
    ]
    for index, value in punctuationMap {
        if (value == char) {
            if (cnToEng) {
                engPunctuation := punctuationMap[index + 1]
            } else {
                engPunctuation := punctuationMap[index - 1]
            }
            SendText(engPunctuation)
            return
        }
    }
}
