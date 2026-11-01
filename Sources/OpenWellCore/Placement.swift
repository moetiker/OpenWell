import CoreGraphics

/// Where a window prefers to go when several free spots exist.
public enum Anchor: String, Codable, Sendable, CaseIterable {
    case topLeft = "top-left"
    case topRight = "top-right"
    case center
    case mouse
}

/// A window already on the screen.
public struct Obstacle: Equatable, Sendable {
    public var frame: CGRect
    /// A window of a terminal OpenWell manages. The second search tier avoids only these.
    public var isManaged: Bool

    public init(_ frame: CGRect, managed: Bool = false) {
        self.frame = frame
        self.isManaged = managed
    }
}

/// All coordinates are global, from the top left of the main screen with y growing
/// downward: the system of the accessibility API and of CGWindowList.
public enum Placement {
    /// The frame for a new window of `size` inside `area`.
    ///
    /// The search runs in three tiers: a spot that overlaps no obstacle, then a spot
    /// that overlaps no managed obstacle, then the spot with the least overlap. Within a
    /// tier the spot whose origin lies closest to `target` wins. A window larger than
    /// the area is shrunk to fit.
    public static func frame(
        for size: CGSize, in area: CGRect, avoiding obstacles: [Obstacle],
        gap: CGFloat = 0, target: CGPoint
    ) -> CGRect {
        let gap = max(0, gap)
        // keep the gap to the screen edges as well, unless the screen is too small for it
        let inner = area.width > 2 * gap && area.height > 2 * gap ? area.insetBy(dx: gap, dy: gap) : area
        let w = min(size.width, inner.width)
        let h = min(size.height, inner.height)
        let grown = obstacles.map { Obstacle($0.frame.insetBy(dx: -gap, dy: -gap), managed: $0.isManaged) }

        let candidates = Self.candidates(width: w, height: h, in: inner, obstacles: grown, target: target)
        let distance = { (p: CGPoint) in hypot(p.x - target.x, p.y - target.y) }
        let closest = { (points: [CGPoint]) in points.min { distance($0) < distance($1) } }
        let frame = { (p: CGPoint) in CGRect(x: p.x, y: p.y, width: w, height: h) }

        if let p = closest(candidates.filter { overlap(frame($0), grown) == 0 }) {
            return frame(p)
        }
        let managed = grown.filter(\.isManaged)
        if let p = closest(candidates.filter { overlap(frame($0), managed) == 0 }) {
            return frame(p)
        }
        // the area corners are always candidates, so the list is never empty
        let best = candidates.min {
            let a = overlap(frame($0), grown), b = overlap(frame($1), grown)
            return a != b ? a < b : distance($0) < distance($1)
        }!
        return frame(best)
    }

    /// The origin `anchor` asks for, for a window of `size` in `area`. `mouse` is the
    /// pointer position, used by `.mouse` and ignored otherwise; without it `.mouse`
    /// counts as `.topLeft`.
    public static func target(
        _ anchor: Anchor, size: CGSize, in area: CGRect, mouse: CGPoint? = nil
    ) -> CGPoint {
        switch anchor {
        case .topLeft:
            return area.origin
        case .topRight:
            return CGPoint(x: area.maxX - size.width, y: area.minY)
        case .center:
            return CGPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2)
        case .mouse:
            guard let mouse else { return area.origin }
            return CGPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height / 2)
        }
    }

    /// Every origin where a window edge meets an area edge or an obstacle edge, plus
    /// the target moved into the area, kept only when the whole window stays inside
    /// the area. Without the target, `.center` on an empty screen ends in a corner.
    static func candidates(width w: CGFloat, height h: CGFloat, in area: CGRect,
                           obstacles: [Obstacle], target: CGPoint) -> [CGPoint] {
        let tx = min(max(target.x, area.minX), area.maxX - w)
        let ty = min(max(target.y, area.minY), area.maxY - h)
        var xs: Set<CGFloat> = [area.minX, area.maxX - w, tx]
        var ys: Set<CGFloat> = [area.minY, area.maxY - h, ty]
        for o in obstacles {
            xs.formUnion([o.frame.maxX, o.frame.minX - w])
            ys.formUnion([o.frame.maxY, o.frame.minY - h])
        }
        let eps: CGFloat = 0.5
        let fitX = xs.filter { $0 >= area.minX - eps && $0 + w <= area.maxX + eps }
        let fitY = ys.filter { $0 >= area.minY - eps && $0 + h <= area.maxY + eps }
        return fitY.flatMap { y in fitX.map { x in CGPoint(x: x, y: y) } }
    }

    /// The total area `frame` shares with `obstacles`. Touching edges count as zero.
    public static func overlap(_ frame: CGRect, _ obstacles: [Obstacle]) -> CGFloat {
        obstacles.reduce(0) { sum, o in
            let i = frame.intersection(o.frame)
            return i.isNull || i.width <= 0 || i.height <= 0 ? sum : sum + i.width * i.height
        }
    }
}
