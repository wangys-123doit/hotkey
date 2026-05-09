# Copilot instructions for `hotkey`

## Build, test, and lint commands

This repository is primarily an AutoHotkey v2 automation project and does **not** define a repo-wide build/lint/test pipeline.

### Main script (AutoHotkey)

- Run the main script with an AutoHotkey v2 interpreter:
  - `AutoHotkey64.exe .\hotkey.ahk`
- There is no automated test runner for AHK modules in this repo.

### Node bridge helper (`get-source-panel-line-number/`)

- Install dependencies:
  - `cd .\get-source-panel-line-number`
  - `npm install`
- Run the bridge service:
  - `node .\bridge.js`
- Single smoke test (manual, one endpoint):
  - `curl http://localhost:3000/line-number`

## High-level architecture

- `hotkey.ahk` is the entrypoint and orchestrator. It:
  - requires AHK v2,
  - includes shared libs (`lib\Jxon.ahk`, `lib\UIA.ahk`, `lib\UIA_Browser.ahk`),
  - includes functional modules (`hotkeys_public.ahk`, `OpenControllerFromNetwork.ahk`, `rdp.ahk`, `CycleExplorerSwitcher.ahk`),
  - optionally includes `hotkeys_private.ahk` via `#Include *i` for machine/user-private hotstrings.
- Startup flow in `hotkey.ahk`:
  - elevates to admin when needed,
  - registers scheduled task `AutoRunHotkeyTask` once,
  - persists setup flag in `config.ini` (`[Setup] TaskCreated`).
- Browser app subsystem (inside `hotkey.ahk` + `browser_apps.json` + `apps\*.ps1`):
  - loads JSON config with `Jxon_Load`,
  - dynamically binds app hotkeys from `apps[]`,
  - generates `.lnk` shortcuts via PowerShell with AUMID metadata,
  - caches/activates known browser app windows (notably ChatGPT/DMS).
- DevTools automation subsystem:
  - `OpenControllerFromNetwork.ahk` uses UIA-heavy context menu traversal/retry/cache to copy selected Network request URL and extract API path.
  - Optional Node-side bridge in `get-source-panel-line-number\bridge.js` exposes `GET /line-number` using `chrome-remote-interface`.
- RDP subsystem:
  - `rdp.ahk` handles hotkeys, window minimize behavior, and clipboard-signal bridge for local-session minimize requests.
  - `rdp-connect.ps1` resolves host/IP (including short host and MAC mapping) and launches `mstsc`.
- Explorer switcher subsystem:
  - `CycleExplorerSwitcher.ahk` provides a custom Win+E multi-window switcher UI (GUI/ListView + custom draw + modifier-release commit behavior).

## Key repository conventions

- Keep everything AHK v2-compatible (`#Requires AutoHotkey v2.0` patterns and v2 function/object syntax).
- Reuse central window-launch helpers in `hotkey.ahk` (`ToggleWindow*`, `RunAppPathWithPrefixFallback`) instead of duplicating launch/minimize logic.
- For app paths, preserve the existing Windows path-fallback behavior (Programs vs ProgramsCommon swap and protocol-path handling).
- Preserve clipboard safety patterns used across modules:
  - backup clipboard (`ClipboardAll()` or text),
  - perform operation,
  - restore clipboard in `finally`/after use.
- Keep host-specific behavior data-driven with Maps (for example `HOST_MONITOR_MAP`, `RDPHostMap`) instead of hardcoding branches.
- For browser app additions:
  - update `browser_apps.json`,
  - ensure matching generated launcher artifacts in `apps\`,
  - keep hotkeys unique because they are dynamically registered from config.
- Private personal/company hotstrings belong in `hotkeys_private.ahk`; do not move sensitive entries into `hotkeys_public.ahk`.
- Existing docs under `.qoder\repowiki\zh\content\` contain project-specific architecture/operations context; align terminology with those docs when updating behavior.
