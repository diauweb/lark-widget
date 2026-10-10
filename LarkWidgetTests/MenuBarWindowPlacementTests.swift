import Foundation

@main
private struct MenuBarWindowPlacementTests {
    static func main() {
        // Reproduce the screenshot: the 900-point week panel extends left of the display.
        let screen = CGRect(x: 0, y: 70, width: 1470, height: 862)
        let overflowing = CGRect(x: -275, y: 312, width: 900, height: 620)
        let corrected = CGRect(origin: MenuBarWindowPlacement.origin(for: overflowing, in: screen),
                               size: overflowing.size)
        precondition(screen.contains(corrected), "The full week must be visible")
        precondition(corrected.minX == 8 && corrected.maxY == screen.maxY - 8,
                     "Move right and leave the requested margin below the menu bar")
        let alreadyInside = CGRect(x: 50, y: 200, width: 900, height: 620)
        precondition(MenuBarWindowPlacement.origin(for: alreadyInside, in: screen) == alreadyInside.origin,
                     "Leave an already-visible panel in place")
        precondition(corrected.size == overflowing.size, "Never shrink the calendar")

        // Screen coordinates may be negative or vertically offset; both view modes must fit.
        for display in [screen, screen.offsetBy(dx: -1470, dy: 200), screen.offsetBy(dx: 1470, dy: -900)] {
            for size in [CGSize(width: 900, height: 620), CGSize(width: 400, height: 620)] {
                for x in stride(from: display.minX - 1000, through: display.maxX + 1000, by: 200) {
                    for y in [display.minY - 400, display.midY, display.maxY + 400] {
                        let proposed = CGRect(origin: CGPoint(x: x, y: y), size: size)
                        let origin = MenuBarWindowPlacement.origin(for: proposed, in: display)
                        let placed = CGRect(origin: origin, size: size)
                        precondition(display.contains(placed), "Keep every edge on the chosen display")
                        precondition(MenuBarWindowPlacement.origin(for: placed, in: display) == origin,
                                     "A second notification must not move the panel again")
                    }
                }
            }
        }
        let tinyScreen = CGRect(x: 0, y: 0, width: 800, height: 500)
        let oversized = CGRect(origin: .zero, size: CGSize(width: 900, height: 620))
        let origin = MenuBarWindowPlacement.origin(for: oversized, in: tinyScreen)
        precondition(origin.x == 8 && origin.y + oversized.height == 492,
                     "If fitting is impossible, preserve size and keep the top-left controls reachable")
        print("PASS: screenshot overflow, both view sizes, offset displays, all edges, stable correction, oversized display fallback")
    }
}
