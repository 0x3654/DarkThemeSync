# DarkThemeSync

Автоматическая синхронизация светлой/тёмной темы: **macOS → Windows в Parallels VM**.
Ответ на вопрос «почему винда сама не переключается и Parallels не синхронизирует» — теперь переключается.

## Как это работает

```
macOS (тема сменилась: Nightfall / хоткей / таймер / Control Center)
   │  watcher: ~/bin/mac2win-theme.sh (poll AppleInterfaceStyle, 1 сек)
   ▼
prlctl exec "Windows 11" powershell "Set-Content C:\Users\Public\mac_theme.txt '<dark|light>'; schtasks /Run /TN MacThemeSync"
   │  (prlctl exec работает от SYSTEM → напрямую тему сессии не поменять)
   ▼
Задача планировщика MacThemeSync (от пользователя MD2DD\m, скрыто через vbs)
   ▼
C:\Users\Public\MacThemeSync.ps1: реестр AppsUseLightTheme/SystemUsesLightTheme
+ broadcast WM_SETTINGCHANGE "ImmersiveColorSet" → таскбар и приложения перерисовываются сразу
```

Задержка: ~2–4 сек. Задача в VM без триггеров (только ручной запуск через `/Run`, прогон в 23:59 убран).

## Файлы

### mac/
- `mac2win-theme.sh` — watcher (установлен в `~/bin/`, poll раз в 1 сек; нагрузка нулевая — `defaults read` читает кэш cfprefsd)
- `local.mac2win-theme-sync.plist` — LaunchAgent (установлен в `~/Library/LaunchAgents/`, KeepAlive, автозапуск при логине; лог `~/Library/Logs/mac2win-theme.log`)

### vm/
- `setup-task.ps1` — одноразовая настройка VM: пишет `MacThemeSync.ps1` + vbs-обёртку в `C:\Users\Public`, создаёт задачу планировщика `MacThemeSync` от залогиненного пользователя. **После него руками:** `$t=Get-ScheduledTask MacThemeSync; $t.Triggers=@(); Set-ScheduledTask -InputObject $t` (убрать триггер-заглушку 23:59)
- `push-payload.sh` — хелпер передачи длинного PowerShell-скрипта в VM по кускам по 400 симв. base64 с проверкой длины (у `prlctl exec` лимит длины команды ~4–5 КБ)

### nightfall-fork/
Клон [r-thomson/Nightfall](https://github.com/r-thomson/Nightfall) — из него делаем «коробку»: галка в настройках, при включении Nightfall сам дергает винду, без watcher'а и LaunchAgent. План: `docs/PLAN-nightfall.md`

### docs/
- `PLAN-nightfall.md` — план интеграции в Nightfall
- `memory-mac2win-theme-sync.md` — копия памяти ассистента по этой теме (грабли prlctl exec)

Диалог, в котором всё это родилось, продолжается в этом проекте:
сессия Claude Code перенесена (`claude --resume` / список сессий в VSCode при открытой папке `~/code/DarkThemeSync`).

## Грабли prlctl exec (проверено, не повторять)

1. Выполняется от **SYSTEM**, не от залогиненного пользователя → HKCU пользователя не виден; тему сессии меняет только задача планировщика от пользователя.
2. **Лимит длины команды** (~5 КБ base64 не проходит) → заливать кусками с проверкой длины на приёме (см. `vm/push-payload.sh`).
3. Файлы, созданные SYSTEM в `C:\Windows\Temp`, обычный пользователь читать не может («Отказано в доступе») → всё в `C:\Users\Public`.
4. Из-под launchd PATH без `/usr/local/bin` (где prlctl) → PATH в начале скрипта.
5. `schtasks /Create` требует триггер → создаём с /SC ONCE, потом чистим триггеры.

## Установка с нуля

VM (через `prlctl exec` от SYSTEM): залить `vm/setup-task.ps1` хелпером `vm/push-payload.sh`, выполнить с `-ExecutionPolicy Bypass`, убрать триггер.

Mac: `cp mac/mac2win-theme.sh ~/bin/ && chmod +x ~/bin/mac2win-theme.sh && cp mac/local.mac2win-theme-sync.plist ~/Library/LaunchAgents/ && launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.mac2win-theme-sync.plist`

(Но при живом Nightfall-форке watcher/LaunchAgent не нужны — см. план.)

## Удаление

```bash
launchctl bootout gui/$(id -u)/local.mac2win-theme-sync
rm ~/Library/LaunchAgents/local.mac2win-theme-sync.plist ~/bin/mac2win-theme.sh
```
```powershell
# в VM
schtasks /Delete /TN MacThemeSync
Remove-Item C:\Users\Public\MacThemeSync.ps1, C:\Users\Public\MacThemeSync.vbs, C:\Users\Public\mac_theme.txt
```

## Контекст

- VM: «Windows 11» (Parallels), пользователь `MD2DD\m`, SID `S-1-5-21-2961813680-396835540-796207745-1000`
- Тему на маке переключает [Nightfall](https://github.com/r-thomson/Nightfall) (у него нет ни CLI, ни хуков — потому watcher)
- Имя VM в watcher'е меняется через `VM_NAME=... ` или правкой дефолта в скрипте
