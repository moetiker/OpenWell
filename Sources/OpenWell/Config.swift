import Foundation
import OpenWellCore

/// `~/.config/openwell/config.json`. It holds data only: OpenWell runs no command
/// from it, because a child process would inherit OpenWell's Accessibility permission
/// and every process of the user can write this file.
struct Config: Codable, Equatable {
    var terminal = "com.github.wez.wezterm"
    var manage = Terminals.known
    var gap: Double = 10
    var anchor = Anchor.topLeft

    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/openwell/config.json")

    init() {}

    // a missing key keeps its default, so an old file still loads after a key is added
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Config()
        terminal = try c.decodeIfPresent(String.self, forKey: .terminal) ?? defaults.terminal
        manage = try c.decodeIfPresent([String].self, forKey: .manage) ?? defaults.manage
        gap = try c.decodeIfPresent(Double.self, forKey: .gap) ?? defaults.gap
        anchor = try c.decodeIfPresent(Anchor.self, forKey: .anchor) ?? defaults.anchor
    }

    /// The file's contents, or the defaults when it is missing (then written) or
    /// unreadable (then logged and left alone).
    static func load() -> Config {
        guard let data = try? Data(contentsOf: url) else {
            let config = Config()
            config.save()
            return config
        }
        do {
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            Log.info("\(url.path): \(error); using the defaults")
            return Config()
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(
                at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(self).write(to: Self.url, options: .atomic)
        } catch {
            Log.info("\(Self.url.path): \(error)")
        }
    }
}
