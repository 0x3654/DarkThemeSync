# План: встроить синк темы Windows прямо в Nightfall («коробка»)

Цель: **установка с нуля = один Nightfall.app**. На маке ничего кроме приложения (никаких watcher'ов, агентов, `~/bin`). Приложение само разворачивает виндовую обвязку при первом включении галки и само же переключает темы.

Текущие скрипты (`mac/`, `vm/`) — черновик-прототип, доказавший механику; после своей сборки агента глушим, скрипты → `prototype/`, содержимое `MacThemeSync.ps1` переезжает внутрь приложения Swift-константой.

Почему на винде что-то должно быть: `prlctl exec` работает от SYSTEM, тему пользовательской сессии меняет только процесс в этой сессии (задача планировщика). Обойти нельзя, но приложение создаёт эту обвязку само (см. «Self-provisioning»).

База: `nightfall-fork/` (upstream r-thomson/Nightfall @ 9e3f0a1, см. `UPSTREAM`). Приложение установлено в `/Applications/Nightfall.app`.

## Код изучен — точки врезки

| Файл | Что там | Что делаем |
|---|---|---|
| `Nightfall/ToggleDarkMode.swift` | `toggleDarkMode()` — единственная точка переключения (хоткей и клик по menubar оба ведут сюда) | после `setAppearanceTheme` пушим в VM |
| `Nightfall/Extensions/UserDefaults.swift` | `struct Keys` + 3 настройки | + `SyncWindowsVM` (Bool), `WindowsVMName` (String, список VM через запятую) |
| `Nightfall/Views/PreferencesView.swift` | SwiftUI-поповвер, 240pt, 3 тумблера + рекордер хоткея | + Toggle и TextField имени VM |
| `Nightfall/Utility/AppearanceTheme.swift` | get/set через приватный SkyLight API | не трогаем |
| `Nightfall/AppDelegate.swift` | запуск приложения | + обзервер + первичный пуш |

## Изменения

### 1. UserDefaults.swift

Swift — без точек с запятой, каждый ключ отдельной строкой:

```swift
struct Keys {
    static let useTransition = "UseTransition"
    static let startAtLogin = "StartAtLogin"
    static let checkForUpdates = "CheckForUpdates"
    static let syncWindowsVM = "SyncWindowsVM"
    static let windowsVMName = "WindowsVMName"
}

var syncWindowsVM: Bool {
    get { self.bool(forKey: Keys.syncWindowsVM) }
    set { self.set(newValue, forKey: Keys.syncWindowsVM) }
}

var windowsVMName: String {
    // список VM через запятую ("Windows 11, WinRU"); дефолт в геттере:
    // поле заполнено с первого открытия настроек, в defaults значение
    // пишется только после ручного редактирования
    get { self.object(forKey: Keys.windowsVMName) as? String ?? "Windows 11" }
    set { self.set(newValue, forKey: Keys.windowsVMName) }
}
```

### 2. Новый файл `Nightfall/Utility/WindowsThemeSync.swift`

```swift
import Foundation

/// Проталкивает текущую тему в Windows-VM (Parallels). Fire-and-forget:
/// каждая VM запускается отдельным Process'ом (параллельно),
/// выключенная/спящая VM тихо фейлится, остальные живут.
enum WindowsThemeSync {
    static func push(_ theme: AppearanceTheme) {
        let defaults = UserDefaults.standard
        guard defaults.syncWindowsVM else { return }

        let mode = theme == .dark ? "dark" : "light"
        let cmd = "Set-Content C:\\Users\\Public\\mac_theme.txt '\(mode)'; schtasks /Run /TN MacThemeSync"

        // "Windows 11, WinRU" → ["Windows 11", "WinRU"]
        let vms = defaults.windowsVMName
            .split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for vm in vms {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/local/bin/prlctl")
            task.arguments = ["exec", vm, "powershell", "-NoProfile", "-Command", cmd]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try? task.run()   // не ждём завершения
        }
    }
}
```

Механизм в VM (задача `MacThemeSync` + `C:\Users\Public\MacThemeSync.ps1`) остаётся как есть — prlctl exec работает от SYSTEM и тему сессии меняет только задача планировщика (см. README, грабли).

### 3. ToggleDarkMode.swift

```swift
let target = !getAppearanceTheme()
setAppearanceTheme(to: target, notify: transition == nil)
WindowsThemeSync.push(target)
```

### 4. AppDelegate — обзервер вместо watcher'а

`AppleInterfaceThemeChangedNotification` (distributed) система рассылает при **любой** смене внешнего вида — Nightfall, Control Center, Shortcuts, расписание. Это закрывает всё, что делал poll-watcher, и без поллинга:

```swift
// в applicationDidFinishLaunching:
DistributedNotificationCenter.default().addObserver(
    self, selector: #selector(appearanceChanged(_:)),
    name: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil)

@objc func appearanceChanged(_ n: Notification) {
    // debounce ~0.5 cek (уведомление может прийти пачкой), затем:
    WindowsThemeSync.push(getAppearanceTheme() == .dark ? .dark : .light)
}
```

Плюс там же один первичный пуш при старте (случай «винда загрузилась, когда мак уже тёмный»).

Нюанс: при переключении самим Nightfall пуш произойдёт дважды (из toggleDarkMode и из обзервера). Это безвредно (idempotent), но можно убрать прямой вызов из `toggleDarkMode` и оставить только обзервер.

### 5. PreferencesView.swift

```swift
@ObservedObject private var syncWindowsVM =
    ObservableUserDefault<Bool>(UserDefaults.Keys.syncWindowsVM)
@ObservedObject private var windowsVMName =
    ObservableUserDefault<String>(UserDefaults.Keys.windowsVMName)

// после "Check for new versions":
Divider().padding(.vertical, 6)
Toggle("Sync Windows theme (Parallels)", isOn: $syncWindowsVM.value)
if syncWindowsVM.value {
    TextField("VMs, comma-separated", text: $windowsVMName.value)
        .textFieldStyle(.roundedBorder)
        .padding(.leading, 18)
}
```

UI-строки на английском — в стиле приложения (локализаций в Nightfall нет).

### 6. Self-provisioning — приложение само ставит виндовую обвязку

Чтобы «установка с нуля = только приложение». Вместо ручного прогона `vm/setup-task.ps1`.

Новый файл `Nightfall/Utility/WindowsVMProvisioner.swift` (~150 строк):

```swift
enum WindowsVMProvisioner {
    /// prlctl list -a --json → [VM] (имя, состояние, windows: bool)
    static func listVMs() -> [ParallelsVM]

    /// Разворачивает обвязку в одной запущенной VM. Идемпотентно (/F).
    static func setup(vm: String) async throws -> ProvisionStatus

    /// Снимает обвязку (schtasks /Delete + rm файлов).
    static func remove(vm: String) async throws
}
```

Шаги `setup(vm:)` — обкатано черновиком (`vm/push-payload.sh`, `vm/setup-task.ps1`):
1. Залить `MacThemeSync.ps1` + `.vbs` в `C:\Users\Public`: содержимое ps1 — Swift-константа (сырой текст из `vm/setup-task.ps1`, без here-string), base64 → `prlctl exec` кусками по ~700 симв. (`Set-Content`/`Add-Content`) → decode → `WriteAllText`. Лимит длины команды prlctl ~4–5 КБ — потому кусками, с проверкой длины на приёме.
2. `schtasks /Create /F /TN MacThemeSync /TR wscript.exe C:\Users\Public\MacThemeSync.vbs /SC ONCE /ST 23:59 /RU <user> /IT`, где `<user>` = `(Get-CimInstance Win32_ComputerSystem).UserName` (не SYSTEM!).
3. Сразу чистить триггер-заглушку: `$t=Get-ScheduledTask MacThemeSync; $t.Triggers=@(); Set-ScheduledTask -InputObject $t` — никакого прогона в 23:59.
4. Верификация `schtasks /Query /TN MacThemeSync` → статус в UI.

UX: первое включение галки → диалог «выбери VM» (список из `prlctl list -a`, виндовые помечены; выделены по умолчанию запущенные) → Setup → per-VM статус (✓ / «VM выключена — запусти и повтори» / «нет Parallels Tools?»). Выбранные имена → `WindowsVMNames` (список через запятую). Кнопка «Remove from VMs» — снятие обвязки.

Важно: VM должна быть **запущена** в момент setup (prlctl exec не работает в остановленную). Для WinRU — тот же диалог при первом запуске.

## Сборка и установка

```bash
cd nightfall-fork
xcodebuild -project Nightfall.xcodeproj -scheme Nightfall -configuration Release -derivedDataPath build
# выход: build/Build/Products/Release/Nightfall.app
# закрыть запущенный Nightfall, cp -R в /Applications, запустить
```

- Зависимость KeyboardShortcuts подтянется SPM'ом (нужна сеть один раз).
- Новый файл и pbxproj: проверить формат — новые Xcode с file-system synchronized groups подхватывают сами, классический формат — вшить руками/Xcode.
- Bundle id не менять: хоткей (KeyboardShortcuts хранит в UserDefaults) и настройки сохранятся.
- Подпись: локальная сборка ad-hoc; Gatekeeper на свою же сборку не ругается.

## После успешной установки

```bash
launchctl bootout gui/$(id -u)/local.mac2win-theme-sync   # watcher больше не нужен
rm ~/Library/LaunchAgents/local.mac2win-theme-sync.plist ~/bin/mac2win-theme.sh
git mv mac vm prototype/   # черновик больше не рабочий механизм, а история прототипа
```

Задачу `MacThemeSync` в VM **не** удалять — Nightfall дергает её же.

## Тест-чеклист

1. Галка on → хоткей Nightfall → VM перекрасилась за ~2–4 сек (таскбар сразу, broadcast).
2. Смена темы через Control Center → VM тоже перекрасилась (обзервер).
3. VM выключена → переключения на маке не дают ошибок/фризов, prlctl тихо завершается.
4. Галка off → prlctl вообще не запускается (проверить `ps`).
5. Поле `Windows 11, WinRU`, обе запущены → перекрасились обе; WinRU выключена → перекрасилась только Windows 11, без ошибок.

## Идеи на потом

- Kali (не виндовая тема): отдельный пуш через `prlctl exec <kali> sudo -u <user> gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'|'prefer-light'` — если понадобится.
- Опционально — автоопределение списка VM через `prlctl list -a` вместо ручного поля.
