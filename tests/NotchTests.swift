import CoreGraphics
import Foundation

@main
enum NotchTests {
    static var failures = 0

    static func check(_ condition: Bool, _ name: String, _ detail: String = "") {
        if condition {
            print("PASS \(name)")
        } else {
            failures += 1
            print("FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
        }
    }

    static func main() {
        // Break caught: losing the existing Touch Bar default when adding notch output.
        check(DisplayMode.defaultMode == .touchBar, "default mode preserves Touch Bar")

        // Break caught: wrong mode routing; notch-only must not open Touch Bar.
        check(!DisplayMode.touchBar.showsNotch, "Touch Bar mode hides notch")
        check(DisplayMode.notch.showsNotch && !DisplayMode.notch.showsTouchBar, "notch mode shows only notch")
        check(DisplayMode.both.showsNotch && DisplayMode.both.showsTouchBar, "both mode shows both outputs")
        check(!DisplayMode.hidden.showsNotch && !DisplayMode.hidden.showsTouchBar, "hidden mode shows no output")
        check(DisplayMode.allCases.count == 4, "all display modes are retained")

        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = CGSize(width: 320, height: 44)

        // Break caught: placing the overlay below the menu bar or off-center horizontally.
        check(
            NotchGeometry.windowFrame(screenFrame: screen, size: size, topInset: 8)
                == CGRect(x: 560, y: 848, width: 320, height: 44),
            "top-center placement with top inset"
        )
        check(
            NotchGeometry.windowFrame(screenFrame: screen, size: size, topInset: 0)
                == CGRect(x: 560, y: 856, width: 320, height: 44),
            "top-center placement without inset"
        )

        // Break caught: using primary-display coordinates on a display with a negative origin.
        let secondary = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        check(
            NotchGeometry.windowFrame(screenFrame: secondary, size: size, topInset: 8)
                == CGRect(x: -880, y: 848, width: 320, height: 44),
            "secondary display uses its own frame"
        )

        // Adaptive bezel/floating/strip notch geometry checks
        let attachedFlat = NotchGeometry.adaptiveFrame(screenFrame: screen, expanded: false, style: .attachedBezel, physicalNotchInset: 0)
        check(attachedFlat.maxY == screen.maxY, "attachedBezel sits flush at top screen bezel (maxY == screen.maxY)")

        let floatingFlat = NotchGeometry.adaptiveFrame(screenFrame: screen, expanded: false, style: .floatingIsland, physicalNotchInset: 0)
        check(floatingFlat.maxY == screen.maxY - 8, "floatingIsland floats 8pt below top edge on flat screens")

        let stripFlat = NotchGeometry.adaptiveFrame(screenFrame: screen, expanded: false, style: .edgeDockStrip, physicalNotchInset: 0)
        check(stripFlat.maxY == screen.maxY && stripFlat.width > attachedFlat.width, "edgeDockStrip spans wide flush strip at top bezel")

        let attachedNotch = NotchGeometry.adaptiveFrame(screenFrame: screen, expanded: false, style: .attachedBezel, physicalNotchInset: 34)
        check(attachedNotch.maxY == screen.maxY && attachedNotch.height > 34, "attachedBezel clears physical notch chin below safeAreaTop=34")

        let expAttached = NotchGeometry.adaptiveFrame(screenFrame: screen, expanded: true, style: .attachedBezel, physicalNotchInset: 0)
        let ratioW = expAttached.width / attachedFlat.width
        check(abs(ratioW - NotchGeometry.phi) < 0.02, "expanded bezel width scales by Golden Ratio (phi)")

        let expFloating = NotchGeometry.adaptiveFrame(screenFrame: screen, expanded: true, style: .floatingIsland, physicalNotchInset: 0)
        let ratioFloatW = expFloating.width / floatingFlat.width
        check(abs(ratioFloatW - NotchGeometry.phi) < 0.02, "expanded floating island width scales by Golden Ratio (phi)")

        check(attachedFlat.height >= 46 && floatingFlat.height >= 46 && stripFlat.height >= 44, "collapsed notch styles reserve >= 44-48pt height for multi-line lyrics without truncation")

        if failures > 0 {
            print("\(failures) failing test(s)")
            exit(1)
        }
        print("All notch tests passed")
    }
}
