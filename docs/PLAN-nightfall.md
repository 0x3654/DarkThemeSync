# План: встроить синк темы Windows прямо в Nightfall («коробка»)

Цель: галка «Sync Windows theme (Parallels)» в настройках Nightfall. Когда включена — Nightfall сам переключает тему в VM при любой смене темы мака. Watcher и LaunchAgent после этого отключаем (файлы остаются в `mac/` как fallback).

База: `nightfall-fork/` (upstream r-thomson/Nightfall @ 9e3f0a1, см. `UPSTREAM`). Приложение установлено в `/Applications/Nightfall.app`.

## Код изучен — точки врезки

| Файл | Что там | Что делаем |
|---|---|---|
| `Nightfall/ToggleDarkMode.swift` | `toggleDarkMode()` — единственная точка переключения (хоткей и клик по menubar оба ведут сюда) | после `setAppearanceTheme` пушим в VM |
| `Nightfall/Extensions/UserDefaults.swift` | `struct Keys` + 3 настройки | + `SyncWindowsVM` (Bool), `WindowsVMName` (String) |
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
    // дефолт в геттере: поле заполнено с первого открытия настроек,
    // в defaults значение пишется только после ручного редактирования
    get { self.object(forKey: Keys.windowsVMName) as? String ?? "Windows 11" }
    set { self.set(newValue, forKey: Keys.windowsVMName) }
}
```

### 2. Новый файл `Nightfall/Utility/WindowsThemeSync.swift`

```swift
import Foundation

/// Проталкивает текущую тему в Windows (Parallels VM). Fire-and-forget:
/// VM выключена/спит — тихо ничего не происходит.
enum WindowsThemeSync {
    static func push(_ theme: AppearanceTheme) {
        let defaults = UserDefaults.standard
        guard defaults.syncWindowsVM else { return }

        let mode = theme == .dark ? "dark" : "light"
        let cmd = "Set-Content C:\\Users\\Public\\mac_theme.txt '\(mode)'; schtasks /Run /TN MacThemeSync"

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/local/bin/prlctl")
        task.arguments = ["exec", defaults.windowsVMName, "powershell", "-NoProfile", "-Command", cmd]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()   // не ждём завершения
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
    TextField("VM name", text: $windowsVMName.value)
        .textFieldStyle(.roundedBorder)
        .padding(.leading, 18)
}
```

UI-строки на английском — в стиле приложения (локализаций в Nightfall нет).

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
# plist и ~/bin/mac2win-theme.sh оставить в репо (mac/) как fallback
```

Задачу `MacThemeSync` в VM **не** удалять — Nightfall дергает её же.

## Тест-чеклист

1. Галка on → хоткей Nightfall → VM перекрасилась за ~2–4 сек (таскбар сразу, broadcast).
2. Смена темы через Control Center → VM тоже перекрасилась (обзервер).
3. VM выключена → переключения на маке не дают ошибок/фризов, prlctl тихо завершается.
4. Галка off → prlctl вообще не запускается (проверить `ps`).
5. Имя VM в поле → синк идёт в указанную VM.
