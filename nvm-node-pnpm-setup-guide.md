# nvm / Node.js / pnpm 配置与迁移命令清单（Windows）

本文档整理了本次会话中实际使用过并验证通过的命令，目标是：
- 解决 nvm install lts 异常
- 正常安装并启用 Node.js
- 将 npm / pnpm 的缓存与全局存储迁移到 D 盘
- 保持 nvm 本体仍在 C 盘（不做第六步迁移）

## 0. 前置诊断（可选）

```powershell
nvm version
nvm list available
nvm root
Get-Content "$env:LOCALAPPDATA\nvm\settings.txt"
```

## 1. 修复 nvm 镜像导致的 lts 安装失败

现象：`nvm list available` 显示有版本，但 `nvm install lts` 报未发布/不可下载。

处理：将 node 镜像改为官方源。

```powershell
$settings = "$env:LOCALAPPDATA\nvm\settings.txt"
(Get-Content $settings) -replace '^node_mirror:.*','node_mirror: https://nodejs.org/dist/' | Set-Content $settings -Encoding ASCII
Get-Content $settings
```

安装并启用指定版本：

```powershell
nvm install 24.14.1 64
nvm use 24.14.1
nvm current
where.exe node
where.exe npm
node -v
npm -v
```

## 2. 仅迁移缓存与全局存储到 D 盘（不迁移 nvm 本体）

### 2.1 创建目录

```powershell
New-Item -ItemType Directory -Force -Path 'D:\nodejs\pnpm-store','D:\nodejs\pnpm-home','D:\nodejs\npm-cache','D:\nodejs\npm-global' | Out-Null
```

### 2.2 配置 npm 缓存与全局目录

```powershell
npm config set cache "D:\nodejs\npm-cache" --global
npm config set prefix "D:\nodejs\npm-global" --global
npm config get cache
npm config get prefix
```

### 2.3 启用 pnpm（通过 corepack）

```powershell
corepack enable
corepack prepare pnpm@latest --activate
pnpm -v
```

### 2.4 配置 pnpm 存储与缓存

```powershell
pnpm config set store-dir "D:\nodejs\pnpm-store" --global
pnpm config set cache-dir "D:\nodejs\npm-cache" --global
pnpm config get store-dir
pnpm config get cache-dir
```

### 2.5 设置 PNPM_HOME 到 D 盘并加入 PATH

```powershell
[Environment]::SetEnvironmentVariable('PNPM_HOME','D:\nodejs\pnpm-home','User')
$userPath=[Environment]::GetEnvironmentVariable('Path','User')
if($userPath -notmatch [Regex]::Escape('D:\nodejs\pnpm-home')){
  [Environment]::SetEnvironmentVariable('Path',$userPath + ';D:\nodejs\pnpm-home','User')
}

# 当前会话立即生效
$env:PNPM_HOME='D:\nodejs\pnpm-home'
if($env:Path -notmatch [Regex]::Escape('D:\nodejs\pnpm-home')){
  $env:Path += ';D:\nodejs\pnpm-home'
}
```

## 3. 验证（推荐）

```powershell
pnpm add -g typescript
where.exe tsc
tsc -v
pnpm config list -g
npm config get cache
npm config get prefix
```

预期：
- `tsc` 路径在 `D:\nodejs\pnpm-home`
- pnpm store 在 `D:\nodejs\pnpm-store`
- npm cache 在 `D:\nodejs\npm-cache`

## 4. Git 访问 GitHub 失败时（已验证可用）

如果浏览器能访问 GitHub，但 git 超时：

```powershell
git config --global http.proxy http://127.0.0.1:7897
git config --global https.proxy http://127.0.0.1:7897
```

验证：

```powershell
git ls-remote https://github.com/wangys-123doit/hotkey.git HEAD
```

不再用代理时回滚：

```powershell
git config --global --unset http.proxy
git config --global --unset https.proxy
```

## 5. 回滚命令

### 5.1 回滚 npm 配置

```powershell
npm config delete cache --global
npm config delete prefix --global
```

### 5.2 回滚 pnpm 配置

```powershell
pnpm config delete store-dir --global
pnpm config delete cache-dir --global
```

### 5.3 回滚 PNPM_HOME 环境变量

```powershell
[Environment]::SetEnvironmentVariable('PNPM_HOME',$null,'User')
$userPath=[Environment]::GetEnvironmentVariable('Path','User')
$userPath=($userPath -split ';' | Where-Object { $_ -and $_ -ne 'D:\nodejs\pnpm-home' }) -join ';'
[Environment]::SetEnvironmentVariable('Path',$userPath,'User')
```

## 6. 使用建议

- 你主要使用 pnpm：可不依赖 npm 全局安装，但建议保留 npm cache 在 D 盘。
- 执行完环境变量变更后，重开终端或重启 VS Code。
- 如果 `nvm use` 后 `node` 不可用，先检查 `where.exe node` 和 `settings.txt` 里的 `path` 是否有效。
