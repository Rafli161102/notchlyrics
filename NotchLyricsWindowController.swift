import Cocoa
import QuartzCore

final class NotchTrackingView: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }
}

final class NotchLyricsWindowController: NSWindowController {
    private let container = NotchTrackingView()
    private let notchView: TouchBarLyricsView
    private let artworkView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let artistLabel = NSTextField(labelWithString: "")
    private let albumLabel = NSTextField(labelWithString: "")
    private let previousButton = NSButton()
    private let playPauseButton = NSButton()
    private let nextButton = NSButton()
    private let onSendCommand: (Int) -> Void

    private let collapsedSize = CGSize(width: 320, height: 44)
    private let expandedSize = CGSize(width: 460, height: 96)
    private var baseTheme = ThemeStore.shared.activeTheme
    private var isExpanded = false
    private var isPlaying = false
    private var lastArtworkIdentity: String?
    private var screenObserver: NSObjectProtocol?
    private var reduceMotionObserver: NSObjectProtocol?

    init(onTogglePlayPause: @escaping () -> Void, onSendCommand: @escaping (Int) -> Void) {
        notchView = TouchBarLyricsView(onTogglePlayPause: onTogglePlayPause)
        self.onSendCommand = onSendCommand

        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: collapsedSize),
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
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        super.init(window: panel)

        setupContent(panel)
        applyTheme(ThemeStore.shared.activeTheme)
        updatePosition()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.updatePosition() }

        reduceMotionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.applyNotchLayout(animated: false) }
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
        notchView.applyTheme(Self.notchTheme(from: theme, expanded: isExpanded))
        styleText(with: theme)
        applyNotchLayout(animated: false)
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
        songPalette: SongColorPalette?,
        artist: String,
        album: String,
        artworkData: String?
    ) {
        self.isPlaying = isPlaying
        titleLabel.stringValue = trackTitle.isEmpty ? "Safari" : trackTitle
        artistLabel.stringValue = artist
        albumLabel.stringValue = album
        setArtwork(artworkData)

        let symbol = isPlaying ? "pause.fill" : "play.fill"
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: isPlaying ? "Pause" : "Play") {
            playPauseButton.image = image
        }

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
            setExpanded(false, animated: false)
        }
    }

    @objc private func previousTrack() { onSendCommand(5) }
    @objc private func togglePlayPause() { onSendCommand(2) }
    @objc private func nextTrack() { onSendCommand(4) }

    private func setupContent(_ panel: NSPanel) {
        container.frame = CGRect(origin: .zero, size: collapsedSize)
        container.autoresizingMask = [.width, .height]
        container.wantsLayer = true
        container.onHoverChanged = { [weak self] hovered in
            self?.setExpanded(hovered, animated: true)
        }
        panel.contentView = container

        notchView.frame = CGRect(origin: .zero, size: collapsedSize)
        notchView.autoresizingMask = [.width, .height]
        container.addSubview(notchView)

        artworkView.frame = CGRect(x: 16, y: 12, width: 32, height: 32)
        artworkView.imageScaling = .scaleProportionallyUpOrDown
        artworkView.wantsLayer = true
        artworkView.layer?.cornerRadius = 6
        artworkView.layer?.masksToBounds = true
        container.addSubview(artworkView)

        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        container.addSubview(titleLabel)

        artistLabel.lineBreakMode = .byTruncatingTail
        artistLabel.maximumNumberOfLines = 1
        container.addSubview(artistLabel)

        albumLabel.lineBreakMode = .byTruncatingTail
        albumLabel.maximumNumberOfLines = 1
        container.addSubview(albumLabel)

        configureButton(previousButton, symbol: "backward.fill", label: "Lagu sebelumnya", action: #selector(previousTrack))
        configureButton(playPauseButton, symbol: "pause.fill", label: "Putar atau jeda", action: #selector(togglePlayPause))
        configureButton(nextButton, symbol: "forward.fill", label: "Lagu berikutnya", action: #selector(nextTrack))

        for view in [artworkView, titleLabel, artistLabel, albumLabel, previousButton, playPauseButton, nextButton] {
            view.isHidden = true
        }
    }

    private func configureButton(_ button: NSButton, symbol: String, label: String, action: Selector) {
        button.bezelStyle = .rounded
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.target = self
        button.action = action
        button.setAccessibilityLabel(label)
        button.toolTip = label
        button.keyEquivalent = ""
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label) {
            button.image = image
        }
        button.imagePosition = .imageOnly
        container.addSubview(button)
    }

    private func styleText(with theme: TouchBarTheme) {
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = NSColor(hex: theme.mainTextHex).ensuringContrast(against: NSColor(hex: theme.backgroundHex), minRatio: 4.5)
        artistLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        artistLabel.textColor = NSColor(hex: theme.trackTextHex).ensuringContrast(against: NSColor(hex: theme.backgroundHex), minRatio: 4.5)
        albumLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        albumLabel.textColor = artistLabel.textColor?.withAlphaComponent(0.78)
        previousButton.contentTintColor = titleLabel.textColor
        playPauseButton.contentTintColor = titleLabel.textColor
        nextButton.contentTintColor = titleLabel.textColor
        playPauseButton.layer?.backgroundColor = NSColor(hex: theme.borderHex).withAlphaComponent(0.5).cgColor
    }

    private func setArtwork(_ encoded: String?) {
        guard let encoded = encoded, !encoded.isEmpty else {
            if lastArtworkIdentity != nil {
                lastArtworkIdentity = nil
                artworkView.image = nil
            }
            return
        }

        let ns = encoded as NSString
        let identity = "\(ns.length)|\(ns.substring(to: min(24, ns.length)))|\(ns.substring(from: max(0, ns.length - 24)))"
        guard identity != lastArtworkIdentity else { return }
        lastArtworkIdentity = identity

        if let data = Data(base64Encoded: encoded),
           let image = NSImage(data: data) {
            artworkView.image = image
        } else {
            artworkView.image = nil
        }
    }

    private func setExpanded(_ expanded: Bool, animated: Bool) {
        guard expanded != isExpanded else { return }
        isExpanded = expanded
        notchView.applyTheme(Self.notchTheme(from: baseTheme, expanded: expanded))
        applyNotchLayout(animated: animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    private func applyNotchLayout(animated: Bool) {
        guard let window = window else { return }
        let size = isExpanded ? expandedSize : collapsedSize
        let topInset = currentTopInset
        let screenFrame = currentScreenFrame
        let frame = NotchGeometry.windowFrame(screenFrame: screenFrame, size: size, topInset: topInset)

        let duration: TimeInterval = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.18 : 0

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
            context.allowsImplicitAnimation = animated
            window.animator().setFrame(frame, display: true)
        }

        container.frame = CGRect(origin: .zero, size: size)
        container.layer?.backgroundColor = NSColor(hex: baseTheme.backgroundHex).cgColor
        container.layer?.cornerRadius = isExpanded ? 16 : 12
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor(hex: baseTheme.borderHex).withAlphaComponent(0.55).cgColor
        container.layer?.masksToBounds = true
        layoutContent(size: size, expanded: isExpanded)
    }

    private func layoutContent(size: CGSize, expanded: Bool) {
        let w = size.width

        if !expanded {
            notchView.frame = CGRect(origin: .zero, size: size)
            for view in [artworkView, titleLabel, artistLabel, albumLabel, previousButton, playPauseButton, nextButton] {
                view.isHidden = true
            }
            return
        }

        // Expanded notch: artwork left, lyric top-right, metadata middle, native controls bottom.
        notchView.frame = CGRect(x: 56, y: 48, width: w - 72, height: 44)
        artworkView.frame = CGRect(x: 16, y: 50, width: 32, height: 32)
        artworkView.isHidden = artworkView.image == nil

        titleLabel.frame = CGRect(x: 56, y: 34, width: w - 72, height: 16)
        artistLabel.frame = CGRect(x: 56, y: 20, width: w - 180, height: 14)
        albumLabel.frame = CGRect(x: 56, y: 6, width: w - 180, height: 13)
        titleLabel.isHidden = false
        artistLabel.isHidden = false
        albumLabel.isHidden = artistLabel.stringValue.isEmpty && albumLabel.stringValue.isEmpty

        let controlsY: CGFloat = 4
        let buttonSize: CGFloat = 44
        let buttonSpacing: CGFloat = 8
        let totalWidth = buttonSize * 3 + buttonSpacing * 2
        let startX = (w - totalWidth) / 2
        previousButton.frame = CGRect(x: startX, y: controlsY, width: buttonSize, height: buttonSize)
        playPauseButton.frame = CGRect(x: startX + buttonSize + buttonSpacing, y: controlsY, width: buttonSize, height: buttonSize)
        nextButton.frame = CGRect(x: startX + (buttonSize + buttonSpacing) * 2, y: controlsY, width: buttonSize, height: buttonSize)
        previousButton.isHidden = false
        playPauseButton.isHidden = false
        nextButton.isHidden = false
    }

    private var currentTopInset: CGFloat {
        (currentScreen?.safeAreaInsets.top ?? 0) > 0 ? 0 : 8
    }

    private var currentScreenFrame: CGRect {
        currentScreen?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private var currentScreen: NSScreen? {
        window?.screen ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func updatePosition() {
        applyNotchLayout(animated: false)
    }

    private static func notchTheme(from theme: TouchBarTheme, expanded: Bool) -> TouchBarTheme {
        var notch = theme
        notch.layoutMode = .lyricsOnly
        notch.trackTitlePosition = .hidden
        notch.showTrackTitle = false
        notch.controlsPosition = .hidden
        notch.eqPosition = .hidden
        notch.progressPosition = .bottom
        notch.showProgressBar = true
        notch.showBorder = true
        notch.cornerRadius = expanded ? 16 : 12
        notch.mainFontSize = max(13, theme.mainFontSize)
        notch.backingFontSize = max(10, theme.backingFontSize)
        notch.horizontalPadding = max(12, theme.horizontalPadding)
        return notch
    }
}
