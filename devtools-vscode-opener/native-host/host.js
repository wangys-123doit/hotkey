#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const { spawn, execSync } = require('child_process');
const os = require('os');

// ─── Path Resolution ────────────────────────────────────────────

function resolveFilePath(inputPath) {
  const p = String(inputPath || '').replace(/\\/g, '/').trim();
  if (!p) return '';
  if (path.isAbsolute(p) || /^[A-Za-z]:[/\\]/.test(p)) return path.normalize(p);

  // BFS: search common project dirs + 1-level subdirs (max depth 2)
  const candidates = new Set([process.cwd()]);
  const home = process.env.USERPROFILE || process.env.HOME || '';
  if (home) {
    for (const sub of ['Desktop', 'Documents', 'code', 'workspace', 'projects', 'repos']) {
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

  const rel = p.replace(/^\/+/, '');
  const skip = new Set(['.git', 'node_modules', 'dist', 'build', 'out', 'coverage', '.vscode']);
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

function pickQoderCmd() {
  const opts = [
    process.env.QODER_PATH,
    'C:/Program Files/Qoder/bin/qoder.cmd',
    'C:/Program Files (x86)/Qoder/bin/qoder.cmd',
    path.join(process.env.LOCALAPPDATA || '', 'Programs/Qoder/bin/qoder.cmd'),
    path.join(process.env.LOCALAPPDATA || '', 'Programs/qoder/bin/qoder.cmd'),
    'D:/Software/Qoder/bin/qoder.cmd'
  ];
  for (const o of opts) if (o && fs.existsSync(o)) return o;
  if (process.platform === 'win32') {
    for (let c = 65; c <= 90; c++) {
      const f = `${String.fromCharCode(c)}:/Software/Qoder/bin/qoder.cmd`;
      if (fs.existsSync(f)) return f;
    }
  }
  return 'qoder.cmd';
}

function pickCodeCmd() {
  for (const o of [process.env.VSCODE_PATH, 'C:/Program Files/Microsoft VS Code/bin/code.cmd', 'C:/Program Files (x86)/Microsoft VS Code/bin/code.cmd']) {
    if (o && fs.existsSync(o)) return o;
  }
  return 'code.cmd';
}

// ─── Window Activation (Windows Virtual Desktop) ────────────────

function activateIdeWindow(processName, projectDir) {
  if (process.platform !== 'win32') return '';
  const projectName = projectDir ? path.basename(projectDir) : '';
  const logFile = path.join(os.tmpdir(), 'ide-vdm-debug.log');

  const cs = [
    'using System;using System.Collections.Generic;using System.IO;using System.Runtime.InteropServices;using System.Text;',
    'public class Vdm {',
    '  [DllImport(\\"user32.dll\\")] static extern bool EnumWindows(EnumWindowsProc f, IntPtr l);',
    '  delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);',
    '  [DllImport(\\"user32.dll\\")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);',
    '  [DllImport(\\"user32.dll\\")] static extern bool IsWindowVisible(IntPtr hWnd);',
    '  [DllImport(\\"user32.dll\\",CharSet=CharSet.Auto)] static extern IntPtr SendMessage(IntPtr hWnd,int m,IntPtr w,StringBuilder l);',
    '  [DllImport(\\"user32.dll\\")] static extern bool ShowWindow(IntPtr hWnd, int n);',
    '  [DllImport(\\"user32.dll\\")] static extern bool SetForegroundWindow(IntPtr hWnd);',
    '  [DllImport(\\"user32.dll\\")] static extern bool IsIconic(IntPtr hWnd);',
    '  [DllImport(\\"user32.dll\\")] static extern void keybd_event(byte vk, byte sc, uint f, UIntPtr e);',
    '  [DllImport(\\"ole32.dll\\")] static extern int CoInitializeEx(IntPtr p, uint d);',
    '  [ComImport,Guid(\\"A5CD92FF-29BE-454C-8D04-D82879FB3F1B\\"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]',
    '  interface IVirtualDesktopManager {',
    '    int IsWindowOnCurrentVirtualDesktop(IntPtr w, out bool on);',
    '    int GetWindowDesktopId(IntPtr w, out Guid id);',
    '  }',
    '  [ComImport,Guid(\\"AA509086-5CA9-4C25-8F95-589D3C07B48A\\")] class VirtualDesktopManagerClass {}',
    '  static string GetTitle(IntPtr h) {',
    '    int len=(int)SendMessage(h,0x000E,IntPtr.Zero,null); if(len<=0) return "";',
    '    var sb=new StringBuilder(len+1); SendMessage(h,0x000D,(IntPtr)sb.Capacity,sb); return sb.ToString();',
    '  }',
    '  public static string FindAndActivate(string proc, string proj, string logF) {',
    '    var log=new List<string>(); CoInitializeEx(IntPtr.Zero,2);',
    '    IVirtualDesktopManager vdm=null;',
    '    try { vdm=(IVirtualDesktopManager)new VirtualDesktopManagerClass(); log.Add("VDM:OK"); }',
    '    catch(Exception e) { log.Add("VDM:FAIL "+e.Message); }',
    '    var pids=new HashSet<uint>();',
    '    foreach(var p in System.Diagnostics.Process.GetProcessesByName(proc)) pids.Add((uint)p.Id);',
    '    log.Add("pids="+pids.Count);',
    '    IntPtr best=IntPtr.Zero,fb=IntPtr.Zero; string bt="",ft="";',
    '    EnumWindows((hwnd,_)=>{',
    '      uint pid; GetWindowThreadProcessId(hwnd,out pid);',
    '      if(!pids.Contains(pid)||!IsWindowVisible(hwnd)) return true;',
    '      bool onCur=false;',
    '      if(vdm!=null) { try{vdm.IsWindowOnCurrentVirtualDesktop(hwnd,out onCur);}catch{onCur=false;} }',
    '      string t=GetTitle(hwnd);',
    '      log.Add("hwnd="+hwnd+" onCur="+onCur+" title="+t);',
    '      if(!onCur) return true;',
    '      if(fb==IntPtr.Zero){fb=hwnd;ft=t;}',
    '      if(!string.IsNullOrEmpty(proj)&&t.IndexOf(proj,StringComparison.OrdinalIgnoreCase)>=0){best=hwnd;bt=t;}',
    '      return true;',
    '    },IntPtr.Zero);',
    '    IntPtr pick=best!=IntPtr.Zero?best:fb; string pickT=best!=IntPtr.Zero?bt:ft;',
    '    if(pick!=IntPtr.Zero) {',
    '      ShowWindow(pick,IsIconic(pick)?3:5);',
    '      keybd_event(0x12,0,0,UIntPtr.Zero); keybd_event(0x12,0,2,UIntPtr.Zero);',
    '      SetForegroundWindow(pick);',
    '      log.Add("ACTIVATED: hwnd="+pick+" title="+pickT);',
    '    } else { log.Add("NO_MATCH"); }',
    '    try{File.AppendAllLines(logF,log);}catch{}',
    '    return pick.ToString();',
    '  }',
    '}'
  ].join('\n');

  const ps = `Add-Type @"\n${cs}\n"@
[Vdm]::FindAndActivate('${processName}','${projectName}','${logFile.replace(/\\/g, '/')}')`;

  const tmp = path.join(os.tmpdir(), `ide-vdm-${Date.now()}.ps1`);
  let hwnd = '';
  try {
    fs.writeFileSync(tmp, ps, 'utf8');
    hwnd = execSync(`powershell -Sta -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "${tmp}"`,
      { timeout: 5000, encoding: 'utf8' }).trim();
  } catch (e) { hwnd = (e.stdout || '').toString().trim(); }
  finally { try { fs.unlinkSync(tmp); } catch {} }
  return hwnd;
}

function reactivateWindow(hwnd) {
  const ps = `Add-Type @"
using System;using System.Runtime.InteropServices;
public class WR {
  [DllImport(\\"user32.dll\\")] static extern bool ShowWindow(IntPtr h,int n);
  [DllImport(\\"user32.dll\\")] static extern bool SetForegroundWindow(IntPtr h);
  [DllImport(\\"user32.dll\\")] static extern void keybd_event(byte v,byte s,uint f,UIntPtr e);
  public static void Go(IntPtr h) {
    ShowWindow(h,5);
    keybd_event(0x12,0,0,UIntPtr.Zero); keybd_event(0x12,0,2,UIntPtr.Zero);
    SetForegroundWindow(h);
    System.Threading.Thread.Sleep(300);
    keybd_event(0x12,0,0,UIntPtr.Zero); keybd_event(0x12,0,2,UIntPtr.Zero);
  }
}
"@
[WR]::Go(${hwnd})`;
  const tmp = path.join(os.tmpdir(), `ide-re-${Date.now()}.ps1`);
  try {
    fs.writeFileSync(tmp, ps, 'utf8');
    execSync(`powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "${tmp}"`, { timeout: 3000 });
  } catch {}
  finally { try { fs.unlinkSync(tmp); } catch {} }
}

// ─── Open File ──────────────────────────────────────────────────

function openFile(file, line, col, ide) {
  const resolved = resolveFilePath(file);
  if (!resolved) throw new Error(`cannot resolve: ${file}`);

  const cwd = findProjectRoot(resolved);
  const isQoder = ide === 'qoder';
  const exe = isQoder ? pickQoderCmd() : pickCodeCmd();
  const processName = isQoder ? 'Qoder' : 'code';

  const targetHwnd = activateIdeWindow(processName, cwd);

  execSync('ping -n 2 127.0.0.1 >nul', { timeout: 5000, stdio: 'ignore' });

  const absFile = resolved.replace(/\\/g, '/');
  const args = ['--reuse-window', '--goto', `${absFile}:${Math.max(1, Number(line) || 1)}:${Math.max(1, Number(col) || 1)}`];
  const isCmdExe = process.platform === 'win32' && (exe.endsWith('code.cmd') || exe.endsWith('qoder.cmd'));
  const child = spawn(isCmdExe ? 'cmd.exe' : exe, isCmdExe ? ['/c', exe, ...args] : args, {
    cwd, detached: true, stdio: 'ignore', env: { ...process.env }
  });
  if (child?.pid) child.unref();

  if (targetHwnd && targetHwnd !== '0') {
    setTimeout(() => reactivateWindow(targetHwnd), 2000);
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
    sendNative({ ok: true, ide, target: `${msg.path}:${msg.line || 1}:${msg.column || 1}` });
  } catch (e) {
    sendNative({ ok: false, ide, error: e?.message });
  }
});
