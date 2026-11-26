import Cocoa
import QuartzCore

final class TouchBarLyricsView: NSView {
    private let bgLayer = CALayer()
    private let progressTrackLayer = CALayer()
    private let progressFillLayer = CALayer()
    private let progressGlowBead = CALayer()
    private let syncDotLayer = CALayer()
    private var eqBars: [CALayer] = []

    private let trackLabel = NSTextField(labelWithString: "")
    private let lyricContainer = NSView()
    private let outgoingMainLayer = CALayer()
    private let outgoingBackingLayer = CALayer()
    private let mainLyricLabel = NSTextField(labelWithString: "Putar lagu di Safari")
    private let backingLyricLabel = NSTextField(labelWithString: "")
    private var mainTransitionToken: Int = 0
    private var backingTransitionToken: Int = 0
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
    private var smoothedIntonation: CGFloat = 0.45
    private var smoothedOnset: CGFloat = 0.0
    private var animPhase: Double = 0

    private var lastRenderedQuantizedStep: Int = -1
    private var lastRenderedMain: String = ""
    private var lastRenderedBacking: String = ""
    private var lastRenderedAccentHex: String = ""

    var renderedBackgroundColor: NSColor? {
        bgLayer.backgroundColor.flatMap { NSColor(cgColor: $0) }
    }

    var renderedMainTextColor: NSColor? {
        guard mainLyricLabel.attributedStringValue.length > 0 else { return nil }
        return mainLyricLabel.attributedStringValue.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
    }

    var renderedMainAttributedString: NSAttributedString {
        mainLyricLabel.attributedStringValue
    }

    var characterAnimationEnabled: Bool = true {
        didSet {
            lastRenderedQuantizedStep = -1
        }
    }

    /// Enables multi-line word wrapping + dynamic font auto-fit (used in Notch so lyrics never truncate).
    var allowsMultiline: Bool = false {
        didSet {
            configureLineWrapping()
            lastRenderedQuantizedStep = -1
            needsLayout = true
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

        progressGlowBead.cornerRadius = 2.0
        progressTrackLayer.addSublayer(progressGlowBead)

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

        outgoingMainLayer.opacity = 0
        outgoingMainLayer.isHidden = true
        outgoingMainLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        outgoingBackingLayer.opacity = 0
        outgoingBackingLayer.isHidden = true
        outgoingBackingLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        lyricContainer.layer?.addSublayer(outgoingMainLayer)
        lyricContainer.layer?.addSublayer(outgoingBackingLayer)

        mainLyricLabel.wantsLayer = true
        mainLyricLabel.alignment = .center
        lyricContainer.addSubview(mainLyricLabel)

        backingLyricLabel.wantsLayer = true
        backingLyricLabel.alignment = .center
        backingLyricLabel.isHidden = true
        lyricContainer.addSubview(backingLyricLabel)

        configureLineWrapping()

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

    private func configureLineWrapping() {
        mainLyricLabel.usesSingleLineMode = !allowsMultiline
        mainLyricLabel.lineBreakMode = allowsMultiline ? .byWordWrapping : .byTruncatingTail
        mainLyricLabel.maximumNumberOfLines = allowsMultiline ? 3 : 1
        if let cell = mainLyricLabel.cell as? NSTextFieldCell {
            cell.wraps = allowsMultiline
            cell.isScrollable = false
        }

        backingLyricLabel.usesSingleLineMode = !allowsMultiline
        backingLyricLabel.lineBreakMode = allowsMultiline ? .byWordWrapping : .byTruncatingTail
        backingLyricLabel.maximumNumberOfLines = allowsMultiline ? 2 : 1
        if let cell = backingLyricLabel.cell as? NSTextFieldCell {
            cell.wraps = allowsMultiline
            cell.isScrollable = false
        }
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
        progressGlowBead.isHidden = (effectiveProgPos == .hidden)
        progressGlowBead.backgroundColor = accentColor.cgColor

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
        let containerH = max(20.0, h - 5.0)
        lyricContainer.frame = NSRect(x: leftCursor, y: containerY, width: lyricW, height: containerH)

        let hasMain = !mainLyricLabel.isHidden
        let hasBack = !backingLyricLabel.isHidden

        if allowsMultiline {
            mainLyricLabel.preferredMaxLayoutWidth = lyricW
            backingLyricLabel.preferredMaxLayoutWidth = (hasMain && hasBack && theme.backingPlacement == .inlineBeside)
                ? max(40, lyricW * 0.36 - 6)
                : lyricW

            if hasMain && hasBack {
                switch theme.backingPlacement {
                case .below:
                    let maxBackH = min(containerH * 0.42, max(12, backingLyricLabel.sizeThatFits(NSSize(width: lyricW, height: containerH)).height))
                    let maxMainH = max(14, containerH - maxBackH - 2)
                    let usedMainH = min(maxMainH, max(14, mainLyricLabel.sizeThatFits(NSSize(width: lyricW, height: maxMainH)).height))
                    let totalH = usedMainH + 2 + maxBackH
                    let startY = max(0, (containerH - totalH) / 2.0)
                    backingLyricLabel.frame = NSRect(x: 0, y: startY, width: lyricW, height: maxBackH)
                    mainLyricLabel.frame = NSRect(x: 0, y: startY + maxBackH + 2, width: lyricW, height: usedMainH)
                case .above:
                    let maxBackH = min(containerH * 0.42, max(12, backingLyricLabel.sizeThatFits(NSSize(width: lyricW, height: containerH)).height))
                    let maxMainH = max(14, containerH - maxBackH - 2)
                    let usedMainH = min(maxMainH, max(14, mainLyricLabel.sizeThatFits(NSSize(width: lyricW, height: maxMainH)).height))
                    let totalH = usedMainH + 2 + maxBackH
                    let startY = max(0, (containerH - totalH) / 2.0)
                    mainLyricLabel.frame = NSRect(x: 0, y: startY, width: lyricW, height: usedMainH)
                    backingLyricLabel.frame = NSRect(x: 0, y: startY + usedMainH + 2, width: lyricW, height: maxBackH)
                case .inlineBeside:
                    let mainW = lyricW * 0.64
                    let backW = max(40, lyricW - mainW - 6)
                    let mH = min(containerH, max(16, mainLyricLabel.sizeThatFits(NSSize(width: mainW, height: containerH)).height))
                    let bH = min(containerH, max(14, backingLyricLabel.sizeThatFits(NSSize(width: backW, height: containerH)).height))
                    mainLyricLabel.frame = NSRect(x: 0, y: max(0, (containerH - mH) / 2.0), width: mainW, height: mH)
                    backingLyricLabel.frame = NSRect(x: mainW + 6, y: max(0, (containerH - bH) / 2.0), width: backW, height: bH)
                }
            } else if hasBack {
                let bH = min(containerH, max(14, backingLyricLabel.sizeThatFits(NSSize(width: lyricW, height: containerH)).height))
                backingLyricLabel.frame = NSRect(x: 0, y: max(0, (containerH - bH) / 2.0), width: lyricW, height: bH)
            } else {
                let mH = min(containerH, max(16, mainLyricLabel.sizeThatFits(NSSize(width: lyricW, height: containerH)).height))
                mainLyricLabel.frame = NSRect(x: 0, y: max(0, (containerH - mH) / 2.0), width: lyricW, height: mH)
            }
        } else if hasMain && hasBack {
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
        vocalIntonation: CGFloat = 0.45,
        vocalOnset: CGFloat = 0.0,
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
        let targetIntonation: CGFloat = isPlaying ? min(1.0, max(0.0, vocalIntonation)) : 0.35
        let targetOnset: CGFloat = isPlaying ? min(1.0, max(0.0, vocalOnset)) : 0.0
        smoothedVocalEnergy = smoothedVocalEnergy * 0.70 + targetEnergy * 0.30
        smoothedBackingEnergy = smoothedBackingEnergy * 0.68 + targetBgEnergy * 0.32
        smoothedIntonation = smoothedIntonation * 0.72 + targetIntonation * 0.28
        smoothedOnset = max(targetOnset, smoothedOnset * 0.80)
        if isPlaying {
            animPhase += (0.22 + Double(smoothedIntonation) * 0.10) * Double(speed)
        }

        // 1. Dynamic Song-Matched Color Resolution obeying ColorSyncMode
        let baseBg = NSColor(hex: theme.backgroundHex)
        let themeAccent = NSColor(hex: theme.accentHex)
        let themeBacking = NSColor(hex: theme.backingTextHex)

        let effectivePalette: SongColorPalette? = (theme.colorSyncMode == .themeOnly) ? nil : (songPalette ?? activeSongPalette)
        let isDarkOledBg = baseBg.relativeLuminance < 0.08
        let targetBg: NSColor
        let targetAccent: NSColor
        let targetBacking: NSColor
        if let pal = effectivePalette {
            // Keep black / OLED dark backgrounds strictly pure without artwork surface tint;
            // apply adaptive artwork colors strictly to text, backing vocals, accent, and EQ.
            if isDarkOledBg {
                targetBg = baseBg
            } else {
                let tintStrength: CGFloat = (theme.colorSyncMode == .vividArtwork) ? 0.09 : 0.05
                let liveTint = tintStrength + smoothedVocalEnergy * (theme.colorSyncMode == .vividArtwork ? 0.09 : 0.05)
                targetBg = baseBg.blended(with: pal.surfaceTint, fraction: liveTint)
            }
            targetAccent = pal.accent.ensuringContrast(against: targetBg, minRatio: 4.5)
            targetBacking = pal.backingAccent.ensuringContrast(against: targetBg, minRatio: 4.5)
        } else {
            if isDarkOledBg {
                targetBg = baseBg
            } else {
                let liveTint = smoothedVocalEnergy * 0.025
                targetBg = baseBg.blended(with: themeAccent, fraction: liveTint)
            }
            targetAccent = themeAccent.ensuringContrast(against: targetBg, minRatio: 4.5)
            targetBacking = themeBacking.ensuringContrast(against: targetBg, minRatio: 4.5)
        }

        currentBgColor = isDarkOledBg ? baseBg : currentBgColor.blended(with: targetBg, fraction: 0.16)
        currentAccentColor = currentAccentColor.blended(with: targetAccent, fraction: 0.16)
        currentBackingColor = currentBackingColor.blended(with: targetBacking, fraction: 0.16)

        let rawMainColor = NSColor(hex: theme.mainTextHex)
        let mainTextMix: CGFloat = (theme.colorSyncMode == .vividArtwork) ? 0.65 : 0.38
        let tintedMainColor = (effectivePalette != nil)
            ? rawMainColor.blended(with: currentAccentColor, fraction: mainTextMix)
            : rawMainColor
        let effectiveMainColor = tintedMainColor.ensuringContrast(against: currentBgColor, minRatio: 4.5)
        let baseUpcoming = theme.upcomingTextHex.isEmpty
            ? effectiveMainColor.withAlphaComponent(0.50)
            : NSColor(hex: theme.upcomingTextHex).ensuringContrast(against: currentBgColor, minRatio: 3.0)
        let borderColor = NSColor(hex: theme.borderHex)
        let rawMutedColor = NSColor(hex: theme.trackTextHex)
        let tintedMutedColor = (effectivePalette != nil)
            ? rawMutedColor.blended(with: currentAccentColor, fraction: mainTextMix * 0.65)
            : rawMutedColor
        let mutedColor = tintedMutedColor.ensuringContrast(against: currentBgColor, minRatio: 4.5)

        // 2. Decoupled Entrance Choreography for Main Vocal vs Backing Vocal
        let cleanBacking = backingText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let formattedBacking = cleanBacking.isEmpty ? "" : "\(theme.backingTag) \(cleanBacking)"
        let mainChanged = (mainText != currentMainSignature)
        let backingChanged = (formattedBacking != currentBackingSignature)

        let now = Date()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if mainChanged {
            let isRapidBurst = now.timeIntervalSince(lineAppearDate) < 0.70 || mainText.count >= 44
            let animDur = (isRapidBurst ? 0.11 : 0.19) / Double(speed)
            let hadVisibleOldMain = !mainLyricLabel.isHidden && !currentMainSignature.isEmpty && !mainText.isEmpty
            if hadVisibleOldMain && !reduceMotion && theme.lineTransition != .none {
                prepareOutgoingGhost(from: mainLyricLabel, onto: outgoingMainLayer, token: &mainTransitionToken, duration: animDur, style: theme.lineTransition)
            } else {
                hideGhostLayer(outgoingMainLayer)
            }

            currentMainSignature = mainText
            lineAppearDate = now

            mainLyricLabel.isHidden = mainText.isEmpty
            if !reduceMotion {
                applyLineTransition(duration: animDur)
            }
            needsLayout = true
            lastRenderedQuantizedStep = -1
        }

        if backingChanged {
            let isRapidBacking = now.timeIntervalSince(backingAppearDate) < 0.70
            let bgAnimDur = (isRapidBacking ? 0.11 : 0.18) / Double(speed)
            let hadVisibleOldBacking = !backingLyricLabel.isHidden && !currentBackingSignature.isEmpty
            if hadVisibleOldBacking && !reduceMotion && theme.lineTransition != .none {
                prepareOutgoingGhost(from: backingLyricLabel, onto: outgoingBackingLayer, token: &backingTransitionToken, duration: bgAnimDur, style: theme.lineTransition)
            } else {
                hideGhostLayer(outgoingBackingLayer)
            }

            currentBackingSignature = formattedBacking
            backingAppearDate = now

            if !formattedBacking.isEmpty {
                backingLyricLabel.isHidden = false
                if !reduceMotion && theme.lineTransition != .none {
                    animateBackingEntrance(duration: bgAnimDur)
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
        let revealSpan = 0.12 / Double(speed)
        let mainReveal: CGFloat = animActive ? min(1.0, CGFloat(max(0.0, now.timeIntervalSince(lineAppearDate) / revealSpan))) : 1.0
        let backReveal: CGFloat = animActive ? min(1.0, CGFloat(max(0.0, now.timeIntervalSince(backingAppearDate) / revealSpan))) : 1.0

        let qMain = Int((clampedMainProg * 360.0).rounded())
            + Int((mainReveal * 24.0).rounded()) * 1000
            + Int((smoothedIntonation * 12.0).rounded()) * 40_000
            + Int((smoothedOnset * 10.0).rounded()) * 600_000
        let qBack = Int((clampedBackProg * 220.0).rounded()) + Int((backReveal * 20.0).rounded()) * 100
        let quantized = qMain &+ qBack * 10_000_000
        let accentSignature = "\(currentAccentColor.hexString)|\(currentBackingColor.hexString)|\(theme.wordAnimation.rawValue)|\(theme.textAlignment.rawValue)|\(Int(theme.mainFontSize * 10))|\(Int(bounds.width.rounded()))|\(Int(bounds.height.rounded()))"

        if mainChanged || backingChanged || quantized != lastRenderedQuantizedStep || mainText != lastRenderedMain || formattedBacking != lastRenderedBacking || accentSignature != lastRenderedAccentHex {
            lastRenderedQuantizedStep = quantized
            lastRenderedMain = mainText
            lastRenderedBacking = formattedBacking
            lastRenderedAccentHex = accentSignature

            let hasBoth = !mainText.isEmpty && !formattedBacking.isEmpty && theme.backingPlacement != .inlineBeside
            var mainFontSize = hasBoth ? min(theme.mainFontSize, 12.0) : theme.mainFontSize
            var backFontSize = hasBoth ? theme.backingFontSize : max(theme.backingFontSize, 11.0)
            let availW = max(120, (lyricContainer.bounds.width > 20 ? lyricContainer.bounds.width : bounds.width - theme.horizontalPadding * 2))
            let availH = max(24, (lyricContainer.bounds.height > 16 ? lyricContainer.bounds.height : bounds.height - 5.0))

            if allowsMultiline {
                let maxMainH = hasBoth ? availH * 0.62 : availH
                let maxBackH = hasBoth ? availH * 0.36 : availH
                let mainBoxW = (!mainText.isEmpty && !formattedBacking.isEmpty && theme.backingPlacement == .inlineBeside) ? availW * 0.64 : availW
                let backBoxW = (!mainText.isEmpty && !formattedBacking.isEmpty && theme.backingPlacement == .inlineBeside) ? max(40, availW * 0.36 - 6) : availW
                mainFontSize = Self.fittedFontSize(
                    text: mainText,
                    targetSize: mainFontSize,
                    minSize: 9.5,
                    weight: .bold,
                    fontStyle: theme.fontStyle,
                    maxWidth: mainBoxW,
                    maxHeight: maxMainH
                )
                if !formattedBacking.isEmpty {
                    backFontSize = Self.fittedFontSize(
                        text: formattedBacking,
                        targetSize: backFontSize,
                        minSize: 8.5,
                        weight: .semibold,
                        fontStyle: theme.fontStyle,
                        maxWidth: backBoxW,
                        maxHeight: maxBackH
                    )
                }
            }
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
                    intonation: smoothedIntonation,
                    onset: smoothedOnset,
                    sungColor: effectiveMainColor,
                    activeColor: currentAccentColor,
                    upcomingColor: baseUpcoming,
                    alignment: align,
                    compactBounce: hasBoth
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
                    intonation: smoothedIntonation * 0.7,
                    onset: smoothedOnset * 0.6,
                    sungColor: currentBackingColor,
                    activeColor: effectiveMainColor,
                    upcomingColor: currentBackingColor.withAlphaComponent(0.55),
                    alignment: backingLyricLabel.alignment,
                    compactBounce: true
                )
            } else {
                backingLyricLabel.stringValue = ""
            }
            if allowsMultiline {
                needsLayout = true
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
        let fillW = progressTrackLayer.bounds.width * self.songProgress
        progressFillLayer.frame = CGRect(
            x: 0,
            y: 0,
            width: fillW,
            height: 1.5
        )
        let beadSize: CGFloat = isPlaying ? (3.2 + smoothedVocalEnergy * 1.4 + smoothedOnset * 1.0) : 2.5
        progressGlowBead.frame = CGRect(
            x: max(0, fillW - beadSize * 0.5),
            y: (1.5 - beadSize) * 0.5,
            width: beadSize,
            height: beadSize
        )
        progressGlowBead.cornerRadius = beadSize * 0.5
        progressGlowBead.backgroundColor = effectiveMainColor.blended(with: currentAccentColor, fraction: 0.65).cgColor
        progressGlowBead.opacity = (self.songProgress > 0.002 && effectiveProgressPosition() != .hidden) ? 1.0 : 0.0
        CATransaction.commit()
    }

    private func hideGhostLayer(_ ghostLayer: CALayer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ghostLayer.removeAllAnimations()
        ghostLayer.contents = nil
        ghostLayer.opacity = 0
        ghostLayer.isHidden = true
        CATransaction.commit()
    }

    private func prepareOutgoingGhost(
        from view: NSView,
        onto ghostLayer: CALayer,
        token: inout Int,
        duration: TimeInterval,
        style: ThemeLineTransition
    ) {
        let bounds = view.bounds
        guard bounds.width > 4, bounds.height > 4,
              let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            return
        }
        view.cacheDisplay(in: bounds, to: rep)
        guard let cgImg = rep.cgImage else { return }

        token += 1
        let myToken = token
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ghostLayer.removeAllAnimations()
        ghostLayer.contents = cgImg
        ghostLayer.contentsScale = scale
        ghostLayer.frame = view.frame
        ghostLayer.opacity = 1.0
        ghostLayer.transform = CATransform3DIdentity
        ghostLayer.isHidden = false
        CATransaction.commit()

        let timing = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
        let group = CAAnimationGroup()
        group.duration = duration
        group.timingFunction = timing
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.0

        var anims: [CAAnimation] = [fade]
        switch style {
        case .none:
            hideGhostLayer(ghostLayer)
            return
        case .pushUp:
            let move = CABasicAnimation(keyPath: "transform.translation.y")
            move.fromValue = 0.0
            move.toValue = 9.0
            let sc = CABasicAnimation(keyPath: "transform.scale")
            sc.fromValue = 1.0
            sc.toValue = 0.96
            anims.append(contentsOf: [move, sc])
        case .pushDown:
            let move = CABasicAnimation(keyPath: "transform.translation.y")
            move.fromValue = 0.0
            move.toValue = -9.0
            let sc = CABasicAnimation(keyPath: "transform.scale")
            sc.fromValue = 1.0
            sc.toValue = 0.96
            anims.append(contentsOf: [move, sc])
        case .slideLeft:
            let move = CABasicAnimation(keyPath: "transform.translation.x")
            move.fromValue = 0.0
            move.toValue = -18.0
            anims.append(move)
        case .crossfade:
            let sc = CABasicAnimation(keyPath: "transform.scale")
            sc.fromValue = 1.0
            sc.toValue = 0.975
            anims.append(sc)
        case .zoomSoft:
            let sc = CABasicAnimation(keyPath: "transform.scale")
            sc.fromValue = 1.0
            sc.toValue = 1.04
            anims.append(sc)
        }

        group.animations = anims
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak ghostLayer] in
            guard let self = self, let ghostLayer = ghostLayer else { return }
            let activeTok = (ghostLayer === self.outgoingMainLayer) ? self.mainTransitionToken : self.backingTransitionToken
            if activeTok == myToken {
                self.hideGhostLayer(ghostLayer)
            }
        }
        ghostLayer.add(group, forKey: "ghostExit")
        CATransaction.commit()
    }

    private func applyLineTransition(duration: TimeInterval) {
        guard let layer = mainLyricLabel.layer else { return }
        layer.removeAnimation(forKey: "mainLyricArrive")
        let timing = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)

        let group = CAAnimationGroup()
        group.duration = duration
        group.timingFunction = timing
        group.fillMode = .backwards

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.0
        fade.toValue = 1.0
        var anims: [CAAnimation] = [fade]

        switch theme.lineTransition {
        case .none:
            return
        case .pushUp:
            let slide = CABasicAnimation(keyPath: "transform.translation.y")
            slide.fromValue = -10.0
            slide.toValue = 0.0
            let sc = CABasicAnimation(keyPath: "transform.scale")
            sc.fromValue = 0.97
            sc.toValue = 1.0
            anims.append(contentsOf: [slide, sc])
        case .pushDown:
            let slide = CABasicAnimation(keyPath: "transform.translation.y")
            slide.fromValue = 10.0
            slide.toValue = 0.0
            let sc = CABasicAnimation(keyPath: "transform.scale")
            sc.fromValue = 0.97
            sc.toValue = 1.0
            anims.append(contentsOf: [slide, sc])
        case .slideLeft:
            let slide = CABasicAnimation(keyPath: "transform.translation.x")
            slide.fromValue = 18.0
            slide.toValue = 0.0
            anims.append(slide)
        case .crossfade:
            let sc = CABasicAnimation(keyPath: "transform.scale")
            sc.fromValue = 1.018
            sc.toValue = 1.0
            anims.append(sc)
        case .zoomSoft:
            let sc = CABasicAnimation(keyPath: "transform.scale")
            sc.fromValue = 0.93
            sc.toValue = 1.0
            anims.append(sc)
        }

        group.animations = anims
        layer.add(group, forKey: "mainLyricArrive")
    }

    private func animateBackingEntrance(duration: TimeInterval) {
        guard let layer = backingLyricLabel.layer else { return }
        layer.removeAnimation(forKey: "backingStaggerIn")

        let group = CAAnimationGroup()
        group.duration = duration
        group.beginTime = CACurrentMediaTime() + 0.025
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
        group.fillMode = .backwards

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.0
        fade.toValue = 1.0

        let slide = CABasicAnimation(keyPath: "transform.translation.y")
        slide.fromValue = -6.0
        slide.toValue = 0.0

        group.animations = [fade, slide]
        layer.add(group, forKey: "backingStaggerIn")
    }

    private static func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
        let denom = max(0.0001, edge1 - edge0)
        let t = min(1.0, max(0.0, (x - edge0) / denom))
        return t * t * (3.0 - 2.0 * t)
    }

    private static func splitClusterSafeTokens(_ text: String) -> [String] {
        var tokens: [String] = []
        var buf = ""
        for ch in text {
            buf.append(ch)
            if ch == " " {
                tokens.append(buf)
                buf = ""
            }
        }
        if !buf.isEmpty { tokens.append(buf) }
        return tokens
    }

    private func buildPerCharacterAttributedString(
        text: String,
        fontSize: CGFloat,
        baseWeight: NSFont.Weight,
        highlightWeight: NSFont.Weight,
        progress: CGFloat,
        introReveal: CGFloat,
        vocalBoost: CGFloat,
        intonation: CGFloat,
        onset: CGFloat,
        sungColor: NSColor,
        activeColor: NSColor,
        upcomingColor: NSColor,
        alignment: NSTextAlignment,
        compactBounce: Bool = false
    ) -> NSAttributedString {
        let bounceScale: CGFloat = compactBounce ? 0.55 : 1.0
        let result = NSMutableAttributedString()
        let baseFont = theme.fontStyle.font(size: fontSize, weight: baseWeight)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = allowsMultiline ? .byWordWrapping : .byTruncatingTail
        if allowsMultiline {
            paragraph.lineSpacing = 1.0
        }
        if TextRomanizer.isRTLScript(text) {
            paragraph.baseWritingDirection = .rightToLeft
        }

        let wordMode = characterAnimationEnabled ? theme.wordAnimation : .solid

        // Complex scripts (Arabic, Hebrew, Hindi/Indic, Thai) require intact ligature runs:
        // animate smoothly at word-cluster boundaries with uniform font & zero baseline breaks.
        if TextRomanizer.requiresClusterGrouping(text) {
            let tokens = Self.splitClusterSafeTokens(text)
            let totalChars = max(1, text.count)
            let cursor = progress * CGFloat(totalChars)
            var charOffset = 0
            for tok in tokens {
                let len = max(1, tok.count)
                let mid = CGFloat(charOffset) + CGFloat(len) * 0.5
                let dist = mid - cursor
                let revealAlpha = wordMode == .solid ? 1.0 : min(1.0, max(0.65, introReveal))
                let color: NSColor
                if wordMode == .solid || (!isPlayingState && progress >= 0.99) {
                    color = sungColor
                } else if dist < -1.5 {
                    let decay = Self.smoothstep(-5.0, -1.5, dist)
                    let frac = (0.16 + vocalBoost * 0.14 + intonation * 0.12) * (0.4 + decay * 0.6)
                    color = sungColor.blended(with: activeColor, fraction: frac).withAlphaComponent(revealAlpha)
                } else if dist <= 0.8 {
                    let focus = 1.0 - Self.smoothstep(0.0, 2.2, abs(dist))
                    let frac = min(1.0, 0.52 + focus * 0.48 + onset * 0.15)
                    color = sungColor.blended(with: activeColor, fraction: frac).withAlphaComponent(revealAlpha)
                } else {
                    let edge = 1.0 - Self.smoothstep(0.8, 5.5, dist)
                    color = upcomingColor.blended(with: activeColor, fraction: edge * 0.68).withAlphaComponent(max(upcomingColor.alphaComponent, edge) * revealAlpha)
                }
                result.append(NSAttributedString(string: tok, attributes: [
                    .font: baseFont,
                    .foregroundColor: color,
                    .paragraphStyle: paragraph
                ]))
                charOffset += tok.count
            }
            return result
        }

        let chars = Array(text)
        let total = max(1, chars.count)
        let cursor = progress * CGFloat(total)

        for (i, ch) in chars.enumerated() {
            let idx = CGFloat(i)
            let dist = idx - cursor

            let charDelay = (idx / CGFloat(total)) * 0.22
            let revealT = Self.smoothstep(charDelay, charDelay + 0.55, introReveal)
            let charAlphaFactor = 0.62 + revealT * 0.38

            let color: NSColor
            var baselineOffset: CGFloat = 0

            switch wordMode {
            case .solid:
                color = sungColor

            case .typewriter:
                let revealLimit = min(1.0, max(0.12, introReveal * 1.15)) * CGFloat(total)
                let vis = idx <= revealLimit ? 1.0 : max(0.14, 1.0 - (idx - revealLimit) * 0.38)
                if dist <= 0.8 {
                    let intensity = 1.0 - Self.smoothstep(0.0, 2.2, abs(dist))
                    let pulse = min(1.0, 0.24 + intensity * (0.46 + intonation * 0.22 + onset * 0.15))
                    color = sungColor.blended(with: activeColor, fraction: pulse).withAlphaComponent(vis)
                    baselineOffset = intensity * (0.30 + onset * 0.35)
                } else {
                    color = upcomingColor.withAlphaComponent(upcomingColor.alphaComponent * vis)
                }

            case .smoothWipe:
                if dist < -1.0 {
                    let tailGlow = Self.smoothstep(-4.0, -1.0, dist) * (0.20 + intonation * 0.18)
                    color = sungColor.blended(with: activeColor, fraction: tailGlow).withAlphaComponent(charAlphaFactor)
                } else if dist <= 1.2 {
                    let frac = 1.0 - Self.smoothstep(0.0, 1.4, abs(dist))
                    let mix = min(1.0, frac * (0.85 + vocalBoost * 0.15 + onset * 0.15))
                    color = upcomingColor.blended(with: activeColor, fraction: mix).withAlphaComponent(max(0.78, charAlphaFactor))
                } else {
                    let pre = (1.0 - Self.smoothstep(1.2, 3.2, dist)) * 0.38
                    color = upcomingColor.blended(with: activeColor, fraction: pre).withAlphaComponent(upcomingColor.alphaComponent * charAlphaFactor)
                }

            case .glowPulse:
                if dist < -1.2 {
                    let decay = Self.smoothstep(-4.2, -1.2, dist)
                    let tint = (0.24 + vocalBoost * 0.16 + intonation * 0.18) * (0.45 + 0.55 * decay)
                    color = sungColor.blended(with: activeColor, fraction: tint)
                } else if dist <= 1.6 {
                    let intensity = 1.0 - Self.smoothstep(0.0, 1.7, abs(dist))
                    let strength = min(1.0, 0.52 + intensity * (0.42 + onset * 0.20 + intonation * 0.14))
                    color = sungColor.blended(with: activeColor, fraction: strength)
                    baselineOffset = intensity * (0.40 + intonation * 0.45)
                } else {
                    let anticipate = (1.0 - Self.smoothstep(1.6, 3.5, dist)) * 0.36
                    color = upcomingColor.blended(with: activeColor, fraction: anticipate)
                }

            case .karaokeLift:
                if !isPlayingState && progress >= 0.99 {
                    color = sungColor
                } else if dist < -1.2 {
                    // Warm chromatic memory tail tapering gently back to sungColor
                    let tailFade = Self.smoothstep(-4.4, -1.2, dist)
                    let frac = (0.16 + vocalBoost * 0.12) + tailFade * (0.22 + intonation * 0.16)
                    color = sungColor.blended(with: activeColor, fraction: min(0.75, frac)).withAlphaComponent(charAlphaFactor)
                    baselineOffset = tailFade * (0.25 + intonation * 0.22)
                } else if dist <= 1.1 {
                    // Intonation-coupled syllable focal lift + onset impulse
                    let intensity = 1.0 - Self.smoothstep(0.0, 1.45, abs(dist + 0.05))
                    let c = sungColor.blended(with: activeColor, fraction: min(1.0, 0.42 + intensity * (0.50 + onset * 0.15)))
                    color = c.withAlphaComponent(max(0.86, charAlphaFactor))
                    baselineOffset = intensity * (0.70 + vocalBoost * 0.55 + intonation * 1.10 + onset * 0.65) * bounceScale
                } else {
                    // Anticipatory chromatic pre-glow for upcoming syllable readability
                    let edgeBlend = 1.0 - Self.smoothstep(1.1, 3.5, dist)
                    let c = upcomingColor.blended(with: activeColor, fraction: edgeBlend * (0.48 + intonation * 0.16))
                    color = c.withAlphaComponent(c.alphaComponent * charAlphaFactor)
                    baselineOffset = edgeBlend * (0.22 + intonation * 0.24) * bounceScale
                }
            }

            let attrs: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: color,
                .baselineOffset: baselineOffset,
                .paragraphStyle: paragraph
            ]
            result.append(NSAttributedString(string: String(ch), attributes: attrs))
        }

        return result
    }

    static func fittedFontSize(
        text: String,
        targetSize: CGFloat,
        minSize: CGFloat,
        weight: NSFont.Weight,
        fontStyle: ThemeFontStyle,
        maxWidth: CGFloat,
        maxHeight: CGFloat
    ) -> CGFloat {
        guard !text.isEmpty, maxWidth > 20, maxHeight > 12 else { return targetSize }
        var size = max(minSize, targetSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 1.0

        while size > minSize {
            let font = fontStyle.font(size: size, weight: weight)
            let rect = (text as NSString).boundingRect(
                with: NSSize(width: maxWidth, height: 400),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font, .paragraphStyle: paragraph]
            )
            if ceil(rect.height) <= maxHeight {
                return size
            }
            size -= 0.5
        }
        return minSize
    }
}
