import AppKit
import OpenWellCore

/// What made a window appear, which decides its screen and anchor.
enum Trigger {
    /// a Dock click, the Dock menu or the first window after a launch: the screen under
    /// the mouse pointer at the time of the click
    case dock(mouse: CGPoint)
    /// Cmd+N in the terminal: the screen of the window it was typed in
    case keyboard
}

/// The free-spot search on the live screen, shared by the app and `OpenWell --spot`.
@MainActor
enum Spot {
    /// The frame for a new window of `size`. `owner` is the process whose frontmost
    /// window decides the screen for `.keyboard`; `excluding` is the new window itself
    /// when it exists already.
    static func frame(for size: CGSize, trigger: Trigger, owner: (WindowList.Entry) -> Bool,
                      excluding: CGWindowID?, config: Config) -> CGRect? {
        let others = WindowList.onScreen(excluding: excluding, managed: Terminals.managed(config))

        let screen: NSScreen?
        var anchor = config.anchor
        var mouse = Screens.mouse
        switch trigger {
        case .dock(let point):
            mouse = point
            screen = Screens.screen(at: point) ?? NSScreen.main
            // the pointer rests on the Dock at that moment
            if anchor == .mouse { anchor = .topLeft }
        case .keyboard:
            // the window list runs front to back: the first window of the owner is the
            // one Cmd+N was typed in
            let previous = others.first(where: owner)
            screen = previous.flatMap { Screens.screen(of: $0.frame) } ?? Screens.mouseScreen
        }
        guard let screen else { return nil }

        let area = Screens.usableArea(of: screen)
        let obstacles = others.filter { $0.frame.intersects(area) }
            .map { Obstacle($0.frame, managed: $0.isManaged) }
        let target = Placement.target(anchor, size: size, in: area, mouse: mouse)
        return Placement.frame(for: size, in: area, avoiding: obstacles,
                               gap: config.gap, target: target).integral
    }

    /// True when `frame` lies inside a usable screen area and overlaps no other window:
    /// a window the terminal already created at a free spot stays where it is. After a
    /// Dock click the spot must also be on the screen under the mouse; a terminal
    /// that opens its window on another screen would otherwise keep it there.
    static func isFree(_ frame: CGRect, excluding: CGWindowID?, trigger: Trigger, config: Config) -> Bool {
        guard let screen = Screens.screen(of: frame),
            Screens.usableArea(of: screen).insetBy(dx: -1, dy: -1).contains(frame) else { return false }
        if case .dock(let mouse) = trigger, Screens.screen(at: mouse).map({ $0 !== screen }) ?? false {
            return false
        }
        let others = WindowList.onScreen(excluding: excluding, managed: Terminals.managed(config))
        return Placement.overlap(frame, others.map { Obstacle($0.frame) }) == 0
    }
}

/// A Dock click hands its mouse position to `OpenWell --spot`, which runs as a child
/// of the terminal and cannot otherwise tell a Dock click from Cmd+N.
enum DockClick {
    private static let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ch.oetiker.OpenWell/dock-click.json")
    /// How long a Dock click waits for the terminal to ask.
    private static let lifetime: TimeInterval = 3

    private struct State: Codable {
        let x: Double
        let y: Double
        let until: Date
    }

    static func record(mouse: CGPoint) {
        let state = State(x: mouse.x, y: mouse.y, until: Date().addingTimeInterval(lifetime))
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: url, options: .atomic)
        } catch {
            Log.info("\(url.path): \(error)")
        }
    }

    /// The mouse position of a Dock click still waiting, removed once read.
    static func take() -> CGPoint? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.removeItem(at: url)
        guard let state = try? JSONDecoder().decode(State.self, from: data), state.until > Date() else {
            return nil
        }
        return CGPoint(x: state.x, y: state.y)
    }
}
