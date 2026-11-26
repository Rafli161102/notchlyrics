import Cocoa
import QuartzCore

final class TouchBarLyricsView: NSView {
    private let bgLayer = CALayer()
    private let progressTrackLayer = CALayer()
    private let progressFillLayer = CALayer()
    private let syncDotLayer = CALayer()
    private var eqBars: [CALayer] = []

    private let trackLabel = NSTextField(labelWithString: "")
    private let lyricContainer = NSView()
    private let mainLyricLabel = NSTextField(labelWithString: "Putar lagu di Safari")
    private let backingLyricLabel = NSTextField(labelWithString: "")
    private let playPauseButton = NSButton()

    private var theme: TouchBarTheme = ThemeStore.shared.activeTheme
    private var currentMainSignature: String = ""
    private var currentBackingSignature: String = ""
    private var lineAppearDate: Date = .distantPast
    private var backingAppearDate: Date = .distantPast
    private var songProgress: CGFloat = 0
    private var isPlayingState: Bool = false
    private var onTogglePlayPause: (() -> Void)?

    private var currentBgColor: NSColor = NSColor(hex: ThemeStore.shared.activeTheme.backgroundHex)
    private var currentAccentColor: NSColor = NSColor(hex: ThemeStore.shared.activeTheme.accentHex)
    private var currentBackingColor: NSColor = NSColor(hex: ThemeStore.shared.activeTheme.backingTextHex)
    private var smoothedVocalEnergy: CGFloat = 0
    private var smoothedBackingEnergy: CGFloat = 0
    private var animPhase: Double = 0

    private var lastRenderedQuantizedStep: Int = -1
    private var lastRenderedMain: String = ""
    private var lastRenderedBacking: String = ""
    private var lastRenderedAccentHex: String = ""

    var characterAnimationEnabled: Bool = true {
        didSet {
            lastRenderedQuantizedStep = -1
        }
    }
    private var activeSongPalette: SongColorPalette?

    func applyArtworkPalette(_ palette: SongColorPalette?) {
        activeSongPalette = palette
        lastRenderedQuantizedStep = -1
    }

    init(onTogglePlayPause: @escaping () -> Void) {
        self.onTogglePlayPause = onTogglePlayPause
        super.init(frame: NSRect(x: 0, y: 0, width: 640, height: 30))
        wantsLayer = true
        setupLayersAndSubviews()
        applyTheme(ThemeStore.shared.activeTheme)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupLayersAndSubviews() {
        guard let root = layer else { return }

        root.addSublayer(bgLayer)

        progressTrackLayer.cornerRadius = 0.75
        bgLayer.addSublayer(progressTrackLayer)

        progressFillLayer.cornerRadius = 0.75
        progressTrackLayer.addSublayer(progressFillLayer)

        syncDotLayer.cornerRadius = 2.5
        bgLayer.addSublayer(syncDotLayer)

        for _ in 0..<4 {
            let bar = CALayer()
            bar.cornerRadius = 1.0
            bgLayer.addSublayer(bar)
            eqBars.append(bar)
        }

        trackLabel.wantsLayer = true
        trackLabel.lineBreakMode = .byTruncatingTail
        trackLabel.maximumNumberOfLines = 1
        addSubview(trackLabel)

        lyricContainer.wantsLayer = true
        lyricContainer.layer?.masksToBounds = true
        addSubview(lyricContainer)

        mainLyricLabel.wantsLayer = true
        mainLyricLabel.alignment = .center
        mainLyricLabel.lineBreakMode = .byTruncatingTail
        mainLyricLabel.maximumNumberOfLines = 1
        lyricContainer.addSubview(mainLyricLabel)

        backingLyricLabel.wantsLayer = true
        backingLyricLabel.alignment = .center
        backingLyricLabel.lineBreakMode = .byTruncatingTail
        backingLyricLabel.maximumNumberOfLines = 1
        backingLyricLabel.isHidden = true
        lyricContainer.addSubview(backingLyricLabel)

        playPauseButton.bezelStyle = .rounded
        playPauseButton.isBordered = false
        playPauseButton.wantsLayer = true
        playPauseButton.layer?.cornerRadius = 5
        playPauseButton.target = self
        playPauseButton.action = #selector(handlePlayPauseTapped)
        if let img = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: "Play or Pause") {
            playPauseButton.image = img
        }
        addSubview(playPauseButton)
    }

    func applyTheme(_ newTheme: TouchBarTheme) {
        theme = newTheme
        let bgColor = NSColor(hex: newTheme.backgroundHex)
        let borderColor = NSColor(hex: newTheme.borderHex)
        let mainColor = NSColor(hex: newTheme.mainTextHex)
        let backingColor = NSColor(hex: newTheme.backingTextHex)
        let accentColor = NSColor(hex: newTheme.accentHex)
        let trackColor = NSColor(hex: newTheme.trackTextHex)

        currentBgColor = bgColor
        currentAccentColor = accentColor
        currentBackingColor = backingColor
        lastRenderedQuantizedStep = -1

        let effectiveTrackPos = effectiveTrackPosition()
        let effectiveControlsPos = effectiveControlsPosition()
        let effectiveEQPos = effectiveEQPosition()
        let effectiveProgPos = effectiveProgressPosition()

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        bgLayer.backgroundColor = bgColor.cgColor
        bgLayer.cornerRadius = newTheme.cornerRadius
        bgLayer.borderWidth = newTheme.showBorder ? 1.0 : 0.0
        bgLayer.borderColor = borderColor.cgColor

        progressTrackLayer.isHidden = (effectiveProgPos == .hidden)
        progressTrackLayer.backgroundColor = borderColor.withAlphaComponent(0.55).cgColor
        progressFillLayer.backgroundColor = accentColor.cgColor

        syncDotLayer.isHidden = (effectiveEQPos == .hidden || newTheme.eqStyle == .none)
        for bar in eqBars {
            bar.isHidden = (effectiveEQPos == .hidden || newTheme.eqStyle != .bars)
        }

        CATransaction.commit()

        trackLabel.isHidden = (effectiveTrackPos == .hidden)
        trackLabel.font = newTheme.fontStyle.font(size: 10.5, weight: .medium)
        trackLabel.textColor = trackColor
        trackLabel.alignment = (effectiveTrackPos == .right) ? .right : .left

        playPauseButton.isHidden = (effectiveControlsPos == .hidden)
        playPauseButton.contentTintColor = mainColor
        playPauseButton.layer?.backgroundColor = borderColor.withAlphaComponent(0.55).cgColor

        mainLyricLabel.alignment = theme.textAlignment.nsAlignment
        backingLyricLabel.alignment = theme.textAlignment.nsAlignment

        needsLayout = true
    }

    private func effectiveTrackPosition() -> ThemeSlotPosition {
        if theme.layoutMode == .lyricsOnly || !theme.showTrackTitle { return .hidden }
        return theme.trackTitlePosition
    }

    private func effectiveControlsPosition() -> ThemeSlotPosition {
        if theme.layoutMode == .lyricsOnly { return .hidden }
        return theme.controlsPosition
    }

    private func effectiveEQPosition() -> ThemeSlotPosition {
        if theme.layoutMode == .lyricsOnly { return .hidden }
        return theme.eqPosition
    }

    private func effectiveProgressPosition() -> ThemeProgressPosition {
        if !theme.showProgressBar { return .hidden }
        return theme.progressPosition
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let h = bounds.height
        let pad = max(4.0, min(20.0, theme.horizontalPadding))

        let trackPos = effectiveTrackPosition()
        let ctrlPos = effectiveControlsPosition()
        let eqPos = effectiveEQPosition()
        let progPos = effectiveProgressPosition()

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        bgLayer.frame = bounds

        // Progress hairline placement (Bottom or Top)
        let progY: CGFloat = (progPos == .top) ? (h - 2.5) : 1.0
        progressTrackLayer.frame = CGRect(x: pad, y: progY, width: max(0, w - pad * 2), height: 1.5)
        progressFillLayer.frame = CGRect(x: 0, y: 0, width: progressTrackLayer.bounds.width * songProgress, height: 1.5)

        var leftCursor = pad
        var rightCursor = w - pad

        // Controls (Play/Pause) slot on Left or Right edge
        let btnWidth: CGFloat = 28
        if ctrlPos == .left {
            playPauseButton.frame = NSRect(x: leftCursor, y: (h - 22) / 2.0, width: btnWidth, height: 22)
            leftCursor += btnWidth + 6
        } else if ctrlPos == .right {
            playPauseButton.frame = NSRect(x: rightCursor - btnWidth, y: (h - 22) / 2.0, width: btnWidth, height: 22)
            rightCursor -= (btnWidth + 6)
        }

        // EQ / Sync Dot slot
        if eqPos != .hidden && theme.eqStyle != .none {
            let eqBlockW: CGFloat = (theme.eqStyle == .bars) ? 24.0 : 8.0
            let eqStartX: CGFloat
            if eqPos == .left {
                eqStartX = leftCursor
                leftCursor += eqBlockW + 6
            } else {
                eqStartX = rightCursor - eqBlockW
                rightCursor -= (eqBlockW + 6)
            }
            syncDotLayer.frame = CGRect(x: eqStartX, y: (h - 5) / 2.0 + 0.5, width: 5, height: 5)
            if theme.eqStyle == .bars {
                for (i, bar) in eqBars.enumerated() {
                    let bx = eqStartX + 8.0 + CGFloat(i) * 3.5
                    bar.frame = CGRect(x: bx, y: (h - 4) / 2.0 + 0.5, width: 2.0, height: 4.0)
                }
            }
        }

        // Track Title slot
        if trackPos != .hidden {
            let trackWidth = min(108.0, max(52.0, w * 0.16))
            if trackPos == .left {
                trackLabel.frame = NSRect(x: leftCursor, y: (h - 16) / 2.0, width: trackWidth, height: 16)
                leftCursor += trackWidth + 8
            } else {
                trackLabel.frame = NSRect(x: rightCursor - trackWidth, y: (h - 16) / 2.0, width: trackWidth, height: 16)
                rightCursor -= (trackWidth + 8)
            }
        }

        let lyricW = max(120, rightCursor - leftCursor)
        let containerY: CGFloat = (progPos == .top) ? 2.0 : 3.0
        lyricContainer.frame = NSRect(x: leftCursor, y: containerY, width: lyricW, height: h - 5.0)

        let hasMain = !mainLyricLabel.isHidden
        let hasBack = !backingLyricLabel.isHidden

        if hasMain && hasBack {
            switch theme.backingPlacement {
            case .below:
                mainLyricLabel.frame = NSRect(x: 0, y: 11, width: lyricW, height: 14)
                backingLyricLabel.frame = NSRect(x: 0, y: 0, width: lyricW, height: 12)
            case .above:
                backingLyricLabel.frame = NSRect(x: 0, y: 13, width: lyricW, height: 12)
                mainLyricLabel.frame = NSRect(x: 0, y: 0, width: lyricW, height: 14)
            case .inlineBeside:
                let mainW = lyricW * 0.64
                let backW = lyricW - mainW - 6
                mainLyricLabel.frame = NSRect(x: 0, y: 4, width: mainW, height: 17)
                backingLyricLabel.frame = NSRect(x: mainW + 6, y: 5, width: max(40, backW), height: 15)
            }
        } else if hasBack {
            backingLyricLabel.frame = NSRect(x: 0, y: 5, width: lyricW, height: 15)
        } else {
            mainLyricLabel.frame = NSRect(x: 0, y: 4, width: lyricW, height: 17)
        }

        CATransaction.commit()
    }

    @objc private func handlePlayPauseTapped() {
        onTogglePlayPause?()
    }

    func update(
        trackTitle: String,
        mainText: String,
        backingText: String?,
        songProgress: CGFloat,
        lineProgress: CGFloat = 1.0,
        backingLineProgress: CGFloat? = nil,
        vocalEnergy: CGFloat = 0.0,
        backingVocalEnergy: CGFloat? = nil,
        isPlaying: Bool,
        isVocalSynced: Bool,
        songPalette: SongColorPalette? = nil
    ) {
        let displayTitle = trackTitle.isEmpty ? "Safari" : trackTitle
        if trackLabel.stringValue != displayTitle {
            let titleFade = CATransition()
            titleFade.type = .fade
            titleFade.duration = 0.25
            trackLabel.layer?.add(titleFade, forKey: "trackTitleFade")
            trackLabel.stringValue = displayTitle
        }

        if isPlaying != isPlayingState {
            isPlayingState = isPlaying
            let symbol = isPlaying ? "pause.fill" : "play.fill"
            if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: symbol) {
                playPauseButton.image = img
            }
        }

        let speed = max(0.5, min(2.0, theme.animationSpeed))
        let targetEnergy: CGFloat = isPlaying ? max(0.08, min(1.0, vocalEnergy)) : 0.0
        let targetBgEnergy: CGFloat = isPlaying ? max(0.08, min(1.0, backingVocalEnergy ?? vocalEnergy)) : 0.0
        smoothedVocalEnergy = smoothedVocalEnergy * 0.72 + targetEnergy * 0.28
        smoothedBackingEnergy = smoothedBackingEnergy * 0.70 + targetBgEnergy * 0.30
        if isPlaying {
            animPhase += 0.24 * Double(speed)
        }

        // 1. Dynamic Song-Matched Color Resolution obeying ColorSyncMode
        let baseBg = NSColor(hex: theme.backgroundHex)
        let themeAccent = NSColor(hex: theme.accentHex)
        let themeBacking = NSColor(hex: theme.backingTextHex)

        let effectivePalette: SongColorPalette? = (theme.colorSyncMode == .themeOnly) ? nil : (songPalette ?? activeSongPalette)
        let targetBg: NSColor
        let targetAccent: NSColor
        let targetBacking: NSColor
        if let pal = effectivePalette {
            let tintStrength: CGFloat = (theme.colorSyncMode == .vividArtwork)
                ? (baseBg.relativeLuminance < 0.2 ? 0.16 : 0.09)
                : (baseBg.relativeLuminance < 0.2 ? 0.09 : 0.05)
            let liveTint = tintStrength + smoothedVocalEnergy * (theme.colorSyncMode == .vividArtwork ? 0.09 : 0.05)
            targetBg = baseBg.blended(with: pal.surfaceTint, fraction: liveTint)
            targetAccent = pal.accent.ensuringContrast(against: targetBg, minRatio: 4.5)
            targetBacking = pal.backingAccent.ensuringContrast(against: targetBg, minRatio: 4.5)
        } else {
            let liveTint = smoothedVocalEnergy * (baseBg.relativeLuminance < 0.2 ? 0.05 : 0.025)
            targetBg = baseBg.blended(with: themeAccent, fraction: liveTint)
            targetAccent = themeAccent.ensuringContrast(against: targetBg, minRatio: 4.5)
            targetBacking = themeBacking.ensuringContrast(against: targetBg, minRatio: 4.5)
        }

        currentBgColor = currentBgColor.blended(with: targetBg, fraction: 0.16)
        currentAccentColor = currentAccentColor.blended(with: targetAccent, fraction: 0.16)
        currentBackingColor = currentBackingColor.blended(with: targetBacking, fraction: 0.16)

        let effectiveMainColor = NSColor(hex: theme.mainTextHex).ensuringContrast(against: currentBgColor, minRatio: 4.5)
        let baseUpcoming = theme.upcomingTextHex.isEmpty
            ? effectiveMainColor.withAlphaComponent(0.50)
            : NSColor(hex: theme.upcomingTextHex).ensuringContrast(against: currentBgColor, minRatio: 3.0)
        let borderColor = NSColor(hex: theme.borderHex)
        let mutedColor = NSColor(hex: theme.trackTextHex).ensuringContrast(against: currentBgColor, minRatio: 4.5)

        // 2. Decoupled Entrance Choreography for Main Vocal vs Backing Vocal
        let cleanBacking = backingText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let formattedBacking = cleanBacking.isEmpty ? "" : "\(theme.backingTag) \(cleanBacking)"
        let mainChanged = (mainText != currentMainSignature)
        let backingChanged = (formattedBacking != currentBackingSignature)

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if mainChanged {
            currentMainSignature = mainText
            lineAppearDate = Date()

            if !reduceMotion {
                applyLineTransition(duration: 0.22 / Double(speed))
            }
            mainLyricLabel.isHidden = mainText.isEmpty
            needsLayout = true
            lastRenderedQuantizedStep = -1
        }

        if backingChanged {
            currentBackingSignature = formattedBacking
            backingAppearDate = Date()

            if !formattedBacking.isEmpty {
                backingLyricLabel.isHidden = false
                if !reduceMotion && theme.lineTransition != .none {
                    animateBackingEntrance(duration: 0.24 / Double(speed))
                }
            } else {
                backingLyricLabel.isHidden = true
            }
            needsLayout = true
            lastRenderedQuantizedStep = -1
        }

        // 3. Per-Character & Per-Word Kinetic Highlight obeying independent Main & Backing progress
        let animActive = characterAnimationEnabled && !reduceMotion && theme.wordAnimation != .solid
        let clampedMainProg = animActive ? min(max(0, lineProgress), 1) : 1.0
        let clampedBackProg = animActive ? min(max(0, backingLineProgress ?? lineProgress), 1) : 1.0
        let now = Date()
        let revealSpan = 0.24 / Double(speed)
        let mainReveal: CGFloat = animActive ? min(1.0, CGFloat(max(0.0, now.timeIntervalSince(lineAppearDate) / revealSpan))) : 1.0
        let backReveal: CGFloat = animActive ? min(1.0, CGFloat(max(0.0, now.timeIntervalSince(backingAppearDate) / revealSpan))) : 1.0

        let qMain = Int((clampedMainProg * 150.0).rounded()) + Int((mainReveal * 24.0).rounded()) * 1000
        let qBack = Int((clampedBackProg * 120.0).rounded()) + Int((backReveal * 20.0).rounded()) * 100
        let quantized = qMain &+ qBack * 100_000
        let accentSignature = "\(currentAccentColor.hexString)|\(currentBackingColor.hexString)|\(theme.wordAnimation.rawValue)|\(theme.textAlignment.rawValue)|\(Int(theme.mainFontSize * 10))"

        if mainChanged || backingChanged || quantized != lastRenderedQuantizedStep || mainText != lastRenderedMain || formattedBacking != lastRenderedBacking || accentSignature != lastRenderedAccentHex {
            lastRenderedQuantizedStep = quantized
            lastRenderedMain = mainText
            lastRenderedBacking = formattedBacking
            lastRenderedAccentHex = accentSignature

            let hasBoth = !mainText.isEmpty && !formattedBacking.isEmpty && theme.backingPlacement != .inlineBeside
            let mainFontSize = hasBoth ? min(theme.mainFontSize, 12.0) : theme.mainFontSize
            let backFontSize = hasBoth ? theme.backingFontSize : max(theme.backingFontSize, 11.0)
            let align = theme.textAlignment.nsAlignment

            mainLyricLabel.alignment = align
            backingLyricLabel.alignment = (theme.backingPlacement == .inlineBeside) ? .right : align

            if !mainText.isEmpty {
                mainLyricLabel.attributedStringValue = buildPerCharacterAttributedString(
                    text: mainText,
                    fontSize: mainFontSize,
                    baseWeight: .semibold,
                    highlightWeight: .bold,
                    progress: clampedMainProg,
                    introReveal: mainReveal,
                    vocalBoost: smoothedVocalEnergy,
                    sungColor: effectiveMainColor,
                    activeColor: currentAccentColor,
                    upcomingColor: baseUpcoming,
                    alignment: align
                )
            } else {
                mainLyricLabel.stringValue = ""
            }

            if !formattedBacking.isEmpty {
                backingLyricLabel.attributedStringValue = buildPerCharacterAttributedString(
                    text: formattedBacking,
                    fontSize: backFontSize,
                    baseWeight: .medium,
                    highlightWeight: .semibold,
                    progress: clampedBackProg,
                    introReveal: backReveal,
                    vocalBoost: smoothedBackingEnergy,
                    sungColor: currentBackingColor,
                    activeColor: effectiveMainColor,
                    upcomingColor: currentBackingColor.withAlphaComponent(0.55),
                    alignment: backingLyricLabel.alignment
                )
            } else {
                backingLyricLabel.stringValue = ""
            }
        }

        // 4. Tactile Audio-Reactive EQ Bars & Progress Layer Sync
        self.songProgress = min(max(0, songProgress), 1)
        let h = bounds.height
        let pad = max(4.0, min(20.0, theme.horizontalPadding))
        let eqPos = effectiveEQPosition()
        let ctrlPos = effectiveControlsPosition()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bgLayer.backgroundColor = currentBgColor.cgColor
        bgLayer.borderColor = (effectivePalette != nil ? currentAccentColor.withAlphaComponent(0.36) : borderColor).cgColor
        trackLabel.textColor = mutedColor
        playPauseButton.contentTintColor = effectiveMainColor

        if eqPos != .hidden && theme.eqStyle != .none {
            let rightEdgeReserved = (ctrlPos == .right) ? 34.0 : 0.0
            let leftEdgeReserved = (ctrlPos == .left) ? 34.0 : 0.0
            let eqBlockW: CGFloat = (theme.eqStyle == .bars) ? 24.0 : 8.0
            let eqStartX: CGFloat = (eqPos == .left)
                ? (pad + leftEdgeReserved)
                : (bounds.width - pad - rightEdgeReserved - eqBlockW)

            let dotScale: CGFloat = isPlaying ? (1.0 + smoothedVocalEnergy * 0.35) : 1.0
            let dotSize = 5.0 * dotScale
            syncDotLayer.frame = CGRect(x: eqStartX + (5.0 - dotSize) * 0.5, y: (h - dotSize) / 2.0 + 0.5, width: dotSize, height: dotSize)
            syncDotLayer.cornerRadius = dotSize * 0.5
            syncDotLayer.backgroundColor = isVocalSynced
                ? currentAccentColor.cgColor
                : mutedColor.withAlphaComponent(0.55).cgColor

            if theme.eqStyle == .bars {
                let barMultipliers: [CGFloat] = [0.65, 1.0, 0.82, 0.52]
                let phaseOffsets: [Double] = [0.0, 1.3, 2.5, 3.8]
                for (i, bar) in eqBars.enumerated() {
                    let wave = isPlaying && !reduceMotion
                        ? CGFloat(0.65 + 0.35 * sin(animPhase + phaseOffsets[i]))
                        : 1.0
                    let amp = isPlaying ? max(0.18, smoothedVocalEnergy * barMultipliers[i] * wave) : 0.14
                    let barH = 3.0 + amp * 11.0
                    let bx = eqStartX + 8.0 + CGFloat(i) * 3.5
                    bar.frame = CGRect(x: bx, y: (h - barH) / 2.0 + 0.5, width: 2.0, height: barH)
                    bar.backgroundColor = (isVocalSynced ? currentAccentColor : mutedColor)
                        .withAlphaComponent(isPlaying ? (0.45 + amp * 0.55) : 0.30).cgColor
                }
            }
        }

        progressFillLayer.backgroundColor = currentAccentColor.cgColor
        progressFillLayer.frame = CGRect(
            x: 0,
            y: 0,
            width: progressTrackLayer.bounds.width * self.songProgress,
            height: 1.5
        )
        CATransaction.commit()
    }

    private func applyLineTransition(duration: TimeInterval) {
        guard let layer = mainLyricLabel.layer else { return }
        layer.removeAllAnimations()
        let timing = CAMediaTimingFunction(controlPoints: 0.2, 0.0, 0.0, 1.0)

        switch theme.lineTransition {
        case .none:
            return
        case .pushUp:
            let tr = CATransition()
            tr.type = .push
            tr.subtype = .fromTop
            tr.duration = duration
            tr.timingFunction = timing
            layer.add(tr, forKey: "mainLyricArrive")
        case .pushDown:
            let tr = CATransition()
            tr.type = .push
            tr.subtype = .fromBottom
            tr.duration = duration
            tr.timingFunction = timing
            layer.add(tr, forKey: "mainLyricArrive")
        case .slideLeft:
            let tr = CATransition()
            tr.type = .push
            tr.subtype = .fromRight
            tr.duration = duration
            tr.timingFunction = timing
            layer.add(tr, forKey: "mainLyricArrive")
        case .crossfade:
            let tr = CATransition()
            tr.type = .fade
            tr.duration = duration
            tr.timingFunction = timing
            layer.add(tr, forKey: "mainLyricArrive")
        case .zoomSoft:
            let group = CAAnimationGroup()
            group.duration = duration
            group.timingFunction = timing
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.92
            scale.toValue = 1.0
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.2
            fade.toValue = 1.0
            group.animations = [scale, fade]
            layer.add(group, forKey: "mainLyricArrive")
        }
    }

    private func animateBackingEntrance(duration: TimeInterval) {
        guard let layer = backingLyricLabel.layer else { return }
        layer.removeAnimation(forKey: "backingStaggerIn")

        let group = CAAnimationGroup()
        group.duration = duration
        group.beginTime = CACurrentMediaTime() + 0.045
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.0, 0.0, 1.0)
        group.fillMode = .backwards

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.0
        fade.toValue = 1.0

        let slide = CABasicAnimation(keyPath: "transform.translation.y")
        slide.fromValue = -4.0
        slide.toValue = 0.0

        group.animations = [fade, slide]
        layer.add(group, forKey: "backingStaggerIn")
    }

    private func buildPerCharacterAttributedString(
        text: String,
        fontSize: CGFloat,
        baseWeight: NSFont.Weight,
        highlightWeight: NSFont.Weight,
        progress: CGFloat,
        introReveal: CGFloat,
        vocalBoost: CGFloat,
        sungColor: NSColor,
        activeColor: NSColor,
        upcomingColor: NSColor,
        alignment: NSTextAlignment
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let chars = Array(text)
        let total = max(1, chars.count)
        let cursor = progress * CGFloat(total)

        let normalFont = theme.fontStyle.font(size: fontSize, weight: baseWeight)
        let boldFont = theme.fontStyle.font(size: fontSize, weight: highlightWeight)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail

        let wordMode = characterAnimationEnabled ? theme.wordAnimation : .solid

        for (i, ch) in chars.enumerated() {
            let idx = CGFloat(i)
            let dist = idx - cursor

            let charDelay = (idx / CGFloat(total)) * 0.42
            let charAlphaFactor = min(1.0, max(0.25, (introReveal - charDelay) / 0.58))

            let color: NSColor
            let font: NSFont
            var baselineOffset: CGFloat = 0

            switch wordMode {
            case .solid:
                color = sungColor
                font = normalFont

            case .typewriter:
                let revealLimit = min(1.0, max(0.08, introReveal * 1.15)) * CGFloat(total)
                let vis = idx <= revealLimit ? 1.0 : max(0.08, 1.0 - (idx - revealLimit) * 0.45)
                if dist <= 0.6 {
                    color = sungColor.blended(with: activeColor, fraction: 0.35).withAlphaComponent(vis)
                    font = dist > -1.0 ? boldFont : normalFont
                } else {
                    color = upcomingColor.withAlphaComponent(upcomingColor.alphaComponent * vis)
                    font = normalFont
                }

            case .smoothWipe:
                if dist < -0.5 {
                    color = sungColor.withAlphaComponent(charAlphaFactor)
                    font = normalFont
                } else if dist <= 0.6 {
                    let frac = max(0, 1.0 - abs(dist) / 0.8)
                    color = upcomingColor.blended(with: activeColor, fraction: frac).withAlphaComponent(max(0.7, charAlphaFactor))
                    font = normalFont
                } else {
                    color = upcomingColor.withAlphaComponent(upcomingColor.alphaComponent * charAlphaFactor)
                    font = normalFont
                }

            case .glowPulse:
                if dist < -1.0 {
                    color = sungColor.blended(with: activeColor, fraction: 0.28 + vocalBoost * 0.16)
                    font = normalFont
                } else if dist <= 1.2 {
                    let intensity = max(0, 1.0 - abs(dist) / 1.3)
                    color = sungColor.blended(with: activeColor, fraction: min(1.0, 0.55 + intensity * 0.45))
                    font = boldFont
                } else {
                    color = upcomingColor
                    font = normalFont
                }

            case .karaokeLift:
                if !isPlayingState && progress >= 0.99 {
                    color = sungColor
                    font = normalFont
                } else if dist < -1.2 {
                    let sungTint = sungColor.blended(with: activeColor, fraction: 0.18 + vocalBoost * 0.14)
                    color = sungTint.withAlphaComponent(charAlphaFactor)
                    font = normalFont
                } else if dist <= 0.95 {
                    let intensity = max(0, 1.0 - abs(dist + 0.1) / 1.15)
                    let c = sungColor.blended(with: activeColor, fraction: min(1, max(0.45, intensity)))
                    color = c.withAlphaComponent(max(0.80, charAlphaFactor))
                    font = intensity > 0.30 ? boldFont : normalFont
                    baselineOffset = intensity * (0.85 + vocalBoost * 0.45)
                } else {
                    let edgeBlend = max(0, 1.0 - (dist - 0.95) / 2.2)
                    let c = upcomingColor.blended(with: activeColor, fraction: edgeBlend * 0.50)
                    color = c.withAlphaComponent(c.alphaComponent * charAlphaFactor)
                    font = normalFont
                    baselineOffset = edgeBlend * 0.25
                }
            }

            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .baselineOffset: baselineOffset,
                .paragraphStyle: paragraph
            ]
            result.append(NSAttributedString(string: String(ch), attributes: attrs))
        }

        return result
    }
}
