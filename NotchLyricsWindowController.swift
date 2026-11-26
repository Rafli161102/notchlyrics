import Cocoa
import QuartzCore

final class NotchTrackingView: NSView {
    var onHoverEntered: (() -> Void)?
    var onHoverExited: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverEntered?()
    }

    override func mouseMoved(with event: NSEvent) {
        onHoverEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onHoverExited?()
    }
}

final class NotchLyricsWindowController: NSWindowController {
    private let container = NotchTrackingView()
    private let notchView: TouchBarLyricsView
    private let artworkView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "00:00 / 00:00")
    private let previousButton = NSButton()
    private let playPauseButton = NSButton()
    private let nextButton = NSButton()
    private let dividerLayer = CALayer()
    private let onSendCommand: (Int) -> Void

    private var baseTheme = ThemeStore.shared.activeTheme
    private var isExpanded = false
    private var isPlaying = false
    private var lastArtworkIdentity: String?
    private var collapseGraceTimer: Timer?
    private var animationToken: Int = 0
    private var screenObserver: NSObjectProtocol?
    private var reduceMotionObserver: NSObjectProtocol?

    init(onTogglePlayPause: @escaping () -> Void, onSendCommand: @escaping (Int) -> Void) {
        notchView = TouchBarLyricsView(onTogglePlayPause: onTogglePlayPause)
        self.onSendCommand = onSendCommand

        let initialSize = CGSize(width: 336, height: 42)
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: initialSize),
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
        collapseGraceTimer?.invalidate()
        if let screenObserver = screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let reduceMotionObserver = reduceMotionObserver { NSWorkspace.shared.notificationCenter.removeObserver(reduceMotionObserver) }
    }

    func applyTheme(_ theme: TouchBarTheme) {
        baseTheme = theme
        previousButton.setAccessibilityLabel(L10n.tr("a11y.prevTrack"))
        playPauseButton.setAccessibilityLabel(L10n.tr("a11y.playPause"))
        nextButton.setAccessibilityLabel(L10n.tr("a11y.nextTrack"))
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
        vocalIntonation: CGFloat = 0.45,
        vocalOnset: CGFloat = 0.0,
        isPlaying: Bool,
        isVocalSynced: Bool,
        songPalette: SongColorPalette?,
        artist: String,
        album: String,
        artworkData: String?,
        elapsedTime: TimeInterval = 0,
        duration: TimeInterval = 0
    ) {
        self.isPlaying = isPlaying
        titleLabel.stringValue = trackTitle.isEmpty ? "Safari" : trackTitle
        let subParts = [artist, album].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        subtitleLabel.stringValue = subParts.joined(separator: " · ")
        timeLabel.stringValue = Self.formatTimePair(elapsed: elapsedTime, duration: duration)
        setArtwork(artworkData)
        applyExpandedTextColors(with: baseTheme, palette: songPalette)

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
            vocalIntonation: vocalIntonation,
            vocalOnset: vocalOnset,
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
            collapseGraceTimer?.invalidate()
            window.orderOut(nil)
            setExpanded(false, animated: false)
        }
    }

    @objc private func previousTrack() { onSendCommand(5) }
    @objc private func togglePlayPause() { onSendCommand(2) }
    @objc private func nextTrack() { onSendCommand(4) }

    private func setupContent(_ panel: NSPanel) {
        container.frame = CGRect(origin: .zero, size: panel.frame.size)
        container.autoresizingMask = [.width, .height]
        container.wantsLayer = true
        container.onHoverEntered = { [weak self] in
            self?.handleHoverEntered()
        }
        container.onHoverExited = { [weak self] in
            self?.scheduleHoverCollapseCheck()
        }
        panel.contentView = container

        notchView.frame = CGRect(origin: .zero, size: panel.frame.size)
        notchView.allowsMultiline = true
        container.addSubview(notchView)

        dividerLayer.opacity = 0
        container.layer?.addSublayer(dividerLayer)

        artworkView.frame = CGRect(x: 13, y: 44, width: 46, height: 46)
        artworkView.imageScaling = .scaleProportionallyUpOrDown
        artworkView.wantsLayer = true
        artworkView.layer?.cornerRadius = 11
        artworkView.layer?.masksToBounds = true
        container.addSubview(artworkView)

        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        container.addSubview(titleLabel)

        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.maximumNumberOfLines = 1
        container.addSubview(subtitleLabel)

        timeLabel.lineBreakMode = .byClipping
        timeLabel.maximumNumberOfLines = 1
        timeLabel.alignment = .right
        container.addSubview(timeLabel)

        configureButton(previousButton, symbol: "backward.fill", label: L10n.tr("a11y.prevTrack"), action: #selector(previousTrack))
        configureButton(playPauseButton, symbol: "pause.fill", label: L10n.tr("a11y.playPause"), action: #selector(togglePlayPause))
        configureButton(nextButton, symbol: "forward.fill", label: L10n.tr("a11y.nextTrack"), action: #selector(nextTrack))

        for view in [artworkView, titleLabel, subtitleLabel, timeLabel, previousButton, playPauseButton, nextButton] {
            view.alphaValue = 0
            view.isHidden = true
        }
    }

    private func handleHoverEntered() {
        collapseGraceTimer?.invalidate()
        collapseGraceTimer = nil
        setExpanded(true, animated: true)
    }

    private func scheduleHoverCollapseCheck() {
        collapseGraceTimer?.invalidate()
        let timer = Timer(timeInterval: 0.10, repeats: false) { [weak self] _ in
            guard let self = self, let window = self.window else { return }
            let mouse = NSEvent.mouseLocation
            if !window.frame.insetBy(dx: -4, dy: -4).contains(mouse) {
                self.setExpanded(false, animated: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        collapseGraceTimer = timer
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
        titleLabel.font = theme.fontStyle.font(size: 12.5, weight: .semibold)
        subtitleLabel.font = theme.fontStyle.font(size: 10.5, weight: .regular)
        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        dividerLayer.backgroundColor = NSColor(hex: theme.borderHex).withAlphaComponent(0.45).cgColor
        playPauseButton.layer?.backgroundColor = NSColor(hex: theme.borderHex).withAlphaComponent(0.5).cgColor
        applyExpandedTextColors(with: theme, palette: nil)
    }

    private func applyExpandedTextColors(with theme: TouchBarTheme, palette: SongColorPalette?) {
        let bg = NSColor(hex: theme.backgroundHex)
        let activePalette = (theme.colorSyncMode == .themeOnly) ? nil : palette
        let accent = activePalette?.accent.ensuringContrast(against: bg, minRatio: 4.5)
        let rawTitle = NSColor(hex: theme.mainTextHex)
        let rawMuted = NSColor(hex: theme.trackTextHex)
        let mix: CGFloat = (theme.colorSyncMode == .vividArtwork) ? 0.55 : 0.30

        let titleColor = (accent != nil ? rawTitle.blended(with: accent!, fraction: mix) : rawTitle)
            .ensuringContrast(against: bg, minRatio: 4.5)
        let mutedColor = (accent != nil ? rawMuted.blended(with: accent!, fraction: mix * 0.65) : rawMuted)
            .ensuringContrast(against: bg, minRatio: 4.5)

        titleLabel.textColor = titleColor
        subtitleLabel.textColor = mutedColor
        timeLabel.textColor = mutedColor
        previousButton.contentTintColor = titleColor
        playPauseButton.contentTintColor = titleColor
        nextButton.contentTintColor = titleColor
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

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let image: NSImage?
            if let data = Data(base64Encoded: encoded) {
                image = NSImage(data: data)
            } else {
                image = nil
            }
            DispatchQueue.main.async {
                guard let self = self, self.lastArtworkIdentity == identity else { return }
                self.artworkView.image = image
            }
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
        animationToken += 1
        let myToken = animationToken

        let style = baseTheme.notchStyle
        let safeTop = currentPhysicalNotchInset
        let targetFrame = NotchGeometry.adaptiveFrame(
            screenFrame: currentScreenFrame,
            expanded: isExpanded,
            style: style,
            physicalNotchInset: safeTop
        )
        let targetSize = targetFrame.size
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let shouldAnimate = animated && !reduceMotion
        let duration: TimeInterval = shouldAnimate ? (isExpanded ? 0.28 : 0.22) : 0.0

        // Fibonacci concentric radii (8, 13, 21) aligned to outer padding
        let targetCornerRadius: CGFloat
        let cornerMask: CACornerMask
        switch style {
        case .attachedBezel:
            targetCornerRadius = isExpanded ? 21 : 13
            cornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        case .edgeDockStrip:
            targetCornerRadius = isExpanded ? 16 : 10
            cornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        case .floatingIsland:
            targetCornerRadius = isExpanded ? 21 : 13
            cornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        }

        let targetNotchFrame = targetNotchViewFrame(size: targetSize, expanded: isExpanded, physicalNotchInset: safeTop)
        let expandedViews: [NSView] = [artworkView, titleLabel, subtitleLabel, timeLabel, previousButton, playPauseButton, nextButton]

        if isExpanded {
            layoutExpandedMetadata(size: targetSize, physicalNotchInset: safeTop)
            for view in expandedViews {
                if view.isHidden {
                    view.alphaValue = 0
                }
            }
            artworkView.isHidden = (artworkView.image == nil)
            titleLabel.isHidden = false
            subtitleLabel.isHidden = subtitleLabel.stringValue.isEmpty
            timeLabel.isHidden = timeLabel.stringValue.isEmpty
            previousButton.isHidden = false
            playPauseButton.isHidden = false
            nextButton.isHidden = false
        }

        if let layer = container.layer {
            layer.backgroundColor = NSColor(hex: baseTheme.backgroundHex).cgColor
            layer.maskedCorners = cornerMask
            layer.borderWidth = (style == .floatingIsland || baseTheme.showBorder) ? 1.0 : 0.5
            layer.borderColor = NSColor(hex: baseTheme.borderHex).withAlphaComponent(0.55).cgColor
            layer.masksToBounds = true

            if shouldAnimate {
                let radAnim = CABasicAnimation(keyPath: "cornerRadius")
                radAnim.fromValue = layer.cornerRadius
                radAnim.toValue = targetCornerRadius
                radAnim.duration = duration
                radAnim.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
                layer.add(radAnim, forKey: "cornerRadiusMorph")
            }
            layer.cornerRadius = targetCornerRadius
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            context.allowsImplicitAnimation = shouldAnimate

            window.animator().setFrame(targetFrame, display: true)
            notchView.animator().frame = targetNotchFrame
            dividerLayer.opacity = isExpanded ? 1.0 : 0.0

            let targetAlpha: CGFloat = isExpanded ? 1.0 : 0.0
            for view in expandedViews {
                view.animator().alphaValue = targetAlpha
            }
        }, completionHandler: { [weak self] in
            guard let self = self, self.animationToken == myToken else { return }
            if !self.isExpanded {
                for view in expandedViews {
                    view.isHidden = true
                }
            }
        })
    }

    private func targetNotchViewFrame(size: CGSize, expanded: Bool, physicalNotchInset: CGFloat) -> CGRect {
        let topClearance: CGFloat = (physicalNotchInset > 0 && baseTheme.notchStyle != .floatingIsland)
            ? physicalNotchInset
            : 0
        if !expanded {
            let lyricH = max(30, size.height - topClearance)
            return CGRect(x: 0, y: 0, width: size.width, height: lyricH)
        }
        // Golden Ratio split (61.8% upper lyrics stage / 38.2% lower metadata + controls stage)
        let usableH = size.height - topClearance
        let lowerBandH = (usableH / (1.0 + NotchGeometry.phi)).rounded()
        let padX: CGFloat = 16
        let hasArt = (artworkView.image != nil)
        let artSize = max(42, usableH - lowerBandH - 12)
        let lyricLeft: CGFloat = hasArt ? (padX + artSize + 13) : padX
        let lyricY = lowerBandH + 6
        let lyricH = max(34, usableH - lowerBandH - 12)
        return CGRect(x: lyricLeft, y: lyricY, width: max(140, size.width - lyricLeft - padX), height: lyricH)
    }

    private func layoutExpandedMetadata(size: CGSize, physicalNotchInset: CGFloat) {
        let w = size.width
        let topClearance: CGFloat = (physicalNotchInset > 0 && baseTheme.notchStyle != .floatingIsland)
            ? physicalNotchInset
            : 0
        let usableH = size.height - topClearance
        // Vertical 61.8% (top lyrics) : 38.2% (bottom metadata + controls)
        let lowerBandH = (usableH / (1.0 + NotchGeometry.phi)).rounded()
        let padX: CGFloat = 16
        let innerW = w - padX * 2

        let artSize = max(42, usableH - lowerBandH - 12)
        artworkView.frame = CGRect(x: padX, y: lowerBandH + 6, width: artSize, height: artSize)
        artworkView.layer?.cornerRadius = max(8, min(13, artSize * 0.24))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dividerLayer.frame = CGRect(x: padX, y: lowerBandH, width: innerW, height: 0.5)
        CATransaction.commit()

        // Horizontal Golden Ratio zone split inside lower band:
        // Left: Title + Artist · Album, Right: Song minutes readout + Transport Controls
        let controlsBtnSize: CGFloat = 28
        let controlsGap: CGFloat = 8
        let timeW: CGFloat = timeLabel.stringValue.count > 13 ? 104 : 84
        let controlsY = max(4, (lowerBandH - controlsBtnSize) / 2.0)
        let nextX = w - padX - controlsBtnSize
        let playX = nextX - controlsBtnSize - controlsGap
        let prevX = playX - controlsBtnSize - controlsGap
        let timeX = prevX - 10 - timeW
        let metaW = max(120, timeX - padX - 10)

        titleLabel.frame = CGRect(x: padX, y: max(18, lowerBandH - 19), width: metaW, height: 16)
        subtitleLabel.frame = CGRect(x: padX, y: 5, width: metaW, height: 14)

        timeLabel.frame = CGRect(x: timeX, y: max(4, (lowerBandH - 15) / 2.0), width: timeW, height: 15)
        previousButton.frame = CGRect(x: prevX, y: controlsY, width: controlsBtnSize, height: controlsBtnSize)
        playPauseButton.frame = CGRect(x: playX, y: controlsY, width: controlsBtnSize, height: controlsBtnSize)
        nextButton.frame = CGRect(x: nextX, y: controlsY, width: controlsBtnSize, height: controlsBtnSize)
    }

    static func formatTime(_ seconds: TimeInterval) -> String {
        let clamped = max(0, Int(seconds.rounded(.down)))
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let secs = clamped % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    static func formatTimePair(elapsed: TimeInterval, duration: TimeInterval) -> String {
        let safeDuration = max(0, duration)
        let safeElapsed = safeDuration > 0 ? min(max(0, elapsed), safeDuration) : max(0, elapsed)
        if safeDuration > 0 {
            return "\(formatTime(safeElapsed)) / \(formatTime(safeDuration))"
        }
        return formatTime(safeElapsed)
    }

    private var currentPhysicalNotchInset: CGFloat {
        currentScreen?.safeAreaInsets.top ?? 0
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
        notch.showBorder = false
        notch.cornerRadius = 0
        notch.mainFontSize = max(expanded ? 13.5 : 12.5, theme.mainFontSize)
        notch.backingFontSize = max(10.0, theme.backingFontSize)
        notch.horizontalPadding = expanded ? 4 : 12
        return notch
    }
}
