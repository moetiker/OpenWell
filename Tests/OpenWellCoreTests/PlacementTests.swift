import CoreGraphics
import Testing
@testable import OpenWellCore

@Suite struct PlacementTests {
    let area = CGRect(x: 0, y: 25, width: 1000, height: 800)
    let size = CGSize(width: 300, height: 200)

    func place(_ obstacles: [Obstacle], anchor: Anchor = .topLeft, gap: CGFloat = 0,
               size: CGSize? = nil, mouse: CGPoint? = nil) -> CGRect {
        let size = size ?? self.size
        let target = Placement.target(anchor, size: size, in: area, mouse: mouse)
        return Placement.frame(for: size, in: area, avoiding: obstacles, gap: gap, target: target)
    }

    @Test func emptyScreenTakesTheAnchorCorner() {
        #expect(place([]) == CGRect(x: 0, y: 25, width: 300, height: 200))
        #expect(place([], anchor: .topRight) == CGRect(x: 700, y: 25, width: 300, height: 200))
        #expect(place([], anchor: .center) == CGRect(x: 350, y: 325, width: 300, height: 200))
    }

    @Test func centerAnchorAvoidsAWindowInTheMiddle() {
        let frame = place([Obstacle(CGRect(x: 300, y: 225, width: 400, height: 400))], anchor: .center)
        #expect(Placement.overlap(frame, [Obstacle(CGRect(x: 300, y: 225, width: 400, height: 400))]) == 0)
    }

    // Of two free spots the one whose origin is closer to the anchor wins: below a
    // wide window rather than beside it.
    @Test func prefersTheCloserSpot() {
        let frame = place([Obstacle(CGRect(x: 0, y: 25, width: 400, height: 300))])
        #expect(frame == CGRect(x: 0, y: 325, width: 300, height: 200))
    }

    @Test func goesRightOfAFullHeightWindow() {
        let frame = place([Obstacle(CGRect(x: 0, y: 25, width: 400, height: 800))])
        #expect(frame == CGRect(x: 400, y: 25, width: 300, height: 200))
    }

    // The case the plan's first wording missed: flush left of an obstacle.
    @Test func goesLeftOfAWindowInTheTopRightCorner() {
        let frame = place([Obstacle(CGRect(x: 600, y: 25, width: 400, height: 800))], anchor: .topRight)
        #expect(frame == CGRect(x: 300, y: 25, width: 300, height: 200))
    }

    @Test func findsTheOnlyGapBetweenWindows() {
        // a free slot of exactly 300 wide between two windows that fill the top row,
        // the bottom half is covered by a third
        let frame = place([
            Obstacle(CGRect(x: 0, y: 25, width: 350, height: 400)),
            Obstacle(CGRect(x: 650, y: 25, width: 350, height: 400)),
            Obstacle(CGRect(x: 0, y: 425, width: 1000, height: 400)),
        ])
        #expect(frame == CGRect(x: 350, y: 25, width: 300, height: 200))
    }

    @Test func keepsTheGap() {
        let frame = place([Obstacle(CGRect(x: 0, y: 25, width: 400, height: 800))], gap: 10)
        #expect(frame == CGRect(x: 410, y: 35, width: 300, height: 200))
    }

    @Test func coversAMaximizedWindowButNotATerminal() {
        let browser = Obstacle(area)
        let terminal = Obstacle(CGRect(x: 0, y: 25, width: 300, height: 800), managed: true)
        let frame = place([browser, terminal])
        #expect(frame == CGRect(x: 300, y: 25, width: 300, height: 200))
    }

    @Test func leastOverlapWhenTerminalsFillTheScreen() {
        // terminals everywhere except a strip of 100 at the right edge
        let frame = place([Obstacle(CGRect(x: 0, y: 25, width: 900, height: 800), managed: true)])
        #expect(frame == CGRect(x: 700, y: 25, width: 300, height: 200))
    }

    @Test func shrinksAWindowLargerThanTheScreen() {
        let frame = place([], gap: 10, size: CGSize(width: 2000, height: 300))
        #expect(frame == CGRect(x: 10, y: 35, width: 980, height: 300))
    }

    @Test func mouseAnchorPicksTheSpotNearThePointer() {
        let frame = place([], anchor: .mouse, mouse: CGPoint(x: 990, y: 815))
        #expect(frame == CGRect(x: 700, y: 625, width: 300, height: 200))
    }

    @Test func mouseAnchorWithoutPointerIsTopLeft() {
        #expect(Placement.target(.mouse, size: size, in: area) == area.origin)
    }

    @Test func anchorNamesMatchTheConfig() {
        #expect(Anchor.allCases.map(\.rawValue) == ["top-left", "top-right", "center", "mouse"])
    }

    @Test func touchingEdgesDoNotOverlap() {
        let a = Obstacle(CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(Placement.overlap(CGRect(x: 100, y: 0, width: 50, height: 50), [a]) == 0)
        #expect(Placement.overlap(CGRect(x: 90, y: 0, width: 50, height: 50), [a]) == 500)
    }
}
