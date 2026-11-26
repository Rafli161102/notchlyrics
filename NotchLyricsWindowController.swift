import Cocoa

final class NotchLyricsWindowController: NSWindowController {
    private let notchView: TouchBarLyricsView
    private let notchSize = CGSize(width: 320, height: 44)
    private var baseTheme = ThemeStore.shared.activeTheme
    private var screenObserver: NSObjectProtocol?
    private var reduceMotionObserver: NSObjectProtocol?

    init(onTogglePlayPause: @escaping () -> Void) {
        notchView = TouchBarLyricsView(onTogglePlayPause: onTogglePlayPause)

        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: notchSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "NotchLyrics"
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        super.init(window: panel)

        notchView.frame = CGRect(origin: .zero, size: notchSize)
        notchView.autoresizingMask = [.width, .height]
        panel.contentView = notchView

        applyTheme(ThemeStore.shared.activeTheme)
        updatePosition()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updatePosition()
        }

        reduceMotionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updatePosition()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let screenObserver = screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let reduceMotionObserver = reduceMotionObserver { NSWorkspace.shared.notificationCenter.removeObserver(reduceMotionObserver) }
    }

    func applyTheme(_ theme: TouchBarTheme) {
        baseTheme = theme
        notchView.applyTheme(Self.notchTheme(from: theme))
    }

    func applyArtworkPalette(_ palette: SongColorPalette?) {
        notchView.applyArtworkPalette(palette)
    }

    func setCharacterAnimationEnabled(_ enabled: Bool) {
        notchView.characterAnimationEnabled = enabled
    }

    func update(
        trackTitle: String,
        mainText: String,
        backingText: String?,
        songProgress: CGFloat,
        lineProgress: CGFloat,
        backingLineProgress: CGFloat?,
        vocalEnergy: CGFloat,
        backingVocalEnergy: CGFloat,
        isPlaying: Bool,
        isVocalSynced: Bool,
        songPalette: SongColorPalette?
    ) {
        notchView.update(
            trackTitle: trackTitle,
            mainText: mainText,
            backingText: backingText,
            songProgress: songProgress,
            lineProgress: lineProgress,
            backingLineProgress: backingLineProgress,
            vocalEnergy: vocalEnergy,
            backingVocalEnergy: backingVocalEnergy,
            isPlaying: isPlaying,
            isVocalSynced: isVocalSynced,
            songPalette: songPalette
        )
    }

    func setVisible(_ visible: Bool) {
        guard let window = window else { return }
        if visible {
            updatePosition()
            window.orderFrontRegardless()
        } else {
            window.orderOut(nil)
        }
    }

    private func updatePosition() {
        guard let window = window else { return }
        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen = screen else { return }

        // Physical-notch Macs already reserve the top area; place flush at the top.
        // No-notch Macs get a small inset so the synthetic island clears the menu bar.
        let topInset: CGFloat = screen.safeAreaInsets.top > 0 ? 0 : 8
        let frame = NotchGeometry.windowFrame(
            screenFrame: screen.frame,
            size: notchSize,
            topInset: topInset
        )
        window.setFrame(frame, display: true)
    }

    private static func notchTheme(from theme: TouchBarTheme) -> TouchBarTheme {
        var notch = theme
        notch.layoutMode = .lyricsOnly
        notch.trackTitlePosition = .hidden
        notch.showTrackTitle = false
        notch.controlsPosition = .hidden
        notch.eqPosition = .hidden
        notch.progressPosition = .bottom
        notch.showProgressBar = true
        notch.showBorder = true
        notch.cornerRadius = 12
        notch.mainFontSize = max(13, theme.mainFontSize)
        notch.backingFontSize = max(10, theme.backingFontSize)
        notch.horizontalPadding = max(12, theme.horizontalPadding)
        return notch
    }
}
