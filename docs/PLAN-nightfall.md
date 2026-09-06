# План: встроить синк темы Windows прямо в Nightfall («коробка»)

Цель: галка в настройках Nightfall «Переключать тему Windows (Parallels VM)».
Когда включена — Nightfall при смене темы сам запускает переключение в VM.
Никаких внешних watcher'ов и LaunchAgent; после этого текущую связку (~/bin/mac2win-theme.sh + LaunchAgent) отключаем.

База: клон в `nightfall-fork/` (upstream r-thomson/Nightfall, MIT). Swift 6.3 / Xcode есть на маке, приложение установлено в /Applications/Nightfall.app и запущено.

## Что внутри Nightfall (по первому осмотру репо)

- `Nightfall/` — исходники приложения (menubar), `NightfallLauncher` — лаунчер, `Nightfall.xcodeproj` — проект.
- README упоминает `ToggleDarkMode.swift` — вся логика переключения в одной внутренней функции, внешних интерфейсов автоматизации нет (проверено — ни CLI, ни URL scheme, ни хуков).

## Изменения

1. **Настройки**: в существующее меню опций добавить пункт-галку
   `Sync Windows theme (Parallels)` + поле «VM name» (default `Windows 11`).
   Хранить в UserDefaults (как остальные настройки Nightfall).
2. **Хук переключения**: в точке смены темы (там, где Nightfall вызывает системный API —
   найти по `ToggleDarkMode`/`NSAppearance`/`AppleInterfaceAppearance`) после успешной смены темы, если галка включена, выполнить:
   ```swift
   Process("/usr/local/bin/prlctl", ["exec", vmName, "powershell", "-NoProfile", "-Command",
       "Set-Content C:\\Users\\Public\\mac_theme.txt '<dark|light>'; schtasks /Run /TN MacThemeSync"])
   ```
   — асинхронно (async detached), ошибки молча игнорировать (VM выключена — не проблема).
   Механизм в VM (задача MacThemeSync + C:\Users\Public\MacThemeSync.ps1) остаётся как есть:
   он нужен, потому что prlctl exec работает от SYSTEM (см. грабли в README).
3. **Синхронизация при старте** (опционально, вместо watcher'а): при запуске Nightfall и при пробуждении мака
   (NSWorkspaceDidWakeNotification) один раз пушить текущую тему — закрывает случай «винда загрузилась, пока мак уже тёмный».
4. UI-строки — на английском, в стиле приложения (локализаций в Nightfall нет).

## Сборка и установка

```bash
cd nightfall-fork
xcodebuild -project Nightfall.xcodeproj -scheme Nightfall -configuration Release build
# скопировать Nightfall.app в /Applications (закрыв запущенный экземпляр)
```

Подпись: у Nightfall нет Developer ID — сборка будет ad-hoc/unsigned; при замене в /Applications
снять quarantine у своей сборки не нужно (собрано локально), но запускать придётся через правый клик при первом старте, если Gatekeeper заругается.

## Откат на watcher

Если своя сборка надоест: вернуть LaunchAgent (файлы в `mac/`), выключить галку в Nightfall.

## Отдельные вопросы

- Пушить ли свой форк на GitHub (приватный репозиторий DarkThemeSync уже есть — nightfall-fork будет подпапкой)?
- Upstream PR не планируется: фича слишком личная (жёстко завязана на Parallels + задачу в VM).
