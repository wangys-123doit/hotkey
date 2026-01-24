$Target = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
$Arguments   = '--profile-directory=Default --app=https://chat.openai.com --disable-extensions --disable-sync --disable-background-networking --disable-default-apps --disable-component-update --disable-features=TranslateUI,MediaRouter --disable-hang-monitor --no-first-run --no-default-browser-check'
$Lnk    = 'E:\AutoHotKey\apps\ChatGPT.lnk'
$AUMID  = 'ChatGPT'

$Wsh = New-Object -ComObject WScript.Shell
$S = $Wsh.CreateShortcut($Lnk)
$S.TargetPath = $Target
$S.Arguments  = $Arguments
$S.IconLocation = "$Target,0"
$S.WorkingDirectory = Split-Path $Target
$S.Save()

$bytes = [System.Text.Encoding]::Unicode.GetBytes("0$AUMID")
$stream = [System.IO.File]::Open($Lnk, 'Open', 'ReadWrite')
$stream.Seek(0x800, 'Begin') | Out-Null
$stream.Write($bytes, 0, $bytes.Length)
$stream.Close()