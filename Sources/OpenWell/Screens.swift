import AppKit

/// NSScreen frames start at the bottom left of the main screen with y growing upward;
/// the accessibility API and CGWindowList start at its top left with y growing
/// downward. Everything here returns accessibility coordinates.
@MainActor
enum Screens {
    private static var mainTop: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }

    static func flip(_ rect: NSRect) -> CGRect {
        CGRect(x: rect.minX, y: mainTop - rect.maxY, width: rect.width, height: rect.height)
    }

    static var mouse: CGPoint {
        let m = NSEvent.mouseLocation
        return CGPoint(x: m.x, y: mainTop - m.y)
    }

    static func screen(at point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { flip($0.frame).contains(point) }
    }

    /// The screen a window is mostly on: the one holding its centre.
    static func screen(of frame: CGRect) -> NSScreen? {
        screen(at: CGPoint(x: frame.midX, y: frame.midY))
    }

    static var mouseScreen: NSScreen? { screen(at: mouse) ?? NSScreen.main }

    /// The part of a screen without menu bar and Dock.
    static func usableArea(of screen: NSScreen) -> CGRect { flip(screen.visibleFrame) }
}
