import AppKit
import ApplicationServices

/// Opens a new window or tab in the configured terminal.
@MainActor
enum Launcher {
    /// A menu shortcut with Cmd alone, and the key that types it.
    enum Shortcut {
        case newWindow
        case newTab

        var character: String { self == .newWindow ? "N" : "T" }
        var keyCode: CGKeyCode { self == .newWindow ? 0x2D : 0x11 } // kVK_ANSI_N, kVK_ANSI_T
    }

    static func openWindow(config: Config, placer: WindowPlacer, trusted: Bool) {
        open(.newWindow, config: config, trusted: trusted) { pid in
            let mouse = Screens.mouse
            placer.expect(pid, mouse: mouse)
            // for a terminal whose Cmd+N runs `OpenWell --spot`
            DockClick.record(mouse: mouse)
        }
    }

    /// A new tab in the terminal's frontmost window. A terminal that is not running
    /// starts with its first window instead.
    static func openTab(config: Config, trusted: Bool) {
        open(.newTab, config: config, trusted: trusted) { _ in }
    }

    private static func open(_ shortcut: Shortcut, config: Config, trusted: Bool,
                             before: (pid_t) -> Void) {
        let id = config.terminal
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            let alert = NSAlert()
            alert.messageText = L("Terminal not found")
            alert.informativeText = String(format: L("No app with the bundle ID %@ is installed. "
                + "Set \"terminal\" in %@."), id, Config.url.path)
            alert.runModal()
            return
        }

        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .first(where: { !$0.isTerminated }) else {
            // the launch opens the first window; the placer sees the launch and places it
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return
        }

        let pid = app.processIdentifier
        if trusted {
            before(pid)
            if !pressMenuItem(shortcut, pid) {
                post(shortcut, pid)
            }
        }
        activate(app)
    }

    /// Presses the menu item with `shortcut`. The app does not need to be frontmost
    /// for this. A terminal that binds the shortcut to its own action, such as WezTerm
    /// with the `OpenWell --spot` binding for Cmd+N, shows another shortcut on the
    /// item, and then gets the keystroke instead.
    private static func pressMenuItem(_ shortcut: Shortcut, _ pid: pid_t) -> Bool {
        guard let menuBar = AXUIElementCreateApplication(pid).element(kAXMenuBarAttribute) else {
            return false
        }
        // the first item is the Apple menu
        return menuBar.elements(kAXChildrenAttribute).dropFirst().contains {
            press(shortcut, in: $0, depth: 0)
        }
    }

    /// Searches a menu bar item or menu item and its submenus. Terminal keeps "New
    /// Window" and "New Tab" in submenus of Shell, one item per profile.
    private static func press(_ shortcut: Shortcut, in element: AXUIElement, depth: Int) -> Bool {
        guard depth < 3 else { return false }
        for menu in element.elements(kAXChildrenAttribute) {
            for item in menu.elements(kAXChildrenAttribute) {
                if item.string(kAXMenuItemCmdCharAttribute)?.uppercased() == shortcut.character,
                    // 0 is Cmd alone; Shift, Option and Control add bits
                    item.number(kAXMenuItemCmdModifiersAttribute) == 0,
                    item.bool(kAXEnabledAttribute) != false, item.press() {
                    return true
                }
                if press(shortcut, in: item, depth: depth + 1) { return true }
            }
        }
        return false
    }

    /// Sends the shortcut to the terminal process alone. A keystroke through the global
    /// event stream would reach whichever app is frontmost while the terminal is still
    /// being activated.
    private static func post(_ shortcut: Shortcut, _ pid: pid_t) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode,
                                      keyDown: down) else { continue }
            event.flags = .maskCommand
            event.postToPid(pid)
        }
    }

    private static func activate(_ app: NSRunningApplication) {
        if #available(macOS 14, *) {
            NSApp.yieldActivation(to: app)
            app.activate()
        } else {
            app.activate(options: [])
        }
    }
}
