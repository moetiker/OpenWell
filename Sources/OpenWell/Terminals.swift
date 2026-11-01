import AppKit
import UniformTypeIdentifiers

/// The terminal apps OpenWell offers in the Dock menu and watches for new windows.
@MainActor
enum Terminals {
    /// Terminals known by bundle ID, in menu order. Discovery finds most of them as
    /// well, but a terminal that registers for no executable file type would be missed.
    nonisolated static let known = [
        "com.github.wez.wezterm",
        "com.googlecode.iterm2",
        "com.apple.Terminal",
        "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "dev.warp.Warp-Stable",
        "co.zeit.hyper",
        "org.tabby",
        "com.raphaelamorim.rio",
    ]

    struct App {
        let id: String
        let name: String
        let url: URL
    }

    /// Apps that macOS lists for opening a Unix executable. On the machine OpenWell was
    /// written on these were exactly the three installed terminals; shell scripts and
    /// `ssh://` were no use, the first lists TextEdit and browsers, the second misses
    /// WezTerm.
    private(set) static var discovered: [String] = scan()

    static func refresh() {
        discovered = scan()
    }

    private static func scan() -> [String] {
        let own = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        return NSWorkspace.shared.urlsForApplications(toOpen: .unixExecutable).compactMap { url in
            guard let id = Bundle(url: url)?.bundleIdentifier, id != own, seen.insert(id).inserted else {
                return nil
            }
            return id
        }
    }

    /// The bundle IDs whose new windows OpenWell places: `manage` from the config plus
    /// every discovered terminal.
    static func managed(_ config: Config) -> Set<String> {
        Set(config.manage).union(discovered)
    }

    /// The installed terminals for the Dock menu: the known ones in their order, then
    /// the configured and the discovered ones.
    static func installed(_ config: Config) -> [App] {
        var ids = known
        for id in config.manage + [config.terminal] + discovered where !ids.contains(id) {
            ids.append(id)
        }
        return ids.compactMap { id in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
            let name = FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
            return App(id: id, name: name, url: url)
        }
    }
}
