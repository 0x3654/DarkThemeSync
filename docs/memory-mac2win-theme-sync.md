---
name: mac2win-theme-sync
description: Синк темы macOS→Windows (Parallels VM) — что установлено + грабли prlctl exec
metadata: 
  node_type: memory
  type: project
  originSessionId: b30fdeff-dd37-4fbf-a0a7-ffab12a1af55
  modified: 2026-09-06T16:57:45.786Z
---

Синхронизация светлой/тёмной темы macOS → VM Parallels «Windows 11» (6.09.2026). Пользователь в VM: `MD2DD\m`, SID `S-1-5-21-2961813680-396835540-796207745-1000`. Тему на маке пользователь переключает Nightfall (r-thomson/Nightfall) — у неё нет ни CLI, ни хуков, поэтому синк через watcher.

Компоненты:
- Mac: `~/bin/mac2win-theme.sh` (poll AppleInterfaceStyle раз в 1 сек) + LaunchAgent `local.mac2win-theme-sync` (KeepAlive, лог `~/Library/Logs/mac2win-theme.log`)
- VM: задача планировщика `MacThemeSync` (запуск от m через vbs-обёртку без мигания окна), скрипты в `C:\Users\Public\MacThemeSync.ps1` / `.vbs`, флаг `C:\Users\Public\mac_theme.txt`

Грабли `prlctl exec` (проверено):
- выполняется от **SYSTEM**, а не от залогиненного пользователя → HKCU пользователя не виден; тему меняет только задача планировщика от пользователя
- лимит длины команды (~5 КБ base64 не проходит, короткие ок) → длинные payload заливать кусками по 400 симв. с проверкой длины
- файлы, созданные SYSTEM в `C:\Windows\Temp`, пользователь читать не может («Отказано в доступе») → использовать `C:\Users\Public`
- из-под launchd PATH без `/usr/local/bin` — prlctl по абсолютному пути/PATH в скрипте

Удаление: `launchctl bootout gui/501/local.mac2win-theme-sync` + rm plist и скрипта; в VM `schtasks /Delete /TN MacThemeSync` + rm `C:\Users\Public\MacThemeSync.*`.
