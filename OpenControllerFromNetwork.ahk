;~ 1、配置区
global CONFIG := {
    projectRoot: "D:\code\jd-tduck-x-platform",   ; 你的项目路径
    ideaPath: "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\JetBrains\IntelliJ IDEA 2023.2.3.lnk"
}

;~ 2、主入口
^!g::OpenControllerFromNetwork()

;~ ^+g::OpenControllerFromNetwork()

;~ 3、主流程
OpenControllerFromNetwork()
{
    try
    {
        ;~ url := DevTools_GetSelectedURL()
        url := A_Clipboard

        if (url = "")
            throw Error("No URL selected")

        path := ParseAPIPath(url)

        A_Clipboard := path

        ;~ MsgBox A_Clipboard

        /* file := FindController(path)

        if (file = "")
            throw Error("Controller not found")

        OpenInIDE(file)

        ToolTip "Opened: " path
        SetTimer () => ToolTip(), -1000
        */


    }
    catch Error as err
    {
        MsgBox "Error:`n" err.Message
    }
}




;~ 4、DevTools 读取 URL（核心）
DevTools_GetSelectedURL()
{
    hwnd := WinActive("A")

    root := UIA.ElementFromHandle(hwnd)

    ; Property
    ;~ ControlTypePropertyId := 30003

    ;~ ; ControlType
    ;~ Button := 50000
    ;~ Edit := 50004
    ;~ DataItem := 50029
    ;~ Document := 50030
    ; 使用原生常量（最稳定）
    cond := UIA.CreatePropertyCondition(30003, 50029)

    rows := root.FindAll(UIA.TreeScope_Subtree, cond)

    for row in rows
    {
        try
        {
            if row.CurrentIsSelected
            {
                url := row.CurrentName

                if (url != "")
                    return url
            }
        }
    }

    return ""
}
;~ 5、URL 解析
ParseAPIPath(url)
{
    pos := InStr(url, "/", false, InStr(url, "://") + 3)
    if !pos
        return ""

    path := SubStr(url, pos)

    qpos := InStr(path, "?")
    if qpos
        path := SubStr(path, 1, qpos - 1)

    return TrimFirstPathSegmentFast(path)
}

TrimFirstPathSegmentFast(path)
{
    if (path = "" || SubStr(path, 1, 1) != "/")
        return path

    pos := InStr(path, "/", false, 2)

    if (pos = 0)
        return ""   ; 只有一层

    return SubStr(path, pos)
}

;~ 6、Controller 搜索（fd + rg）
FindController(path)
{
    global CONFIG

    try
    {
        ; 转换 REST path → 关键词
        keyword := StrReplace(path, "/", " ")

        cmd := Format(
            'cmd /c fd -t f -e java -e ts "{1}" "{2}"',
            keyword,
            CONFIG.projectRoot
        )

        result := ExecCmd(cmd)

        if (result != "")
        {
            lines := StrSplit(result, "`n")
            return lines[1]
        }
    }
    catch
    {
    }

    return ""
}

;~ 7、打开 IDEA
OpenInIDE(file)
{
    global CONFIG

    Run Format('"{1}" "{2}"', CONFIG.ideaPath, file)
}
;~ 8、执行命令工具
ExecCmd(cmd)
{
    shell := ComObject("WScript.Shell")
    exec := shell.Exec(cmd)

    result := exec.StdOut.ReadAll()
    return result
}