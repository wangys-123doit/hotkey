$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

try {
    Add-Type -Path (Join-Path $PSScriptRoot 'wx_native.cs')
} catch {
    "ADDTYPE ERROR: $($_.Exception.Message)"
    if ($_.Exception.InnerException) { "INNER: " + $_.Exception.InnerException.Message }
    exit 1
}

function I2($v) { if ([double]::IsInfinity($v) -or [double]::IsNaN($v)) { 0 } else { [int]$v } }

$walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
$rawWalker = [System.Windows.Automation.TreeWalker]::RawViewWalker
$root = [System.Windows.Automation.AutomationElement]::RootElement
$out = New-Object System.Text.StringBuilder

$wechatPids = @{}
Get-Process -Name WeChat*,Weixin* -ErrorAction Ignore | ForEach-Object { $wechatPids[$_.Id] = $_.ProcessName }

# 1. 收集微信顶层窗口
$tops = New-Object System.Collections.ArrayList
$child = $rawWalker.GetFirstChild($root)
while ($null -ne $child) {
    try {
        $cur = $child.Current
        if ($wechatPids.ContainsKey($cur.ProcessId)) { [void]$tops.Add(@($child, $cur)) }
    } catch {}
    $child = $rawWalker.GetNextSibling($child)
}
[void]$out.AppendLine("top-level windows: $($tops.Count)")

# 2. 每个窗口：列出直接子 hwnd 类名；对 Chrome_RenderWidgetHostHWND 发 WM_GETOBJECT
foreach ($item in $tops) {
    $cur = $item[1]
    $hwnd = [IntPtr]$cur.NativeWindowHandle
    [void]$out.AppendLine("")
    [void]$out.AppendLine("===== pid=$($cur.ProcessId) hwnd=$hwnd title='$($cur.Name)' =====")
    $kids = [Wx]::Children($hwnd)
    $renderHwnds = New-Object System.Collections.ArrayList
    foreach ($k in $kids) {
        $cls = [Wx]::Class($k)
        $ttl = [Wx]::Title($k)
        if ($ttl.Length -gt 40) { $ttl = $ttl.Substring(0,40) + '..' }
        [void]$out.AppendLine("  child hwnd=$k class=$cls title='$ttl'")
        if ($cls -match 'Chrome_RenderWidgetHostHWND') { [void]$renderHwnds.Add($k) }
    }
    foreach ($r in $renderHwnds) {
        $res = [Wx]::SendWmGetObject($r)
        [void]$out.AppendLine("  WM_GETOBJECT -> hwnd=$r result=$res")
    }
}

Start-Sleep -Milliseconds 1500

# 3. 激活后重新转储 ControlView 树
foreach ($item in $tops) {
    $el = $item[0]; $cur = $item[1]
    [void]$out.AppendLine("")
    [void]$out.AppendLine("========== TREE pid=$($cur.ProcessId) proc=$($wechatPids[$cur.ProcessId]) title='$($cur.Name)' ==========")
    $count = 0
    $stack = New-Object System.Collections.Stack
    $stack.Push(@($el, 0))
    while ($stack.Count -gt 0 -and $count -lt 1500) {
        $pair = $stack.Pop()
        $node = $pair[0]; $depth = $pair[1]
        $count++
        try {
            $c = $node.Current
            $name = $c.Name
            if ($name.Length -gt 60) { $name = $name.Substring(0,60) + '...' }
            $rect = $c.BoundingRectangle
            [void]$out.AppendLine(('  ' * $depth) + "[$($c.ControlType.ProgrammaticName.Replace('ControlType.',''))] name='$name' class='$($c.ClassName)' rect=$(I2 $rect.X),$(I2 $rect.Y),$(I2 $rect.Width)x$(I2 $rect.Height)")
            $children = New-Object System.Collections.ArrayList
            $ch = $walker.GetFirstChild($node)
            while ($null -ne $ch) { [void]$children.Add($ch); $ch = $walker.GetNextSibling($ch) }
            for ($i = $children.Count - 1; $i -ge 0; $i--) { $stack.Push(@($children[$i], $depth + 1)) }
        } catch {
            [void]$out.AppendLine(('  ' * $depth) + "(err: $($_.Exception.Message))")
        }
    }
    if ($count -ge 1500) { [void]$out.AppendLine("... truncated ...") }
}

$out.ToString() | Out-File 'd:\Autohotkey\hotkey\wechat_uia_dump.txt' -Encoding UTF8
"done, length=$($out.Length)"
