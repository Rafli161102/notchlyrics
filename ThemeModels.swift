import Cocoa

enum ThemeFontStyle: String, Codable, CaseIterable {
    case sans = "sans"
    case rounded = "rounded"
    case serif = "serif"
    case mono = "mono"

    var displayName: String {
        switch self {
        case .sans: return "System Sans"
        case .rounded: return "Rounded"
        case .serif: return "Editorial Serif"
        case .mono: return "Monospace"
        }
    }

    func font(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        switch self {
        case .sans:
            return NSFont.systemFont(ofSize: size, weight: weight)
        case .rounded:
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            if let desc = base.fontDescriptor.withDesign(.rounded),
               let f = NSFont(descriptor: desc, size: size) {
                return f
            }
            return base
        case .serif:
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            if let desc = base.fontDescriptor.withDesign(.serif),
               let f = NSFont(descriptor: desc, size: size) {
                return f
            }
            return base
        case .mono:
            return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        }
    }
}

enum ThemeLayoutMode: String, Codable, CaseIterable {
    case standard = "standard"
    case centeredMinimal = "centeredMinimal"
    case rightFlow = "rightFlow"
    case lyricsOnly = "lyricsOnly"

    var displayName: String {
        switch self {
        case .standard: return "Klasik Seimbang"
        case .centeredMinimal: return "Tengah Minimal"
        case .rightFlow: return "Lirik Kiri + Judul Kanan"
        case .lyricsOnly: return "Fokus Lirik Penuh"
        }
    }
}

enum ThemeSlotPosition: String, Codable, CaseIterable {
    case left = "left"
    case right = "right"
    case hidden = "hidden"

    var displayName: String {
        switch self {
        case .left: return "Sisi Kiri"
        case .right: return "Sisi Kanan"
        case .hidden: return "Sembunyikan"
        }
    }
}

enum ThemeBackingPlacement: String, Codable, CaseIterable {
    case below = "below"
    case above = "above"
    case inlineBeside = "inlineBeside"

    var displayName: String {
        switch self {
        case .below: return "Di Bawah Vokal Utama"
        case .above: return "Di Atas Vokal Utama"
        case .inlineBeside: return "Sejajar 1 Baris"
        }
    }
}

enum ThemeTextAlign: String, Codable, CaseIterable {
    case center = "center"
    case left = "left"
    case right = "right"

    var displayName: String {
        switch self {
        case .center: return "Rata Tengah"
        case .left: return "Rata Kiri"
        case .right: return "Rata Kanan"
        }
    }

    var nsAlignment: NSTextAlignment {
        switch self {
        case .center: return .center
        case .left: return .left
        case .right: return .right
        }
    }
}

enum ThemeProgressPosition: String, Codable, CaseIterable {
    case bottom = "bottom"
    case top = "top"
    case hidden = "hidden"

    var displayName: String {
        switch self {
        case .bottom: return "Garis Bawah"
        case .top: return "Garis Atas"
        case .hidden: return "Sembunyikan"
        }
    }
}

enum ThemeEQStyle: String, Codable, CaseIterable {
    case bars = "bars"
    case pulseDot = "pulseDot"
    case none = "none"

    var displayName: String {
        switch self {
        case .bars: return "Bar Equalizer + Titik"
        case .pulseDot: return "Titik Vokal Saja"
        case .none: return "Nonaktif"
        }
    }
}

enum ThemeLineTransition: String, Codable, CaseIterable {
    case pushUp = "pushUp"
    case pushDown = "pushDown"
    case slideLeft = "slideLeft"
    case crossfade = "crossfade"
    case zoomSoft = "zoomSoft"
    case none = "none"

    var displayName: String {
        switch self {
        case .pushUp: return "Dorong ke Atas"
        case .pushDown: return "Turun ke Bawah"
        case .slideLeft: return "Geser Samping"
        case .crossfade: return "Crossfade Halus"
        case .zoomSoft: return "Pop Skala Lembut"
        case .none: return "Instan (Tanpa Transisi)"
        }
    }
}

enum ThemeWordAnimation: String, Codable, CaseIterable {
    case karaokeLift = "karaokeLift"
    case smoothWipe = "smoothWipe"
    case typewriter = "typewriter"
    case glowPulse = "glowPulse"
    case solid = "solid"

    var displayName: String {
        switch self {
        case .karaokeLift: return "Karaoke + Angkat Huruf"
        case .smoothWipe: return "Sapuan Warna Per Kata"
        case .typewriter: return "Ketik Huruf Bertahap"
        case .glowPulse: return "Sorot Tebal Reaktif"
        case .solid: return "Statis Penuh"
        }
    }
}

enum ThemeColorSyncMode: String, Codable, CaseIterable {
    case adaptiveArtwork = "adaptiveArtwork"
    case vividArtwork = "vividArtwork"
    case themeOnly = "themeOnly"

    var displayName: String {
        switch self {
        case .adaptiveArtwork: return "Adaptif Sampul (Seimbang)"
        case .vividArtwork: return "Sampul Lagu Kuat"
        case .themeOnly: return "Warna Tema Kustom Saja"
        }
    }
}

struct TouchBarTheme: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var isBuiltIn: Bool
    var backgroundHex: String
    var borderHex: String
    var mainTextHex: String
    var backingTextHex: String
    var upcomingTextHex: String
    var accentHex: String
    var trackTextHex: String
    var cornerRadius: CGFloat
    var fontStyle: ThemeFontStyle
    var backingTag: String
    var showBorder: Bool
    var showProgressBar: Bool
    var showTrackTitle: Bool

    // Extended Layout & Animation Settings
    var layoutMode: ThemeLayoutMode
    var trackTitlePosition: ThemeSlotPosition
    var controlsPosition: ThemeSlotPosition
    var eqPosition: ThemeSlotPosition
    var backingPlacement: ThemeBackingPlacement
    var textAlignment: ThemeTextAlign
    var progressPosition: ThemeProgressPosition
    var eqStyle: ThemeEQStyle
    var mainFontSize: CGFloat
    var backingFontSize: CGFloat
    var horizontalPadding: CGFloat
    var lineTransition: ThemeLineTransition
    var wordAnimation: ThemeWordAnimation
    var animationSpeed: CGFloat
    var wordSpeedScale: CGFloat
    var karaokeOffsetSeconds: TimeInterval
    var colorSyncMode: ThemeColorSyncMode

    init(
        id: String,
        name: String,
        isBuiltIn: Bool,
        backgroundHex: String,
        borderHex: String,
        mainTextHex: String,
        backingTextHex: String,
        upcomingTextHex: String = "",
        accentHex: String,
        trackTextHex: String,
        cornerRadius: CGFloat,
        fontStyle: ThemeFontStyle,
        backingTag: String,
        showBorder: Bool,
        showProgressBar: Bool,
        showTrackTitle: Bool,
        layoutMode: ThemeLayoutMode = .standard,
        trackTitlePosition: ThemeSlotPosition = .left,
        controlsPosition: ThemeSlotPosition = .right,
        eqPosition: ThemeSlotPosition = .left,
        backingPlacement: ThemeBackingPlacement = .below,
        textAlignment: ThemeTextAlign = .center,
        progressPosition: ThemeProgressPosition = .bottom,
        eqStyle: ThemeEQStyle = .bars,
        mainFontSize: CGFloat = 13.0,
        backingFontSize: CGFloat = 10.0,
        horizontalPadding: CGFloat = 8.0,
        lineTransition: ThemeLineTransition = .pushUp,
        wordAnimation: ThemeWordAnimation = .karaokeLift,
        animationSpeed: CGFloat = 1.0,
        wordSpeedScale: CGFloat = 1.0,
        karaokeOffsetSeconds: TimeInterval = 0.0,
        colorSyncMode: ThemeColorSyncMode = .adaptiveArtwork
    ) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.backgroundHex = backgroundHex
        self.borderHex = borderHex
        self.mainTextHex = mainTextHex
        self.backingTextHex = backingTextHex
        self.upcomingTextHex = upcomingTextHex
        self.accentHex = accentHex
        self.trackTextHex = trackTextHex
        self.cornerRadius = cornerRadius
        self.fontStyle = fontStyle
        self.backingTag = backingTag
        self.showBorder = showBorder
        self.showProgressBar = showProgressBar
        self.showTrackTitle = showTrackTitle
        self.layoutMode = layoutMode
        self.trackTitlePosition = trackTitlePosition
        self.controlsPosition = controlsPosition
        self.eqPosition = eqPosition
        self.backingPlacement = backingPlacement
        self.textAlignment = textAlignment
        self.progressPosition = progressPosition
        self.eqStyle = eqStyle
        self.mainFontSize = mainFontSize
        self.backingFontSize = backingFontSize
        self.horizontalPadding = horizontalPadding
        self.lineTransition = lineTransition
        self.wordAnimation = wordAnimation
        self.animationSpeed = animationSpeed
        self.wordSpeedScale = wordSpeedScale
        self.karaokeOffsetSeconds = karaokeOffsetSeconds
        self.colorSyncMode = colorSyncMode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        isBuiltIn = try c.decode(Bool.self, forKey: .isBuiltIn)
        backgroundHex = try c.decode(String.self, forKey: .backgroundHex)
        borderHex = try c.decode(String.self, forKey: .borderHex)
        mainTextHex = try c.decode(String.self, forKey: .mainTextHex)
        backingTextHex = try c.decode(String.self, forKey: .backingTextHex)
        upcomingTextHex = try c.decodeIfPresent(String.self, forKey: .upcomingTextHex) ?? ""
        accentHex = try c.decode(String.self, forKey: .accentHex)
        trackTextHex = try c.decode(String.self, forKey: .trackTextHex)
        cornerRadius = try c.decode(CGFloat.self, forKey: .cornerRadius)
        fontStyle = try c.decode(ThemeFontStyle.self, forKey: .fontStyle)
        backingTag = try c.decode(String.self, forKey: .backingTag)
        showBorder = try c.decode(Bool.self, forKey: .showBorder)
        showProgressBar = try c.decode(Bool.self, forKey: .showProgressBar)
        showTrackTitle = try c.decode(Bool.self, forKey: .showTrackTitle)

        layoutMode = try c.decodeIfPresent(ThemeLayoutMode.self, forKey: .layoutMode) ?? .standard
        let defaultTitlePos: ThemeSlotPosition = showTrackTitle ? .left : .hidden
        trackTitlePosition = try c.decodeIfPresent(ThemeSlotPosition.self, forKey: .trackTitlePosition) ?? defaultTitlePos
        controlsPosition = try c.decodeIfPresent(ThemeSlotPosition.self, forKey: .controlsPosition) ?? .right
        eqPosition = try c.decodeIfPresent(ThemeSlotPosition.self, forKey: .eqPosition) ?? .left
        backingPlacement = try c.decodeIfPresent(ThemeBackingPlacement.self, forKey: .backingPlacement) ?? .below
        textAlignment = try c.decodeIfPresent(ThemeTextAlign.self, forKey: .textAlignment) ?? .center
        let defaultProgPos: ThemeProgressPosition = showProgressBar ? .bottom : .hidden
        progressPosition = try c.decodeIfPresent(ThemeProgressPosition.self, forKey: .progressPosition) ?? defaultProgPos
        eqStyle = try c.decodeIfPresent(ThemeEQStyle.self, forKey: .eqStyle) ?? .bars
        mainFontSize = try c.decodeIfPresent(CGFloat.self, forKey: .mainFontSize) ?? 13.0
        backingFontSize = try c.decodeIfPresent(CGFloat.self, forKey: .backingFontSize) ?? 10.0
        horizontalPadding = try c.decodeIfPresent(CGFloat.self, forKey: .horizontalPadding) ?? 8.0
        lineTransition = try c.decodeIfPresent(ThemeLineTransition.self, forKey: .lineTransition) ?? .pushUp
        wordAnimation = try c.decodeIfPresent(ThemeWordAnimation.self, forKey: .wordAnimation) ?? .karaokeLift
        animationSpeed = try c.decodeIfPresent(CGFloat.self, forKey: .animationSpeed) ?? 1.0
        wordSpeedScale = try c.decodeIfPresent(CGFloat.self, forKey: .wordSpeedScale) ?? 1.0
        karaokeOffsetSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .karaokeOffsetSeconds) ?? 0.0
        colorSyncMode = try c.decodeIfPresent(ThemeColorSyncMode.self, forKey: .colorSyncMode) ?? .adaptiveArtwork
    }

    static let builtInThemes: [TouchBarTheme] = [
        TouchBarTheme(
            id: "oled-obsidian",
            name: "OLED Obsidian",
            isBuiltIn: true,
            backgroundHex: "#000000",
            borderHex: "#1F1F22",
            mainTextHex: "#F5F5F7",
            backingTextHex: "#D99B26",
            accentHex: "#D99B26",
            trackTextHex: "#8E8E93",
            cornerRadius: 4,
            fontStyle: .sans,
            backingTag: "BG ·",
            showBorder: false,
            showProgressBar: true,
            showTrackTitle: true,
            layoutMode: .standard,
            lineTransition: .pushUp,
            wordAnimation: .karaokeLift,
            colorSyncMode: .adaptiveArtwork
        ),
        TouchBarTheme(
            id: "braun-signal",
            name: "Braun Signal",
            isBuiltIn: true,
            backgroundHex: "#141414",
            borderHex: "#2E2E32",
            mainTextHex: "#FFFFFF",
            backingTextHex: "#FF5A1F",
            accentHex: "#FF5A1F",
            trackTextHex: "#9A9AA0",
            cornerRadius: 3,
            fontStyle: .sans,
            backingTag: "[BG]",
            showBorder: true,
            showProgressBar: true,
            showTrackTitle: true,
            layoutMode: .rightFlow,
            trackTitlePosition: .right,
            textAlignment: .left,
            lineTransition: .slideLeft,
            wordAnimation: .smoothWipe,
            colorSyncMode: .themeOnly
        ),
        TouchBarTheme(
            id: "studio-crimson",
            name: "Studio Crimson",
            isBuiltIn: true,
            backgroundHex: "#0B0B0D",
            borderHex: "#26262B",
            mainTextHex: "#F2F2F2",
            backingTextHex: "#E25563",
            accentHex: "#E25563",
            trackTextHex: "#8C8C94",
            cornerRadius: 6,
            fontStyle: .rounded,
            backingTag: "BG ·",
            showBorder: true,
            showProgressBar: true,
            showTrackTitle: true,
            layoutMode: .centeredMinimal,
            trackTitlePosition: .hidden,
            lineTransition: .zoomSoft,
            wordAnimation: .glowPulse,
            colorSyncMode: .vividArtwork
        ),
        TouchBarTheme(
            id: "warm-ivory",
            name: "Warm Ivory Paper",
            isBuiltIn: true,
            backgroundHex: "#EAE5DC",
            borderHex: "#C9C2B6",
            mainTextHex: "#161616",
            backingTextHex: "#9B3B24",
            accentHex: "#9B3B24",
            trackTextHex: "#524E48",
            cornerRadius: 6,
            fontStyle: .serif,
            backingTag: "BG ·",
            showBorder: true,
            showProgressBar: true,
            showTrackTitle: true,
            layoutMode: .standard,
            lineTransition: .crossfade,
            wordAnimation: .typewriter,
            colorSyncMode: .themeOnly
        )
    ]
}

extension NSColor {
    convenience init(hex: String, fallback: NSColor = .black) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let val = UInt64(cleaned, radix: 16) else {
            self.init(cgColor: fallback.cgColor)!
            return
        }
        let r = CGFloat((val >> 16) & 0xFF) / 255.0
        let g = CGFloat((val >> 8) & 0xFF) / 255.0
        let b = CGFloat(val & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }

    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    var relativeLuminance: CGFloat {
        guard let rgb = usingColorSpace(.sRGB) else { return 0 }
        func lin(_ c: CGFloat) -> CGFloat {
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(rgb.redComponent) + 0.7152 * lin(rgb.greenComponent) + 0.0722 * lin(rgb.blueComponent)
    }

    func contrastRatio(with other: NSColor) -> CGFloat {
        let l1 = relativeLuminance
        let l2 = other.relativeLuminance
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }
}

final class ThemeStore {
    static let shared = ThemeStore()

    private let supportDir = (NSHomeDirectory() as NSString)
        .appendingPathComponent("Library/Application Support/TouchBarLyrics")
    var themesFilePath: String { (supportDir as NSString).appendingPathComponent("themes.json") }
    private let keySelectedThemeID = "selectedThemeID"

    private(set) var themes: [TouchBarTheme] = TouchBarTheme.builtInThemes
    private(set) var activeTheme: TouchBarTheme = TouchBarTheme.builtInThemes[0]

    var onThemeChanged: ((TouchBarTheme) -> Void)?

    private init() {
        load()
    }

    func load() {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: supportDir, withIntermediateDirectories: true)

        if let data = fm.contents(atPath: themesFilePath),
           let decoded = try? JSONDecoder().decode([TouchBarTheme].self, from: data),
           !decoded.isEmpty {
            themes = decoded
        } else {
            themes = TouchBarTheme.builtInThemes
            save()
        }

        let selectedID = UserDefaults.standard.string(forKey: keySelectedThemeID) ?? "oled-obsidian"
        if let found = themes.first(where: { $0.id == selectedID }) {
            activeTheme = found
        } else {
            activeTheme = themes[0]
        }
    }

    func save() {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(themes) {
            try? data.write(to: URL(fileURLWithPath: themesFilePath))
        }
    }

    func selectTheme(id: String) {
        guard let found = themes.first(where: { $0.id == id }) else { return }
        activeTheme = found
        UserDefaults.standard.set(id, forKey: keySelectedThemeID)
        onThemeChanged?(activeTheme)
    }

    func upsertTheme(_ theme: TouchBarTheme, makeActive: Bool = true) {
        if let idx = themes.firstIndex(where: { $0.id == theme.id }) {
            themes[idx] = theme
        } else {
            themes.append(theme)
        }
        save()
        if makeActive {
            selectTheme(id: theme.id)
        }
    }

    func duplicateTheme(_ source: TouchBarTheme, newName: String) -> TouchBarTheme {
        var copy = source
        copy.id = "custom-\(UUID().uuidString.prefix(8).lowercased())"
        copy.name = newName
        copy.isBuiltIn = false
        upsertTheme(copy, makeActive: true)
        return copy
    }

    func deleteTheme(id: String) {
        guard let idx = themes.firstIndex(where: { $0.id == id }), !themes[idx].isBuiltIn else { return }
        themes.remove(at: idx)
        save()
        if activeTheme.id == id {
            selectTheme(id: themes.first?.id ?? "oled-obsidian")
        }
    }

    func resetBuiltIns() {
        let customs = themes.filter { !$0.isBuiltIn }
        themes = TouchBarTheme.builtInThemes + customs
        save()
        if let current = themes.first(where: { $0.id == activeTheme.id }) {
            activeTheme = current
        } else {
            activeTheme = themes[0]
        }
        onThemeChanged?(activeTheme)
    }
}
