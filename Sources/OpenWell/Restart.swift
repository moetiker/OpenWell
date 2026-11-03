import AppKit

/// `brew upgrade` quits OpenWell through an Apple event and starts the new version
/// with `open -b`, which looks like a start by hand. A start shortly after a quit
/// requested by another program is such a restart and opens no window.
enum Restart {
    private static let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ch.oetiker.OpenWell/restart")
    /// How long after the quit a start still counts as a restart.
    private static let lifetime: TimeInterval = 60

    /// Called for the quit Apple event. A quit from the Dock menu comes from the Dock,
    /// Cmd+Q and the menu bar send no Apple event; anything else is a script or an
    /// installer.
    static func noteQuit(_ event: NSAppleEventDescriptor) {
        guard let sender = event.attributeDescriptor(forKeyword: keySenderPIDAttr)?.int32Value,
              sender != getpid()
        else { return }
        let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
        if dock.contains(where: { $0.processIdentifier == sender }) { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url, options: .atomic)
            Log.info("Quit requested by pid \(sender)")
        } catch {
            Log.info("\(url.path): \(error)")
        }
    }

    /// Whether this start follows a quit requested by another program, read once.
    static func take() -> Bool {
        guard let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate]
            as? Date else { return false }
        try? FileManager.default.removeItem(at: url)
        return Date().timeIntervalSince(date) < lifetime
    }
}
