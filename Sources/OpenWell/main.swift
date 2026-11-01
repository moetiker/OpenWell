import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var config = Config.load()
    private lazy var placer = WindowPlacer(config: config)
    private var trusted = false
    private var trustTimer: Timer?
    private var configWatch: DispatchSourceFileSystemObject?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Terminals.refresh()
        NSApp.mainMenu = mainMenu()
        watchConfig()

        let event = NSAppleEventManager.shared().currentAppleEvent
        let asLoginItem = event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
            == keyAELaunchedAsLogInItem

        trusted = AXTrust.isTrusted(prompt: true)
        if trusted {
            placer.start()
        } else {
            watchTrust()
        }
        // a start at login only watches; a start by hand is a click on the icon
        if !asLoginItem {
            newWindow(nil)
        }
    }

    // a click on the Dock icon of the running app
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        newWindow(nil)
        return false
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        Terminals.refresh()
        reloadConfig()
        let menu = NSMenu()
        // a click on the icon opens a window already
        menu.addItem(item(L("New Tab"), #selector(newTab(_:))))
        menu.addItem(terminalItem())
        menu.addItem(.separator())
        menu.addItem(item(L("Open at Login"), #selector(toggleOpenAtLogin(_:))))
        menu.addItem(item(L("Edit Config"), #selector(editConfig(_:))))
        return menu
    }

    @objc func newWindow(_ sender: Any?) {
        reloadConfig()
        if !trusted { askForTrust() }
        Launcher.openWindow(config: config, placer: placer, trusted: trusted)
    }

    @objc func newTab(_ sender: Any?) {
        reloadConfig()
        if !trusted { askForTrust() }
        Launcher.openTab(config: config, trusted: trusted)
    }

    /// "Terminal: <name>" with a submenu of the installed terminals, so a long list
    /// stays out of the Dock menu itself.
    private func terminalItem() -> NSMenuItem {
        let terminals = Terminals.installed(config)
        let chosen = terminals.first { $0.id == config.terminal }?.name ?? config.terminal
        let submenu = NSMenu()
        for terminal in terminals {
            let entry = item(terminal.name, #selector(chooseTerminal(_:)))
            entry.representedObject = terminal.id
            entry.state = terminal.id == config.terminal ? .on : .off
            entry.image = NSWorkspace.shared.icon(forFile: terminal.url.path)
            entry.image?.size = NSSize(width: 16, height: 16)
            submenu.addItem(entry)
        }
        let item = NSMenuItem(title: String(format: L("Terminal: %@"), chosen), action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    /// Makes the chosen terminal the one a Dock click opens, and watches it.
    @objc func chooseTerminal(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        // saving now would replace the user's broken file with the defaults
        guard Config.isReadable else {
            let alert = NSAlert()
            alert.messageText = L("The configuration cannot be read")
            alert.informativeText = String(format: L("%@ is not valid JSON. Fix it with Edit Config, "
                + "then choose the terminal again."), Config.url.path)
            alert.runModal()
            return
        }
        reloadConfig()
        config.terminal = id
        if !config.manage.contains(id) { config.manage.append(id) }
        config.save()
        placer.update(config)
    }

    private func reloadConfig() {
        config = Config.load()
        placer.update(config)
    }

    /// Reloads the config when the file changes. Editors save by replacing the file,
    /// which a watch on the file itself would lose, so this watches the directory.
    private func watchConfig() {
        let dir = Config.url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.reloadConfig() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        configWatch = source
    }

    @objc func toggleOpenAtLogin(_ sender: Any?) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            Log.info("Open at Login: \(error)")
        }
    }

    @objc func editConfig(_ sender: Any?) {
        if !FileManager.default.fileExists(atPath: Config.url.path) { config.save() }
        // open as plain text: a .json file may belong to an IDE that takes a while to start
        NSWorkspace.shared.open([Config.url], withApplicationAt: URL(fileURLWithPath:
            "/System/Applications/TextEdit.app"), configuration: NSWorkspace.OpenConfiguration())
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleOpenAtLogin(_:)) {
            menuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
        return true
    }

    // MARK: - Accessibility

    private func askForTrust() {
        let alert = NSAlert()
        alert.messageText = L("OpenWell needs Accessibility access")
        alert.informativeText = L("OpenWell opens and moves terminal windows through the "
            + "Accessibility API. Allow it under System Settings > Privacy & Security > "
            + "Accessibility. If OpenWell is listed but switched on, remove it with the "
            + "minus button and start OpenWell again.")
        alert.addButton(withTitle: L("Open System Settings"))
        alert.addButton(withTitle: L("Later"))
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(AXTrust.settingsURL)
        }
    }

    private func watchTrust() {
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in
                guard let self, AXTrust.isTrusted() else { return }
                self.trusted = true
                self.trustTimer?.invalidate()
                self.trustTimer = nil
                self.placer.start()
            }
        }
    }

    // MARK: - Menus

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func mainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L("About OpenWell"),
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(item(L("Open at Login"), #selector(toggleOpenAtLogin(_:))))
        appMenu.addItem(item(L("Edit Config"), #selector(editConfig(_:)), key: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("Hide OpenWell"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: L("Quit OpenWell"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileMenu = NSMenu(title: L("File"))
        fileMenu.addItem(item(L("New Terminal Window"), #selector(newWindow(_:)), key: "n"))
        fileMenu.addItem(item(L("New Terminal Tab"), #selector(newTab(_:)), key: "t"))
        let fileItem = NSMenuItem()
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        return main
    }
}

/// `OpenWell --spot` prints `x,y` for a new window of the configured terminal, in
/// global coordinates from the top left of the main screen. A terminal that can create
/// a window at a given position calls it from its Cmd+N binding, so the window appears
/// at its spot instead of being moved there.
@MainActor
func printSpot() -> Int32 {
    let config = Config.load()
    let trigger: Trigger = DockClick.take().map { .dock(mouse: $0) } ?? .keyboard
    // the frontmost window of the terminal gives the size, and for Cmd+N the screen
    let pids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: config.terminal)
        .map(\.processIdentifier))
    let owner = { (entry: WindowList.Entry) in pids.contains(entry.pid) }
    let front = WindowList.onScreen(excluding: nil, managed: Terminals.managed(config)).first(where: owner)
    let size = front?.frame.size ?? CGSize(width: 800, height: 600)
    guard let frame = Spot.frame(for: size, trigger: trigger, owner: owner,
                                 excluding: nil, config: config) else { return 1 }
    print("\(Int(frame.minX)),\(Int(frame.minY))")
    return 0
}

/// The text for `key` in the language of the desktop, from `Localizable.strings` in the
/// app bundle; English when the language has no translation.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

if CommandLine.arguments.dropFirst().first == "--spot" {
    exit(printSpot())
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
