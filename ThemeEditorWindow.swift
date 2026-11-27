import Cocoa

final class ThemeEditorWindowController: NSWindowController, NSWindowDelegate {
    private let themePopup = NSPopUpButton()
    private let languagePopup = NSPopUpButton()
    private let nameField = NSTextField()
    private let deleteButton = NSButton(title: L10n.tr("studio.deleteBtn"), target: nil, action: nil)
    private weak var mainTabView: NSTabView?

    // Layout & Typography Controls
    private let layoutModePopup = NSPopUpButton()
    private let trackPosPopup = NSPopUpButton()
    private let controlsPosPopup = NSPopUpButton()
    private let eqPosPopup = NSPopUpButton()
    private let eqStylePopup = NSPopUpButton()
    private let backingPlacementPopup = NSPopUpButton()
    private let textAlignPopup = NSPopUpButton()
    private let progressPosPopup = NSPopUpButton()
    private let fontPopup = NSPopUpButton()
    private let customFontPopup = NSPopUpButton()
    private let mainSizePopup = NSPopUpButton()
    private let backingSizePopup = NSPopUpButton()
    private let backingSpacingSlider = NSSlider(value: 1.0, minValue: -4.0, maxValue: 12.0, target: nil, action: nil)
    private let backingSpacingValueLabel = NSTextField(labelWithString: "1 px")
    private let paddingPopup = NSPopUpButton()
    private let radiusPopup = NSPopUpButton()
    private let tagPopup = NSPopUpButton()
    private let notchStylePopup = NSPopUpButton()
    private let showBorderCheck = NSButton(checkboxWithTitle: L10n.tr("studio.label.showBorder"), target: nil, action: nil)

    // Color Pickers & Hex Inputs
    private let bgWell = NSColorWell()
    private let borderWell = NSColorWell()
    private let mainWell = NSColorWell()
    private let backingWell = NSColorWell()
    private let upcomingWell = NSColorWell()
    private let accentWell = NSColorWell()
    private let trackWell = NSColorWell()
    private let colorSyncPopup = NSPopUpButton()

    var onRecalibrateSync: (() -> Void)?

    // Animation & Karaoke Tempo Controls
    private let lineTransPopup = NSPopUpButton()
    private let wordAnimPopup = NSPopUpButton()
    private let vocalSyncModePopup = NSPopUpButton()
    private let wordSpeedSlider = NSSlider(value: 1.0, minValue: 0.40, maxValue: 2.20, target: nil, action: nil)
    private let wordSpeedValueLabel = NSTextField(labelWithString: "1.00x")
    private let karaokeOffsetSlider = NSSlider(value: 0.0, minValue: -2.50, maxValue: 2.50, target: nil, action: nil)
    private let karaokeOffsetValueLabel = NSTextField(labelWithString: "0.00s")
    private let backingOffsetSlider = NSSlider(value: 0.0, minValue: -1.50, maxValue: 1.50, target: nil, action: nil)
    private let backingOffsetValueLabel = NSTextField(labelWithString: "0.00s")
    private let animSpeedSlider = NSSlider(value: 1.0, minValue: 0.50, maxValue: 2.00, target: nil, action: nil)
    private let animSpeedValueLabel = NSTextField(labelWithString: "1.00x")

    private let contrastLabel = NSTextField(labelWithString: "")
    private var previewView: TouchBarLyricsView!
    private var previewTimer: Timer?
    private var previewTick: Int = 0

    private var editingTheme: TouchBarTheme = ThemeStore.shared.activeTheme

    private let previewSamples: [(main: String, bg: String)] = [
        ("I just wanna be part of your symphony", "will you hold me tight"),
        ("When you hold me tight and never let go", "never let go, oh")
    ]

    init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 576, height: 636),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = L10n.tr("studio.windowTitle")
        win.center()
        win.isReleasedWhenClosed = false
        super.init(window: win)
        win.delegate = self
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onLanguageDidChange),
            name: L10n.didChangeNotification,
            object: nil
        )
        setupUI()
        reloadFromStore()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func cancelOperation(_ sender: Any?) {
        window?.close()
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        startPreviewAnimation()
    }

    func windowWillClose(_ notification: Notification) {
        stopPreviewAnimation()
    }

    private func startPreviewAnimation() {
        guard previewTimer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.stepPreview()
        }
        RunLoop.main.add(t, forMode: .common)
        previewTimer = t
    }

    private func stopPreviewAnimation() {
        previewTimer?.invalidate()
        previewTimer = nil
    }

    private func stepPreview() {
        previewTick = (previewTick + 1) % 160
        let sampleIdx = (previewTick < 80) ? 0 : 1
        let localTick = previewTick % 80
        let rawLineProg = Double(localTick) / 62.0
        let lineProg = CGFloat(min(1.0, rawLineProg * Double(editingTheme.wordSpeedScale)))
        let songProg = CGFloat(previewTick) / 160.0
        let vEnergy = CGFloat(0.45 + 0.40 * sin(Double(previewTick) * 0.25))

        let showBG = (lineProg >= 0.30)
        let bgProg = showBG ? CGFloat(min(1.0, (lineProg - 0.30) / 0.70)) : 0.0
        previewView.update(
            trackTitle: "Symphony",
            mainText: previewSamples[sampleIdx].main,
            backingText: showBG ? previewSamples[sampleIdx].bg : nil,
            songProgress: songProg,
            lineProgress: lineProg,
            backingLineProgress: bgProg,
            vocalEnergy: vEnergy,
            backingVocalEnergy: vEnergy * 0.9,
            isPlaying: true,
            isVocalSynced: true,
            songPalette: nil
        )
    }

    private func setupUI() {
        guard let content = window?.contentView else { return }
        content.subviews.forEach { $0.removeFromSuperview() }
        window?.title = L10n.tr("studio.windowTitle")
        deleteButton.title = L10n.tr("studio.deleteBtn")
        showBorderCheck.title = L10n.tr("studio.label.showBorder")

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 14, left: 18, bottom: 14, right: 18)
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)

        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])

        // 1. Live Touch Bar Preview Strip (Animated)
        previewView = TouchBarLyricsView {}
        previewView.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(previewView)
        NSLayoutConstraint.activate([
            previewView.widthAnchor.constraint(equalToConstant: 524),
            previewView.heightAnchor.constraint(equalToConstant: 32)
        ])
        stepPreview()

        // 2. Language Bar + Preset & Name Bar
        languagePopup.removeAllItems()
        for lang in AppLanguage.allCases {
            languagePopup.addItem(withTitle: lang.displayName)
        }
        if let lIdx = AppLanguage.allCases.firstIndex(of: L10n.currentLanguage) {
            languagePopup.selectItem(at: lIdx)
        }
        languagePopup.target = self
        languagePopup.action = #selector(onSelectLanguage)

        let langRow = NSStackView()
        langRow.orientation = .horizontal
        langRow.spacing = 8
        langRow.addArrangedSubview(NSTextField(labelWithString: L10n.tr("studio.languageLabel")))
        langRow.addArrangedSubview(languagePopup)
        root.addArrangedSubview(langRow)

        let topBar = NSStackView()
        topBar.orientation = .horizontal
        topBar.spacing = 8
        themePopup.target = self
        themePopup.action = #selector(onSelectTheme)
        nameField.placeholderString = L10n.tr("studio.themeNamePlaceholder")
        nameField.target = self
        nameField.action = #selector(onFieldEdited)
        let dupBtn = NSButton(title: L10n.tr("studio.duplicateBtn"), target: self, action: #selector(onDuplicateTheme))
        deleteButton.target = self
        deleteButton.action = #selector(onDeleteTheme)

        topBar.addArrangedSubview(NSTextField(labelWithString: L10n.tr("studio.themeLabel")))
        topBar.addArrangedSubview(themePopup)
        topBar.addArrangedSubview(nameField)
        nameField.widthAnchor.constraint(equalToConstant: 120).isActive = true
        topBar.addArrangedSubview(dupBtn)
        topBar.addArrangedSubview(deleteButton)
        root.addArrangedSubview(topBar)

        // 3. Clean 3-Tab Studio (Layout | Colors | Animation)
        let tabs = NSTabView()
        tabs.translatesAutoresizingMaskIntoConstraints = false
        self.mainTabView = tabs

        let layoutTab = NSTabViewItem(identifier: "layout")
        layoutTab.label = L10n.tr("studio.tab.layout")
        layoutTab.view = buildLayoutTab()

        let colorTab = NSTabViewItem(identifier: "colors")
        colorTab.label = L10n.tr("studio.tab.colors")
        colorTab.view = buildColorTab()

        let animTab = NSTabViewItem(identifier: "anim")
        animTab.label = L10n.tr("studio.tab.animation")
        animTab.view = buildAnimationTab()

        tabs.addTabViewItem(layoutTab)
        tabs.addTabViewItem(colorTab)
        tabs.addTabViewItem(animTab)
        root.addArrangedSubview(tabs)
        NSLayoutConstraint.activate([
            tabs.widthAnchor.constraint(equalToConstant: 540),
            tabs.heightAnchor.constraint(equalToConstant: 356)
        ])

        contrastLabel.font = NSFont.systemFont(ofSize: 11)
        contrastLabel.textColor = .secondaryLabelColor
        root.addArrangedSubview(contrastLabel)

        // Footer buttons
        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.spacing = 10
        let openJsonBtn = NSButton(title: L10n.tr("studio.btn.openJson"), target: self, action: #selector(onOpenJSON))
        let resetBuiltInBtn = NSButton(title: L10n.tr("studio.btn.resetPresets"), target: self, action: #selector(onResetPresets))
        let saveBtn = NSButton(title: L10n.tr("studio.btn.saveApply"), target: self, action: #selector(onSave))
        saveBtn.keyEquivalent = "\r"
        footer.addArrangedSubview(openJsonBtn)
        footer.addArrangedSubview(resetBuiltInBtn)
        footer.addArrangedSubview(saveBtn)
        root.addArrangedSubview(footer)
    }

    private func configurePopup(_ popup: NSPopUpButton, titles: [String]) {
        popup.removeAllItems()
        for t in titles { popup.addItem(withTitle: t) }
        popup.target = self
        popup.action = #selector(onFieldEdited)
    }

    private func buildLayoutTab() -> NSView {
        configurePopup(layoutModePopup, titles: ThemeLayoutMode.allCases.map { $0.displayName })
        configurePopup(trackPosPopup, titles: ThemeSlotPosition.allCases.map { $0.displayName })
        configurePopup(controlsPosPopup, titles: ThemeSlotPosition.allCases.map { $0.displayName })
        configurePopup(eqPosPopup, titles: ThemeSlotPosition.allCases.map { $0.displayName })
        configurePopup(eqStylePopup, titles: ThemeEQStyle.allCases.map { $0.displayName })
        configurePopup(backingPlacementPopup, titles: ThemeBackingPlacement.allCases.map { $0.displayName })
        configurePopup(textAlignPopup, titles: ThemeTextAlign.allCases.map { $0.displayName })
        configurePopup(progressPosPopup, titles: ThemeProgressPosition.allCases.map { $0.displayName })
        configurePopup(fontPopup, titles: ThemeFontStyle.allCases.map { $0.displayName })
        var systemFontTitles = [L10n.tr("studio.font.presetDefault")]
        systemFontTitles.append(contentsOf: NSFontManager.shared.availableFontFamilies.sorted())
        configurePopup(customFontPopup, titles: systemFontTitles)
        customFontPopup.widthAnchor.constraint(lessThanOrEqualToConstant: 155).isActive = true

        configurePopup(mainSizePopup, titles: ["11.5 pt", "13.0 pt", "14.5 pt"])
        configurePopup(backingSizePopup, titles: ["8.0 pt", "9.0 pt", "10.0 pt", "11.5 pt"])

        backingSpacingSlider.isContinuous = true
        backingSpacingSlider.target = self
        backingSpacingSlider.action = #selector(onSliderChanged(_:))
        backingSpacingSlider.widthAnchor.constraint(equalToConstant: 78).isActive = true
        backingSpacingValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        backingSpacingValueLabel.widthAnchor.constraint(equalToConstant: 38).isActive = true

        let decGapBtn = NSButton(title: "-", target: self, action: #selector(onBackingSpacingStep(_:)))
        decGapBtn.tag = -1
        decGapBtn.controlSize = .mini
        let incGapBtn = NSButton(title: "+", target: self, action: #selector(onBackingSpacingStep(_:)))
        incGapBtn.tag = 1
        incGapBtn.controlSize = .mini
        let spacingControlRow = NSStackView(views: [backingSpacingSlider, backingSpacingValueLabel, decGapBtn, incGapBtn])
        spacingControlRow.orientation = .horizontal
        spacingControlRow.spacing = 4

        configurePopup(paddingPopup, titles: [L10n.tr("studio.pad.tight"), L10n.tr("studio.pad.standard"), L10n.tr("studio.pad.wide")])
        configurePopup(radiusPopup, titles: [L10n.tr("studio.radius.sharp"), L10n.tr("studio.radius.tactile"), L10n.tr("studio.radius.rounded")])
        configurePopup(tagPopup, titles: ["BG ·", "[BG]", "↳"])
        configurePopup(notchStylePopup, titles: ThemeNotchStyle.allCases.map { $0.displayName })

        showBorderCheck.target = self
        showBorderCheck.action = #selector(onFieldEdited)

        let rows: [(String, NSView, String, NSView)] = [
            (L10n.tr("studio.label.layoutMode"), layoutModePopup, L10n.tr("studio.label.textAlign"), textAlignPopup),
            (L10n.tr("studio.label.trackPos"), trackPosPopup, L10n.tr("studio.label.controlsPos"), controlsPosPopup),
            (L10n.tr("studio.label.eqPos"), eqPosPopup, L10n.tr("studio.label.eqStyle"), eqStylePopup),
            (L10n.tr("studio.label.backingPlacement"), backingPlacementPopup, L10n.tr("studio.label.progressPos"), progressPosPopup),
            (L10n.tr("studio.label.font"), fontPopup, L10n.tr("studio.label.customFont"), customFontPopup),
            (L10n.tr("studio.label.mainSize"), mainSizePopup, L10n.tr("studio.label.backingSize"), backingSizePopup),
            (L10n.tr("studio.label.backingSpacing"), spacingControlRow, L10n.tr("studio.label.backingTag"), tagPopup),
            (L10n.tr("studio.label.padding"), paddingPopup, L10n.tr("studio.label.radius"), radiusPopup),
            (L10n.tr("studio.label.notchStyle"), notchStylePopup, L10n.tr("studio.label.showBorder"), showBorderCheck)
        ]

        let grid = NSGridView(numberOfColumns: 4, rows: rows.count)
        grid.rowSpacing = 6
        grid.columnSpacing = 10
        for (r, row) in rows.enumerated() {
            grid.cell(atColumnIndex: 0, rowIndex: r).contentView = NSTextField(labelWithString: row.0)
            grid.cell(atColumnIndex: 1, rowIndex: r).contentView = row.1
            grid.cell(atColumnIndex: 2, rowIndex: r).contentView = NSTextField(labelWithString: row.2)
            grid.cell(atColumnIndex: 3, rowIndex: r).contentView = row.3
        }

        let box = NSStackView(views: [grid])
        box.orientation = .vertical
        box.alignment = .leading
        box.spacing = 10
        box.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 8, right: 12)
        return box
    }

    private func buildColorTab() -> NSView {
        configurePopup(colorSyncPopup, titles: ThemeColorSyncMode.allCases.map { $0.displayName })

        let grid = NSGridView(numberOfColumns: 4, rows: 4)
        grid.rowSpacing = 12
        grid.columnSpacing = 12

        let pairs: [(Int, Int, String, NSControl)] = [
            (0, 0, L10n.tr("studio.color.bg"), bgWell), (0, 2, L10n.tr("studio.color.border"), borderWell),
            (1, 0, L10n.tr("studio.color.main"), mainWell), (1, 2, L10n.tr("studio.color.backing"), backingWell),
            (2, 0, L10n.tr("studio.color.upcoming"), upcomingWell), (2, 2, L10n.tr("studio.color.accent"), accentWell),
            (3, 0, L10n.tr("studio.color.track"), trackWell), (3, 2, L10n.tr("studio.color.syncMode"), colorSyncPopup)
        ]

        for p in pairs {
            grid.cell(atColumnIndex: p.1, rowIndex: p.0).contentView = NSTextField(labelWithString: p.2)
            grid.cell(atColumnIndex: p.1 + 1, rowIndex: p.0).contentView = p.3
            if let well = p.3 as? NSColorWell {
                well.target = self
                well.action = #selector(onFieldEdited)
                well.widthAnchor.constraint(equalToConstant: 56).isActive = true
                well.heightAnchor.constraint(equalToConstant: 24).isActive = true
            }
        }

        let tip = NSTextField(wrappingLabelWithString: L10n.tr("studio.color.tip"))
        tip.font = NSFont.systemFont(ofSize: 11)
        tip.textColor = .secondaryLabelColor

        let box = NSStackView(views: [grid, tip])
        box.orientation = .vertical
        box.alignment = .leading
        box.spacing = 14
        box.edgeInsets = NSEdgeInsets(top: 16, left: 14, bottom: 12, right: 14)
        return box
    }

    private func buildAnimationTab() -> NSView {
        configurePopup(lineTransPopup, titles: ThemeLineTransition.allCases.map { $0.displayName })
        configurePopup(wordAnimPopup, titles: ThemeWordAnimation.allCases.map { $0.displayName })
        configurePopup(vocalSyncModePopup, titles: VocalSyncMode.allCases.map { $0.displayName })

        for sl in [wordSpeedSlider, karaokeOffsetSlider, backingOffsetSlider, animSpeedSlider] {
            sl.isContinuous = true
            sl.target = self
            sl.action = #selector(onSliderChanged(_:))
            sl.widthAnchor.constraint(equalToConstant: 195).isActive = true
        }
        for lbl in [wordSpeedValueLabel, karaokeOffsetValueLabel, backingOffsetValueLabel, animSpeedValueLabel] {
            lbl.font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
            lbl.widthAnchor.constraint(equalToConstant: 54).isActive = true
        }

        func sliderRow(_ slider: NSSlider, _ valLabel: NSTextField) -> NSStackView {
            let s = NSStackView(views: [slider, valLabel])
            s.orientation = .horizontal
            s.spacing = 8
            return s
        }

        let grid = NSGridView(numberOfColumns: 2, rows: 7)
        grid.rowSpacing = 10
        grid.columnSpacing = 14

        let items: [(String, NSView)] = [
            (L10n.tr("studio.anim.lineTrans"), lineTransPopup),
            (L10n.tr("studio.anim.wordAnim"), wordAnimPopup),
            (L10n.tr("studio.anim.syncMode"), vocalSyncModePopup),
            (L10n.tr("studio.anim.wordSpeed"), sliderRow(wordSpeedSlider, wordSpeedValueLabel)),
            (L10n.tr("studio.anim.karaokeOffset"), sliderRow(karaokeOffsetSlider, karaokeOffsetValueLabel)),
            (L10n.tr("studio.anim.backingOffset"), sliderRow(backingOffsetSlider, backingOffsetValueLabel)),
            (L10n.tr("studio.anim.animSpeed"), sliderRow(animSpeedSlider, animSpeedValueLabel))
        ]
        for (r, item) in items.enumerated() {
            grid.cell(atColumnIndex: 0, rowIndex: r).contentView = NSTextField(labelWithString: item.0)
            grid.cell(atColumnIndex: 1, rowIndex: r).contentView = item.1
        }

        // Fine millisecond offset nudges & speed presets
        let stepRow = NSStackView()
        stepRow.orientation = .horizontal
        stepRow.spacing = 6
        stepRow.addArrangedSubview(NSTextField(labelWithString: L10n.tr("studio.anim.quickLabel")))
        for (title, hundredths) in [("-0.25s", -25), ("-0.05s", -5), ("+0.05s", 5), ("+0.25s", 25)] {
            let b = NSButton(title: title, target: self, action: #selector(onOffsetStepButton(_:)))
            b.tag = hundredths
            b.controlSize = .small
            stepRow.addArrangedSubview(b)
        }
        stepRow.addArrangedSubview(NSTextField(labelWithString: L10n.tr("studio.anim.tempoLabel")))
        for (title, pct) in [("0.75x", 75), ("1.00x", 100), ("1.25x", 125)] {
            let b = NSButton(title: title, target: self, action: #selector(onSpeedPresetButton(_:)))
            b.tag = pct
            b.controlSize = .small
            stepRow.addArrangedSubview(b)
        }

        let resetTempoBtn = NSButton(title: L10n.tr("studio.anim.resetTempo"), target: self, action: #selector(onResetTempo))
        let recalibrateBtn = NSButton(title: L10n.tr("studio.anim.recalibrateSync"), target: self, action: #selector(onRecalibrateSyncTapped))
        let actionRow = NSStackView(views: [resetTempoBtn, recalibrateBtn])
        actionRow.orientation = .horizontal
        actionRow.spacing = 10

        let note = NSTextField(wrappingLabelWithString: L10n.tr("studio.anim.note"))
        note.font = NSFont.systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor

        let box = NSStackView(views: [grid, stepRow, actionRow, note])
        box.orientation = .vertical
        box.alignment = .leading
        box.spacing = 11
        box.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 10, right: 14)
        return box
    }

    func reloadFromStore() {
        themePopup.removeAllItems()
        for t in ThemeStore.shared.themes {
            themePopup.addItem(withTitle: t.name)
        }
        editingTheme = ThemeStore.shared.activeTheme
        if let idx = ThemeStore.shared.themes.firstIndex(where: { $0.id == editingTheme.id }) {
            themePopup.selectItem(at: idx)
        }
        populateFields(from: editingTheme)
    }

    private func populateFields(from t: TouchBarTheme) {
        nameField.stringValue = t.name
        nameField.isEnabled = !t.isBuiltIn
        deleteButton.isEnabled = !t.isBuiltIn

        bgWell.color = NSColor(hex: t.backgroundHex)
        borderWell.color = NSColor(hex: t.borderHex)
        mainWell.color = NSColor(hex: t.mainTextHex)
        backingWell.color = NSColor(hex: t.backingTextHex)
        upcomingWell.color = t.upcomingTextHex.isEmpty
            ? NSColor(hex: t.mainTextHex).withAlphaComponent(0.50)
            : NSColor(hex: t.upcomingTextHex)
        accentWell.color = NSColor(hex: t.accentHex)
        trackWell.color = NSColor(hex: t.trackTextHex)

        if let idx = ThemeLayoutMode.allCases.firstIndex(of: t.layoutMode) { layoutModePopup.selectItem(at: idx) }
        if let idx = ThemeSlotPosition.allCases.firstIndex(of: t.trackTitlePosition) { trackPosPopup.selectItem(at: idx) }
        if let idx = ThemeSlotPosition.allCases.firstIndex(of: t.controlsPosition) { controlsPosPopup.selectItem(at: idx) }
        if let idx = ThemeSlotPosition.allCases.firstIndex(of: t.eqPosition) { eqPosPopup.selectItem(at: idx) }
        if let idx = ThemeEQStyle.allCases.firstIndex(of: t.eqStyle) { eqStylePopup.selectItem(at: idx) }
        if let idx = ThemeBackingPlacement.allCases.firstIndex(of: t.backingPlacement) { backingPlacementPopup.selectItem(at: idx) }
        if let idx = ThemeTextAlign.allCases.firstIndex(of: t.textAlignment) { textAlignPopup.selectItem(at: idx) }
        if let idx = ThemeProgressPosition.allCases.firstIndex(of: t.progressPosition) { progressPosPopup.selectItem(at: idx) }
        if let idx = ThemeFontStyle.allCases.firstIndex(of: t.fontStyle) { fontPopup.selectItem(at: idx) }
        if !t.customFontName.isEmpty, let cIdx = customFontPopup.itemTitles.firstIndex(of: t.customFontName) {
            customFontPopup.selectItem(at: cIdx)
        } else {
            customFontPopup.selectItem(at: 0)
        }
        if let idx = ThemeColorSyncMode.allCases.firstIndex(of: t.colorSyncMode) { colorSyncPopup.selectItem(at: idx) }
        if let idx = ThemeLineTransition.allCases.firstIndex(of: t.lineTransition) { lineTransPopup.selectItem(at: idx) }
        if let idx = ThemeWordAnimation.allCases.firstIndex(of: t.wordAnimation) { wordAnimPopup.selectItem(at: idx) }
        if let idx = ThemeNotchStyle.allCases.firstIndex(of: t.notchStyle) { notchStylePopup.selectItem(at: idx) }

        mainSizePopup.selectItem(at: t.mainFontSize <= 12.0 ? 0 : (t.mainFontSize <= 13.8 ? 1 : 2))
        backingSizePopup.selectItem(at: t.backingFontSize <= 8.5 ? 0 : (t.backingFontSize <= 9.5 ? 1 : (t.backingFontSize <= 10.8 ? 2 : 3)))
        backingSpacingSlider.doubleValue = Double(t.backingSpacing)
        backingSpacingValueLabel.stringValue = Self.formatSpacing(t.backingSpacing)
        paddingPopup.selectItem(at: t.horizontalPadding <= 5.5 ? 0 : (t.horizontalPadding <= 11.0 ? 1 : 2))
        radiusPopup.selectItem(at: t.cornerRadius <= 1 ? 0 : (t.cornerRadius <= 4 ? 1 : 2))
        if let tIdx = tagPopup.itemTitles.firstIndex(of: t.backingTag) { tagPopup.selectItem(at: tIdx) }

        if let idx = VocalSyncMode.allCases.firstIndex(of: t.vocalSyncMode) { vocalSyncModePopup.selectItem(at: idx) }
        wordSpeedSlider.doubleValue = Double(t.wordSpeedScale)
        wordSpeedValueLabel.stringValue = String(format: "%.2fx", t.wordSpeedScale)
        karaokeOffsetSlider.doubleValue = t.karaokeOffsetSeconds
        karaokeOffsetValueLabel.stringValue = String(format: "%+.2fs", t.karaokeOffsetSeconds)
        backingOffsetSlider.doubleValue = t.backingOffsetSeconds
        backingOffsetValueLabel.stringValue = String(format: "%+.2fs", t.backingOffsetSeconds)
        animSpeedSlider.doubleValue = Double(t.animationSpeed)
        animSpeedValueLabel.stringValue = String(format: "%.2fx", t.animationSpeed)

        showBorderCheck.state = t.showBorder ? .on : .off

        updateContrastInfo(for: t)
        previewView.applyTheme(t)
    }

    private func collectEditedTheme() -> TouchBarTheme {
        var t = editingTheme
        if !t.isBuiltIn {
            let trimmed = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { t.name = trimmed }
        }
        t.backgroundHex = bgWell.color.hexString
        t.borderHex = borderWell.color.hexString
        t.mainTextHex = mainWell.color.hexString
        t.backingTextHex = backingWell.color.hexString
        t.upcomingTextHex = upcomingWell.color.hexString
        t.accentHex = accentWell.color.hexString
        t.trackTextHex = trackWell.color.hexString

        let prevMode = t.layoutMode
        let selectedMode = ThemeLayoutMode.allCases[max(0, layoutModePopup.indexOfSelectedItem)]
        if selectedMode != prevMode {
            // Apply preset slot ergonomics when user picks a layout preset, while staying overridable afterward
            t.layoutMode = selectedMode
            switch selectedMode {
            case .standard:
                t.trackTitlePosition = .left
                t.controlsPosition = .right
                t.eqPosition = .left
                t.textAlignment = .center
            case .centeredMinimal:
                t.trackTitlePosition = .hidden
                t.controlsPosition = .right
                t.eqPosition = .left
                t.textAlignment = .center
            case .rightFlow:
                t.trackTitlePosition = .right
                t.controlsPosition = .right
                t.eqPosition = .left
                t.textAlignment = .left
            case .lyricsOnly:
                t.trackTitlePosition = .hidden
                t.controlsPosition = .hidden
                t.eqPosition = .hidden
                t.textAlignment = .center
            }
        } else {
            t.layoutMode = selectedMode
            t.trackTitlePosition = ThemeSlotPosition.allCases[max(0, trackPosPopup.indexOfSelectedItem)]
            t.controlsPosition = ThemeSlotPosition.allCases[max(0, controlsPosPopup.indexOfSelectedItem)]
            t.eqPosition = ThemeSlotPosition.allCases[max(0, eqPosPopup.indexOfSelectedItem)]
            t.textAlignment = ThemeTextAlign.allCases[max(0, textAlignPopup.indexOfSelectedItem)]
        }

        t.showTrackTitle = (t.trackTitlePosition != .hidden)
        t.eqStyle = ThemeEQStyle.allCases[max(0, eqStylePopup.indexOfSelectedItem)]
        t.backingPlacement = ThemeBackingPlacement.allCases[max(0, backingPlacementPopup.indexOfSelectedItem)]
        t.progressPosition = ThemeProgressPosition.allCases[max(0, progressPosPopup.indexOfSelectedItem)]
        t.showProgressBar = (t.progressPosition != .hidden)

        let chosenFontStyle = ThemeFontStyle.allCases[max(0, fontPopup.indexOfSelectedItem)]
        if chosenFontStyle != t.fontStyle {
            t.fontStyle = chosenFontStyle
            t.customFontName = ""
            customFontPopup.selectItem(at: 0)
        } else {
            t.fontStyle = chosenFontStyle
            let customIdx = customFontPopup.indexOfSelectedItem
            t.customFontName = (customIdx > 0) ? (customFontPopup.titleOfSelectedItem ?? "") : ""
        }
        t.mainFontSize = [11.5, 13.0, 14.5][max(0, min(2, mainSizePopup.indexOfSelectedItem))]
        t.backingFontSize = [8.0, 9.0, 10.0, 11.5][max(0, min(3, backingSizePopup.indexOfSelectedItem))]
        t.backingSpacing = CGFloat((backingSpacingSlider.doubleValue * 2.0).rounded() / 2.0)
        t.horizontalPadding = [4.0, 8.0, 16.0][max(0, min(2, paddingPopup.indexOfSelectedItem))]
        t.cornerRadius = [0.0, 4.0, 6.0][max(0, min(2, radiusPopup.indexOfSelectedItem))]
        t.backingTag = tagPopup.titleOfSelectedItem ?? "BG ·"
        t.showBorder = (showBorderCheck.state == .on)

        t.colorSyncMode = ThemeColorSyncMode.allCases[max(0, colorSyncPopup.indexOfSelectedItem)]
        t.notchStyle = ThemeNotchStyle.allCases[max(0, notchStylePopup.indexOfSelectedItem)]
        t.lineTransition = ThemeLineTransition.allCases[max(0, lineTransPopup.indexOfSelectedItem)]
        t.wordAnimation = ThemeWordAnimation.allCases[max(0, wordAnimPopup.indexOfSelectedItem)]
        t.vocalSyncMode = VocalSyncMode.allCases[max(0, vocalSyncModePopup.indexOfSelectedItem)]
        t.wordSpeedScale = CGFloat((wordSpeedSlider.doubleValue * 20.0).rounded() / 20.0)
        t.karaokeOffsetSeconds = (karaokeOffsetSlider.doubleValue * 20.0).rounded() / 20.0
        t.backingOffsetSeconds = (backingOffsetSlider.doubleValue * 20.0).rounded() / 20.0
        t.animationSpeed = CGFloat((animSpeedSlider.doubleValue * 20.0).rounded() / 20.0)
        return t
    }

    private static func formatSpacing(_ px: CGFloat) -> String {
        let rounded = (px * 2.0).rounded() / 2.0
        if abs(rounded - rounded.rounded()) < 0.01 {
            return String(format: "%.0f px", rounded)
        }
        return String(format: "%.1f px", rounded)
    }

    @objc private func onSliderChanged(_ sender: NSSlider) {
        let ws = (wordSpeedSlider.doubleValue * 20.0).rounded() / 20.0
        let off = (karaokeOffsetSlider.doubleValue * 20.0).rounded() / 20.0
        let bgOff = (backingOffsetSlider.doubleValue * 20.0).rounded() / 20.0
        let ans = (animSpeedSlider.doubleValue * 20.0).rounded() / 20.0
        let gap = CGFloat((backingSpacingSlider.doubleValue * 2.0).rounded() / 2.0)
        wordSpeedValueLabel.stringValue = String(format: "%.2fx", ws)
        karaokeOffsetValueLabel.stringValue = String(format: "%+.2fs", off)
        backingOffsetValueLabel.stringValue = String(format: "%+.2fs", bgOff)
        animSpeedValueLabel.stringValue = String(format: "%.2fx", ans)
        backingSpacingValueLabel.stringValue = Self.formatSpacing(gap)
        onFieldEdited()
    }

    @objc private func onBackingSpacingStep(_ sender: NSButton) {
        let next = (backingSpacingSlider.doubleValue + Double(sender.tag)).rounded()
        backingSpacingSlider.doubleValue = max(-4.0, min(12.0, next))
        onSliderChanged(backingSpacingSlider)
    }

    @objc private func onOffsetStepButton(_ sender: NSButton) {
        let next = karaokeOffsetSlider.doubleValue + Double(sender.tag) / 100.0
        karaokeOffsetSlider.doubleValue = max(-2.50, min(2.50, next))
        onSliderChanged(karaokeOffsetSlider)
    }

    @objc private func onSpeedPresetButton(_ sender: NSButton) {
        wordSpeedSlider.doubleValue = Double(sender.tag) / 100.0
        onSliderChanged(wordSpeedSlider)
    }

    @objc private func onResetTempo() {
        wordSpeedSlider.doubleValue = 1.0
        karaokeOffsetSlider.doubleValue = 0.0
        backingOffsetSlider.doubleValue = 0.0
        animSpeedSlider.doubleValue = 1.0
        onSliderChanged(wordSpeedSlider)
    }

    @objc private func onRecalibrateSyncTapped() {
        onRecalibrateSync?()
    }

    private func updateContrastInfo(for t: TouchBarTheme) {
        let bg = NSColor(hex: t.backgroundHex)
        let mainRatio = NSColor(hex: t.mainTextHex).contrastRatio(with: bg)
        let bgRatio = NSColor(hex: t.backingTextHex).contrastRatio(with: bg)
        let status = (mainRatio >= 4.5 && bgRatio >= 4.5) ? L10n.tr("studio.contrast.pass") : L10n.tr("studio.contrast.fail")
        contrastLabel.stringValue = L10n.tr("studio.contrast.summary", mainRatio, bgRatio, status)
        contrastLabel.textColor = (mainRatio >= 4.5 && bgRatio >= 4.5) ? .secondaryLabelColor : .systemOrange
    }

    @objc private func onSelectLanguage() {
        let idx = languagePopup.indexOfSelectedItem
        guard idx >= 0, idx < AppLanguage.allCases.count else { return }
        L10n.currentLanguage = AppLanguage.allCases[idx]
    }

    @objc private func onLanguageDidChange() {
        let selectedTabID = mainTabView?.selectedTabViewItem?.identifier as? String
        setupUI()
        reloadFromStore()
        if let id = selectedTabID, let tv = mainTabView {
            tv.selectTabViewItem(withIdentifier: id)
        }
        if window?.isVisible == true {
            startPreviewAnimation()
        }
    }

    @objc private func onSelectTheme() {
        let idx = themePopup.indexOfSelectedItem
        guard idx >= 0, idx < ThemeStore.shared.themes.count else { return }
        let selected = ThemeStore.shared.themes[idx]
        ThemeStore.shared.selectTheme(id: selected.id)
        editingTheme = selected
        populateFields(from: selected)
    }

    @objc private func onFieldEdited() {
        var updated = collectEditedTheme()
        if updated.isBuiltIn {
            let customName = "\(updated.name) Custom"
            updated = ThemeStore.shared.duplicateTheme(updated, newName: customName)
            editingTheme = updated
            reloadFromStore()
            return
        }
        editingTheme = updated
        populateFields(from: updated)
        ThemeStore.shared.upsertTheme(updated, makeActive: true)
    }

    @objc private func onDuplicateTheme() {
        let count = ThemeStore.shared.themes.filter { !$0.isBuiltIn }.count + 1
        let created = ThemeStore.shared.duplicateTheme(editingTheme, newName: "Custom \(count)")
        editingTheme = created
        reloadFromStore()
    }

    @objc private func onDeleteTheme() {
        guard !editingTheme.isBuiltIn else { return }
        ThemeStore.shared.deleteTheme(id: editingTheme.id)
        reloadFromStore()
    }

    @objc private func onResetPresets() {
        ThemeStore.shared.resetBuiltIns()
        reloadFromStore()
    }

    @objc private func onOpenJSON() {
        ThemeStore.shared.save()
        NSWorkspace.shared.open(URL(fileURLWithPath: ThemeStore.shared.themesFilePath))
    }

    @objc private func onSave() {
        let updated = collectEditedTheme()
        ThemeStore.shared.upsertTheme(updated, makeActive: true)
        window?.close()
    }
}
