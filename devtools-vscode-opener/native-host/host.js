#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const os = require('os');

// ─── IDE Workspace Discovery ────────────────────────────────────

/**
 * 通过 PowerShell + VDM 获取当前桌面上 IDE 进程的工作区目录。
 * 从进程命令行参数中提取工作区路径，确保文件搜索优先在已打开的项目中进行。
 */
function findIdeWorkspaces(processName) {
  if (process.platform !== 'win32') return [];
  try {
    const psLines = [
      '$procs = Get-Process -Name \'' + processName + '\' -ErrorAction SilentlyContinue',
      'if (-not $procs) { exit }',
      'Add-Type -AssemblyName System.Management',
      'foreach ($p in $procs) {',
      '  try {',
      '    $wmi = Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)" -ErrorAction SilentlyContinue',
      '    if ($wmi.CommandLine) { Write-Output $wmi.CommandLine }',
      '  } catch {}',
      '}'
    ];
    const out = execSync(
      'pwsh -NoProfile -NonInteractive -Command "' + psLines.join('; ') + '"',
      { encoding: 'utf8', timeout: 4000 }
    ).trim();
    if (!out) return [];

    const workspaces = [];
    for (const line of out.split('\n').map(s => s.trim()).filter(Boolean)) {
      // Extract workspace dirs from command-line args (quoted or unquoted paths)
      const matches = line.match(/"([^"]+)"|(?:^|\s)([A-Za-z]:\\[^\s]+)/g);
      if (!matches) continue;
      for (const m of matches) {
        let dir = m.replace(/^"|"$/g, '').trim();
        // Skip executable paths, only keep workspace directories
        if (/\.(cmd|exe|bat)$/i.test(dir)) continue;
        if (fs.existsSync(dir) && fs.statSync(dir).isDirectory()) {
          workspaces.push(path.resolve(dir));
        }
      }
    }
    return [...new Set(workspaces)];
  } catch { return []; }
}

// ─── Path Resolution ────────────────────────────────────────────

function resolveFilePath(inputPath, ideProcessName) {
  const p = String(inputPath || '').replace(/\\/g, '/').trim();
  if (!p) return '';
  if (path.isAbsolute(p) || /^[A-Za-z]:[/\\]/.test(p)) return path.normalize(p);

  const rel = p.replace(/^\/+/, '');
  const skip = new Set(['.git', 'node_modules', 'dist', 'build', 'out', 'coverage', '.vscode']);

  // Priority 1: Search in IDE workspace directories (already-open projects on current desktop)
  const workspaces = findIdeWorkspaces(ideProcessName || 'Qoder');
  for (const ws of workspaces) {
    const full = path.join(ws, rel);
    if (fs.existsSync(full)) return path.normalize(full);
    // Also search 1-level subdirs within workspace
    try {
      for (const entry of fs.readdirSync(ws, { withFileTypes: true })) {
        if (entry.isDirectory() && !skip.has(entry.name)) {
          const sub = path.join(ws, entry.name, rel);
          if (fs.existsSync(sub)) return path.normalize(sub);
        }
      }
    } catch {}
  }

  // Priority 2: BFS in common project directories
  const candidates = new Set();
  // Add parent dirs of known workspaces (to find sibling projects)
  for (const ws of workspaces) {
    const parent = path.dirname(ws);
    if (parent !== ws) candidates.add(parent);
  }
  const home = process.env.USERPROFILE || process.env.HOME || '';
  if (home) {
    for (const sub of ['code', 'workspace', 'projects', 'repos', 'Desktop', 'Documents']) {
      const dir = path.join(home, sub);
      if (fs.existsSync(dir)) candidates.add(dir);
    }
  }
  if (process.platform === 'win32') {
    for (let c = 65; c <= 90; c++) {
      for (const sub of ['code', 'workspace', 'projects']) {
        const dir = `${String.fromCharCode(c)}:\\${sub}`;
        if (fs.existsSync(dir)) candidates.add(dir);
      }
    }
  }

  for (const dir of candidates) {
    if (fs.existsSync(path.join(dir, rel))) return path.normalize(path.join(dir, rel));
    try {
      for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        if (entry.isDirectory() && !skip.has(entry.name)) {
          const full = path.join(dir, entry.name, rel);
          if (fs.existsSync(full)) return path.normalize(full);
        }
      }
    } catch {}
  }
  return '';
}

function findProjectRoot(filePath) {
  let cur = path.resolve(path.dirname(filePath));
  for (let i = 0; i < 6; i++) {
    if (fs.existsSync(path.join(cur, 'package.json')) || fs.existsSync(path.join(cur, '.git'))) return cur;
    const parent = path.dirname(cur);
    if (parent === cur) break;
    cur = parent;
  }
  return path.resolve(path.dirname(filePath));
}

// ─── Open File (VDM activate + clipboard + Quick Open, single pwsh) ──

function openFile(file, line, col, ide) {
  const processName = ide === 'qoder' ? 'Qoder' : 'code';
  const resolved = resolveFilePath(file, processName);
  if (!resolved) throw new Error(`cannot resolve: ${file}`);

  const cwd = findProjectRoot(resolved);
  const projectName = cwd ? path.basename(cwd) : '';

  // Relative path with :line:col for Quick Open
  const relPath = path.relative(cwd, resolved).replace(/\\/g, '/');
  const lineNum = Math.max(1, Number(line) || 1);
  const colNum = Math.max(1, Number(col) || 1);
  const openPath = `${relPath}:${lineNum}:${colNum}`;

  // Combined C#: VDM window activation + Quick Open keyboard sim
  const cs = [
    'using System;using System.Collections.Generic;using System.IO;using System.Runtime.InteropServices;using System.Text;using System.Threading;',
    'public class VdmKfo {',
    '  [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc f, IntPtr l);',
    '  delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);',
    '  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);',
    '  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);',
    '  [DllImport("user32.dll",CharSet=CharSet.Auto)] static extern IntPtr SendMessage(IntPtr hWnd,int m,IntPtr w,StringBuilder l);',
    '  [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hWnd, int n);',
    '  [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hWnd);',
    '  [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hWnd);',
    '  [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte sc, uint f, UIntPtr e);',
    '  [DllImport("ole32.dll")] static extern int CoInitializeEx(IntPtr p, uint d);',
    '  [ComImport,Guid("A5CD92FF-29BE-454C-8D04-D82879FB3F1B"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]',
    '  interface IVirtualDesktopManager {',
    '    int IsWindowOnCurrentVirtualDesktop(IntPtr w, out bool on);',
    '    int GetWindowDesktopId(IntPtr w, out Guid id);',
    '  }',
    '  [ComImport,Guid("AA509086-5CA9-4C25-8F95-589D3C07B48A")] class VirtualDesktopManagerClass {}',
    '  static string GetTitle(IntPtr h) {',
    '    int len=(int)SendMessage(h,0x000E,IntPtr.Zero,null); if(len<=0) return "";',
    '    var sb=new StringBuilder(len+1); SendMessage(h,0x000D,(IntPtr)sb.Capacity,sb); return sb.ToString();',
    '  }',
    '  static void KeyDown(short vk){keybd_event((byte)vk,0,0,UIntPtr.Zero);}',
    '  static void KeyUp(short vk){keybd_event((byte)vk,0,2,UIntPtr.Zero);}',
    '  public static string Go(string proc, string proj, string logF) {',
    '    var log=new List<string>(); CoInitializeEx(IntPtr.Zero,0);',
    '    IVirtualDesktopManager vdm=null;',
    '    try { vdm=(IVirtualDesktopManager)new VirtualDesktopManagerClass(); log.Add("VDM:OK"); }',
    '    catch(Exception e) { log.Add("VDM:FAIL "+e.Message); }',
    '    var pids=new HashSet<uint>();',
    '    foreach(var p in System.Diagnostics.Process.GetProcessesByName(proc)) pids.Add((uint)p.Id);',
    '    IntPtr best=IntPtr.Zero,fb=IntPtr.Zero;',
    '    EnumWindows((hwnd,_)=>{',
    '      uint pid; GetWindowThreadProcessId(hwnd,out pid);',
    '      if(!pids.Contains(pid)||!IsWindowVisible(hwnd)) return true;',
    '      bool onCur=false;',
    '      if(vdm!=null) { try{vdm.IsWindowOnCurrentVirtualDesktop(hwnd,out onCur);}catch{onCur=false;} }',
    '      if(!onCur) return true;',
    '      string t=GetTitle(hwnd);',
    '      if(fb==IntPtr.Zero) fb=hwnd;',
    '      if(!string.IsNullOrEmpty(proj)&&t.IndexOf(proj,StringComparison.OrdinalIgnoreCase)>=0) best=hwnd;',
    '      return true;',
    '    },IntPtr.Zero);',
    '    IntPtr pick=best!=IntPtr.Zero?best:fb;',
    '    if(pick==IntPtr.Zero) { log.Add("NO_MATCH"); try{File.AppendAllLines(logF,log);}catch{} return ""; }',
    '    ShowWindow(pick,IsIconic(pick)?3:5);',
    '    keybd_event(0x12,0,0,UIntPtr.Zero); keybd_event(0x12,0,2,UIntPtr.Zero);',
    '    SetForegroundWindow(pick);',
    '    Thread.Sleep(600);',
    '    KeyDown(0x11); KeyDown(0x10); KeyDown(0x4E); Thread.Sleep(50); KeyUp(0x4E); KeyUp(0x10); KeyUp(0x11);',
    '    KeyDown(0x11); KeyDown(0x56); Thread.Sleep(80); KeyUp(0x56); KeyUp(0x11);',
    '    Thread.Sleep(200);',
    '    KeyDown(0x0D); Thread.Sleep(50); KeyUp(0x0D);',
    '    Thread.Sleep(300);',
    '    keybd_event(0x12,0,0,UIntPtr.Zero); keybd_event(0x12,0,2,UIntPtr.Zero);',
    '    Thread.Sleep(100);',
    '    keybd_event(0x12,0,0,UIntPtr.Zero); keybd_event(0x12,0,2,UIntPtr.Zero);',
    '    log.Add("OK: hwnd="+pick); try{File.AppendAllLines(logF,log);}catch{}',
    '    return pick.ToString();',
    '  }',
    '}'
  ].join('\n');

  const logFile = path.join(os.tmpdir(), 'ide-vdm-debug.log');
  const ps = `Set-Clipboard -Value '${openPath.replace(/'/g, "''")}'
Add-Type @"\n${cs}\n"@
[VdmKfo]::Go('${processName}','${projectName}','${logFile.replace(/\\/g, '/')}')`;

  const tmp = path.join(os.tmpdir(), `ide-open-${Date.now()}.ps1`);
  try {
    fs.writeFileSync(tmp, ps, 'utf8');
    execSync(`pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "${tmp}"`, { timeout: 10000 });
  } finally {
    try { fs.unlinkSync(tmp); } catch {}
  }
}

// ─── Native Messaging Protocol ──────────────────────────────────

function readNative(cb) {
  let buf = Buffer.alloc(0);
  process.stdin.on('data', d => {
    buf = Buffer.concat([buf, d]);
    if (buf.length >= 4) {
      const len = buf.readUInt32LE(0);
      if (buf.length >= 4 + len) {
        try { cb(null, JSON.parse(buf.slice(4, 4 + len).toString('utf8'))); }
        catch (e) { cb(e); }
      }
    }
  });
}

function sendNative(obj) {
  const b = Buffer.from(JSON.stringify(obj));
  const h = Buffer.alloc(4);
  h.writeUInt32LE(b.length, 0);
  process.stdout.write(Buffer.concat([h, b]));
}

readNative((err, msg) => {
  if (err) return sendNative({ ok: false, error: String(err) });
  if (!msg || msg.action !== 'open' || !msg.path) return sendNative({ ok: false, error: 'invalid message' });

  const ide = msg.ide === 'qoder' ? 'qoder' : 'vscode';
  try {
    openFile(msg.path, msg.line, msg.column, ide);
    sendNative({ ok: true, ide });
  } catch (e) {
    sendNative({ ok: false, ide, error: e?.message });
  }
});
