import CoreGraphics

enum NotchGeometry {
    static let phi: CGFloat = 1.6180339887

    /// Top-center window in AppKit screen coordinates (origin at bottom-left).
    static func windowFrame(screenFrame: CGRect, size: CGSize, topInset: CGFloat) -> CGRect {
        CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height - topInset,
            width: size.width,
            height: size.height
        )
    }

    /// Computes balanced Golden Ratio (phi = 1.618) frame for collapsed & hover-expanded notch
    /// across attached bezel, floating island, and wide edge strip styles.
    static func adaptiveFrame(
        screenFrame: CGRect,
        expanded: Bool,
        style: ThemeNotchStyle,
        physicalNotchInset: CGFloat
    ) -> CGRect {
        let hasPhysicalNotch = physicalNotchInset > 0

        let width: CGFloat
        let height: CGFloat
        let topInset: CGFloat

        switch style {
        case .attachedBezel:
            // Collapsed: 336x48; Expanded scales by phi (336 * 1.618 = 544) & room for multi-line lyrics without truncation
            let collapsedW: CGFloat = 336
            width = expanded ? (collapsedW * phi).rounded() : collapsedW
            if hasPhysicalNotch {
                height = expanded ? (physicalNotchInset + 82) : (physicalNotchInset + 42)
                topInset = 0
            } else {
                height = expanded ? 110 : 48
                topInset = 0
            }
        case .floatingIsland:
            // Collapsed: 318x48; Expanded scales by phi (318 * 1.618 = 515) & 108pt height
            let collapsedW: CGFloat = 318
            width = expanded ? (collapsedW * phi).rounded() : collapsedW
            height = expanded ? 108 : 48
            topInset = hasPhysicalNotch ? (physicalNotchInset + 5) : 8
        case .edgeDockStrip:
            // Balanced wide top-bezel dock scaled around 488 -> 488 * 1.25 (~610 Fibonacci)
            width = min(screenFrame.width - 34, expanded ? 610 : 488)
            height = hasPhysicalNotch
                ? (expanded ? (physicalNotchInset + 78) : (physicalNotchInset + 40))
                : (expanded ? 104 : 46)
            topInset = 0
        }

        return windowFrame(
            screenFrame: screenFrame,
            size: CGSize(width: width, height: height),
            topInset: topInset
        )
    }
}
