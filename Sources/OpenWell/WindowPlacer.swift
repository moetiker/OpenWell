import AppKit
import ApplicationServices
import OpenWellCore

/// Watches the managed terminals for new windows and moves the ones OpenWell expects
/// to a free spot.
@MainActor
final class WindowPlacer {
    private struct Expectation {
        let trigger: Trigger
        let until: Date
    }

    private var config: Config
    private var observers: [pid_t: AXObserver] = [:]
    private var launchedAt: [pid_t: Date] = [:]
    private var expected: [pid_t: Expectation] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []

    /// How long a Dock click or a launch waits for its window.
    private let expectationTimeout: TimeInterval = 5
    /// Windows appearing this soon after a launch, besides the first one, are restored
    /// ones and stay where the app put them.
    private let restoreWindow: TimeInterval = 3

    init(config: Config) {
        self.config = config
    }

    func start() {
        guard workspaceObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let pid = app?.processIdentifier, id = app?.bundleIdentifier
            MainActor.assumeIsolated { [weak self] in
                guard let self, let pid, let id else { return }
                self.launched(pid: pid, bundleID: id)
            }
        })
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                .processIdentifier
            MainActor.assumeIsolated { [weak self] in
                guard let self, let pid else { return }
                self.detach(pid)
            }
        })
        attachRunning()
    }

    /// Applies a changed config: watches the apps `manage` now lists, and only those.
    func update(_ config: Config) {
        guard config != self.config else { return }
        self.config = config
        for pid in observers.keys { detach(pid) }
        attachRunning()
    }

    /// The next window of `pid` comes from a Dock click with the pointer at `mouse`.
    func expect(_ pid: pid_t, mouse: CGPoint) {
        expected[pid] = Expectation(trigger: .dock(mouse: mouse), until: Date().addingTimeInterval(expectationTimeout))
    }

    // MARK: - Watching

    private func attachRunning() {
        let managed = Terminals.managed(config)
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier, managed.contains(id) else { continue }
            attach(app.processIdentifier)
        }
    }

    private func launched(pid: pid_t, bundleID: String) {
        // a terminal installed while OpenWell runs is not discovered yet
        if !Terminals.managed(config).contains(bundleID) { Terminals.refresh() }
        guard Terminals.managed(config).contains(bundleID) else { return }
        launchedAt[pid] = Date()
        if expected[pid] == nil {
            expected[pid] = Expectation(trigger: .dock(mouse: Screens.mouse),
                                        until: Date().addingTimeInterval(expectationTimeout))
        }
        attach(pid)
        // the first window may have appeared before the launch notification arrived,
        // when there was no observer yet to report it
        pollFirstWindow(pid, until: Date().addingTimeInterval(expectationTimeout))
    }

    private func pollFirstWindow(_ pid: pid_t, until deadline: Date) {
        guard expected[pid] != nil, Date() < deadline else { return }
        let app = AXUIElementCreateApplication(pid)
        if let window = app.elements(kAXWindowsAttribute).first(where: \.isStandardWindow) {
            windowCreated(window, pid: pid)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.pollFirstWindow(pid, until: deadline)
        }
    }

    private func attach(_ pid: pid_t) {
        guard observers[pid] == nil else { return }
        var observer: AXObserver?
        guard AXObserverCreate(pid, windowCreatedCallback, &observer) == .success, let observer else {
            Log.info("Cannot watch process \(pid)")
            return
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let result = AXObserverAddNotification(
            observer, AXUIElementCreateApplication(pid), kAXWindowCreatedNotification as CFString, refcon)
        if result != .success {
            // an app still starting up may refuse; the launch poll covers its first window
            Log.info("Cannot watch the windows of process \(pid): AXError \(result.rawValue)")
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
        if result != .success {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, self.observers[pid] === observer else { return }
                self.detach(pid, keepState: true)
                self.attach(pid)
            }
        }
    }

    private func detach(_ pid: pid_t, keepState: Bool = false) {
        if let observer = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        if !keepState {
            launchedAt[pid] = nil
            expected[pid] = nil
        }
    }

    // MARK: - Deciding

    /// Decides at once: the window is on screen already, and every millisecond of delay
    /// shows as a jump.
    fileprivate func windowCreated(_ window: AXUIElement, pid: pid_t) {
        decide(window, pid: pid, attempt: 0)
    }

    private func decide(_ window: AXUIElement, pid: pid_t, attempt: Int) {
        // some apps announce a window before it has its role
        if window.role == nil && attempt < 10 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
                self?.decide(window, pid: pid, attempt: attempt + 1)
            }
            return
        }
        guard window.isStandardWindow, !window.isFullScreen else { return }

        let now = Date()
        if let expectation = expected[pid] {
            expected[pid] = nil
            if expectation.until > now {
                place(window, pid: pid, trigger: expectation.trigger)
                return
            }
        }
        if let launched = launchedAt[pid], now.timeIntervalSince(launched) < restoreWindow {
            return
        }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
            place(window, pid: pid, trigger: .keyboard)
        }
    }

    // MARK: - Placing

    private func place(_ window: AXUIElement, pid: pid_t, trigger: Trigger) {
        guard let frame = window.frame else { return }
        let windowID = window.windowID
        let name = "window \(windowID.map(String.init) ?? "?") of process \(pid)"
        if case .dock = trigger { _ = DockClick.take() }

        // a terminal that asked `OpenWell --spot` created the window at its spot already
        if Spot.isFree(frame, excluding: windowID, config: config) {
            Log.info("Left \(name) at \(frame): free already")
            return
        }
        guard let new = Spot.frame(for: frame.size, trigger: trigger, owner: { $0.pid == pid },
                                   excluding: windowID, config: config) else { return }
        // no screen has a free spot left and the terminal used the best one already
        if new == frame {
            Log.info("Left \(name) at \(frame): best spot already")
            return
        }
        if new.size != frame.size { window.size = new.size }
        window.position = new.origin
        Log.info("Moved \(name) from \(frame) to \(new)")
    }
}

/// The AXObserver callback is a C function pointer and cannot capture; `refcon` carries
/// the placer.
private func windowCreatedCallback(
    _ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    var pid: pid_t = 0
    guard AXUIElementGetPid(element, &pid) == .success else { return }
    let placer = Unmanaged<WindowPlacer>.fromOpaque(refcon).takeUnretainedValue()
    // the observer's run loop source sits on the main run loop, so this already runs
    // on the main thread; AXUIElement is just not marked Sendable
    nonisolated(unsafe) let window = element
    MainActor.assumeIsolated {
        placer.windowCreated(window, pid: pid)
    }
}

/// The windows on the current Space, front to back.
@MainActor
enum WindowList {
    struct Entry {
        let id: CGWindowID
        let pid: pid_t
        let frame: CGRect
        let isManaged: Bool
    }

    // tool tips, drag images and status items are tiny or transparent and block no spot
    private static let minimumSide: CGFloat = 20

    static func onScreen(excluding excluded: CGWindowID?, managed: Set<String>) -> [Entry] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let own = ProcessInfo.processInfo.processIdentifier
        var bundleIDs: [pid_t: String] = [:]
        return info.compactMap { w in
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                let id = w[kCGWindowNumber as String] as? CGWindowID, id != excluded,
                let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != own,
                let bounds = w[kCGWindowBounds as String] as? NSDictionary,
                let frame = CGRect(dictionaryRepresentation: bounds),
                frame.width >= minimumSide, frame.height >= minimumSide else { return nil }
            if bundleIDs[pid] == nil {
                bundleIDs[pid] = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
            }
            return Entry(id: id, pid: pid, frame: frame, isManaged: managed.contains(bundleIDs[pid]!))
        }
    }
}
