import CoreGraphics

enum NotchGeometry {
    /// Top-center window in AppKit screen coordinates (origin at bottom-left).
    static func windowFrame(screenFrame: CGRect, size: CGSize, topInset: CGFloat) -> CGRect {
        CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height - topInset,
            width: size.width,
            height: size.height
        )
    }
}
