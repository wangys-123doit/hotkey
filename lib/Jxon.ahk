; =====================================================
; Jxon.ahk v2 - 轻量 JSON 库 for AHK v2
; 作者: ChatGPT
; 支持: Map/Array
; =====================================================

; -------------------------------
; JSON Load: 字符串 -> Map/Array
; -------------------------------
Jxon_Load(jsonText) {
    src := jsonText    ; ← 关键：创建真正的变量
    pos := 1
    return Jxon_ParseValue(&src, &pos)
}

; -------------------------------
; JSON Save: Map/Array -> 字符串
; -------------------------------
Jxon_Save(obj) {
    ; ----------------------------
    ; 判断对象类型
    ; ----------------------------
    objType := Type(obj)

    if (objType = "Object") {
        ; 区分数组和 Map
        if (obj.HasOwnProperty("Length")) {  ; Array 对象
            return Jxon_SaveArray(obj)
        } else {                             ; Map / 普通对象
            return Jxon_SaveObject(obj)
        }
    }

    if (objType = "Number") {
        return obj
    }

    if (objType = "Bool") {
        return obj ? "true" : "false"
    }

    if (!obj) {
        return "null"
    }

    ; 默认当字符串处理
    return Jxon_Escape(obj)
}


; -------------------------------
; 内部: 转义字符串
; -------------------------------
Jxon_Escape(str) {
    static q := Chr(34)
    str := StrReplace(str, "\", "\\")
    str := StrReplace(str, q, "\\" q)
    str := StrReplace(str, "`n", "\n")
    str := StrReplace(str, "`r", "\r")
    str := StrReplace(str, "`t", "\t")
    return q str q
}

; -------------------------------
; 内部: 解析 JSON 值
; -------------------------------
Jxon_ParseValue(&src, &pos) {
    local ch, val
    Jxon_SkipWhitespace(&src, &pos)
    ch := SubStr(src, pos, 1)

    if (ch = Chr(34)) {
        pos += 1
        return Jxon_ParseString(&src,&pos)
    }

    if (ch ~= "[0-9\-]") {
        return Jxon_ParseNumber(&src,&pos)
    }

    if (SubStr(src, pos, 4) = "true") {
        pos += 4
        return true
    }
    if (SubStr(src, pos, 5) = "false") {
        pos += 5
        return false
    }
    if (SubStr(src, pos, 4) = "null") {
        pos += 4
        return ""
    }
    if (ch = "{") {
        return Jxon_ParseObject(&src,&pos)
    }
    if (ch = "[") {
        return Jxon_ParseArray(&src,&pos)
    }

    Throw "Invalid JSON at position " pos
}

; -------------------------------
; 内部: 跳过空白字符
; -------------------------------
Jxon_SkipWhitespace(&src, &pos) {
    local ch, len := StrLen(src)
    while (pos <= len) {
        ch := SubStr(src, pos, 1)
        if !(ch ~= "\s") {
            break
        }
        pos += 1
    }
}

; -------------------------------
; 内部: 解析字符串
; -------------------------------
Jxon_ParseString(&src, &pos) {
    local ch, out := "", len := StrLen(src)

    while (pos <= len) {
        ch := SubStr(src, pos, 1)
        pos += 1

        ; 遇到结束双引号就退出
        if (ch = Chr(34)) {
            break
        }

        ; 处理转义字符
        if (ch = "\") {
            ch := SubStr(src, pos, 1)
            pos += 1

            if (ch = "n") {
                ch := "`n"
            } else if (ch = "r") {
                ch := "`r"
            } else if (ch = "t") {
                ch := "`t"
            } else if (ch = Chr(34)) {
                ch := Chr(34)
            } else if (ch = "\") {
                ch := "\"
            }
        }

        out .= ch
    }

    return out
}


; -------------------------------
; 内部: 解析数字
; -------------------------------
Jxon_ParseNumber(&src, &pos) {
    local start := pos, len := StrLen(src), ch
    while (pos <= len) {
        ch := SubStr(src, pos, 1)
        if !(ch ~= "[0-9eE\.\-+]")
            break
        pos += 1
    }
    return StrGetSub(src, start, pos - start)
}

StrGetSub(str, start, len) {
    return SubStr(str, start, len)
}

; -------------------------------
; 内部: 解析对象
; -------------------------------
Jxon_ParseObject(&src, &pos) {
    local obj := Map()
    local key, val, ch
    pos += 1  ; 跳过 '{'

    while (true) {
        Jxon_SkipWhitespace(&src,&pos)
        ch := SubStr(src, pos, 1)

        if (ch = "}") {
            pos += 1
            break
        }

        key := Jxon_ParseValue(&src,&pos)
        Jxon_SkipWhitespace(&src,&pos)

        if (SubStr(src, pos, 1) = ":") {
            pos += 1
        } else {
            Throw "Expected ':' at position " pos
        }

        val := Jxon_ParseValue(&src,&pos)
        obj[key] := val

        Jxon_SkipWhitespace(&src,&pos)
        ch := SubStr(src, pos, 1)

        if (ch = ",") {
            pos += 1
        } else if (ch = "}") {
            pos += 1
            break
        } else if (ch != "") {
            Throw "Unexpected character '" ch "' at position " pos
        }
    }

    return obj
}


; -------------------------------
; 内部: 解析数组
; -------------------------------
Jxon_ParseArray(&src, &pos) {
    local arr := []
    local val, ch
    pos += 1  ; 跳过 '['
    while (true) {
        Jxon_SkipWhitespace(&src,&pos)
        ch := SubStr(src, pos, 1)
        if (ch = "]") {
            pos += 1
            break
        }
        val := Jxon_ParseValue(&src,&pos)
        arr.Push(val)

        Jxon_SkipWhitespace(&src,&pos)
        ch := SubStr(src, pos, 1)
        if (ch = ",") {
            pos += 1
        }
    }
    return arr
}

; -------------------------------
; 内部: 保存对象
; -------------------------------
Jxon_SaveObject(obj) {
    local parts := []
    for key, val in obj {
        parts.Push(Jxon_Escape(key) ":" Jxon_Save(val))
    }
    return "{" StrJoin(",", parts) "}"
}

; -------------------------------
; 内部: 保存数组
; -------------------------------
Jxon_SaveArray(arr) {
    local parts := []
    for index, val in arr {
        parts.Push(Jxon_Save(val))
    }
    return "[" StrJoin(",", parts) "]"
}

; -------------------------------
; 内置: 帮助函数 StrJoin
; -------------------------------
StrJoin(sep, arr) {
    local out := ""
    for index, val in arr {
        if (index > 1)
            out .= sep
        out .= val
    }
    return out
}

; =====================================================
; 使用示例：

;~ jsonText := "
;~ (
;~ {
    ;~ ""name"": ""AHK"",
    ;~ ""enabled"": true,
    ;~ ""items"": [1,2,3]
;~ }
;~ )"

;~ obj := Jxon_Load(jsonText)
;~ MsgBox obj["name"]        ; 输出 "AHK"

;~ jsonStr := Jxon_Save(obj)
;~ MsgBox jsonStr

; =====================================================
