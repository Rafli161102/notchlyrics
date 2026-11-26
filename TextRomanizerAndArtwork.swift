import Cocoa
import ImageIO

// MARK: - Multi-Script Romanizer (Japanese Kanji/Kana, Korean Hangul, Chinese, Cyrillic, Thai, Arabic)

enum TextRomanizer {
    static func containsJapaneseKana(_ text: String) -> Bool {
        return text.unicodeScalars.contains { scalar in
            (0x3040...0x30FF).contains(scalar.value) || (0x31F0...0x31FF).contains(scalar.value)
        }
    }

    static func needsRomanization(_ text: String) -> Bool {
        return text.unicodeScalars.contains { $0.value > 0x024F && $0.properties.isAlphabetic }
    }

    static func romanize(_ text: String, preferJapanese: Bool = false) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, needsRomanization(trimmed) else { return text }

        let treatAsJapanese = containsJapaneseKana(trimmed) || (preferJapanese && containsCJK(trimmed))
        if treatAsJapanese {
            return romanizeJapanese(trimmed)
        }

        let latin = cfTransform(trimmed, transform: kCFStringTransformToLatin)
        let clean = cfTransform(latin, transform: kCFStringTransformStripDiacritics)
        return normalizeSpacing(clean.replacingOccurrences(of: "-", with: ""))
    }

    static func romanizeLines(_ lines: [LyricLine], titleHint: String = "", artistHint: String = "") -> [LyricLine] {
        let songHasKana = containsJapaneseKana(titleHint)
            || containsJapaneseKana(artistHint)
            || lines.contains { containsJapaneseKana($0.mainText) || containsJapaneseKana($0.backingText ?? "") }

        func romanizeWordsList(_ srcWords: [LyricWord]) -> (text: String?, words: [LyricWord]) {
            guard !srcWords.isEmpty else { return (nil, []) }
            var outWords: [LyricWord] = []
            var combined = ""
            for w in srcWords {
                let rawTrim = w.text.trimmingCharacters(in: .whitespacesAndNewlines)
                var piece = rawTrim.isEmpty ? "" : romanize(rawTrim, preferJapanese: songHasKana)
                if piece.isEmpty && !w.text.isEmpty {
                    piece = w.text
                }
                let needsSpace = !combined.isEmpty
                    && !combined.hasSuffix(" ")
                    && !piece.isEmpty
                    && !piece.hasPrefix(" ")
                    && !",.!?;:)".contains(piece.first!)
                let spaced = (needsSpace ? " " : "") + piece
                combined += spaced
                outWords.append(LyricWord(time: w.time, duration: w.duration, text: spaced))
            }
            let trimmed = combined.trimmingCharacters(in: .whitespacesAndNewlines)
            return (trimmed.isEmpty ? nil : trimmed, outWords)
        }

        return lines.map { line in
            let mainPair = romanizeWordsList(line.words)
            let backPair = romanizeWordsList(line.backingWords)
            let rMain = mainPair.text ?? romanize(line.mainText, preferJapanese: songHasKana)
            let rBack = backPair.text ?? line.backingText.map { romanize($0, preferJapanese: songHasKana) }

            return LyricLine(
                time: line.time,
                endTime: line.endTime,
                backingTime: line.backingTime,
                backingEndTime: line.backingEndTime,
                mainText: rMain,
                backingText: rBack,
                backingIsSuffix: line.backingIsSuffix,
                words: mainPair.words,
                backingWords: backPair.words
            )
        }
    }

    private static func containsCJK(_ text: String) -> Bool {
        return text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
        }
    }

    private static func cfTransform(_ s: String, transform: CFString) -> String {
        let mutable = NSMutableString(string: s)
        CFStringTransform(mutable, nil, transform, false)
        return mutable as String
    }

    private static func romanizeJapanese(_ text: String) -> String {
        let cfStr = text as CFString
        let range = CFRangeMake(0, CFStringGetLength(cfStr))
        let locale = Locale(identifier: "ja") as CFLocale
        let tokenizer = CFStringTokenizerCreate(nil, cfStr, range, kCFStringTokenizerUnitWord, locale)

        var out = ""
        var lastEnd = 0
        let ns = text as NSString

        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let tokRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            if tokRange.location > lastEnd {
                let gap = ns.substring(with: NSRange(location: lastEnd, length: tokRange.location - lastEnd))
                out += gap
            }

            let rawTok = ns.substring(with: NSRange(location: tokRange.location, length: tokRange.length))
            let tokenLatin: String
            if let attr = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String {
                tokenLatin = cfTransform(attr, transform: kCFStringTransformStripDiacritics)
            } else {
                let l = cfTransform(rawTok, transform: kCFStringTransformToLatin)
                tokenLatin = cfTransform(l, transform: kCFStringTransformStripDiacritics)
            }

            let cleanedTok = cleanSokuon(tokenLatin)
            if needsRomanization(rawTok) {
                if let last = out.last, (last.isLetter || last.isNumber),
                   let first = cleanedTok.first, (first.isLetter || first.isNumber) {
                    out += " "
                }
            }
            out += cleanedTok
            lastEnd = tokRange.location + tokRange.length
        }

        if lastEnd < ns.length {
            out += ns.substring(from: lastEnd)
        }
        return normalizeSpacing(out)
    }

    private static func cleanSokuon(_ token: String) -> String {
        // Apple's Japanese tokenizer emits "~tsu" before doubled consonants (e.g. "shi~tsuta" -> "shitta")
        var s = token
        if let regex = try? NSRegularExpression(pattern: #"~tsu([bcdfghjklmnpqrstvwxyz])"#, options: .caseInsensitive) {
            s = regex.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: "$1$1")
        }
        return s.replacingOccurrences(of: "~", with: "")
    }

    private static func normalizeSpacing(_ text: String) -> String {
        var s = text.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\(\s+"#, with: "(", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+\)"#, with: ")", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+([,\.!?])"#, with: "$1", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Dynamic Song Artwork Color Palette & WCAG AA Guard

struct SongColorPalette: Equatable {
    let accent: NSColor
    let backingAccent: NSColor
    let surfaceTint: NSColor
}

enum ArtworkPaletteExtractor {
    static func extract(from base64OrData: Data) -> SongColorPalette? {
        // Downsample at decode time: covers are often 1400x1400 and we only
        // need a 32x32 color histogram.
        guard let source = CGImageSourceCreateWithData(base64OrData as CFData, nil) else {
            return nil
        }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 48
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbOptions as CFDictionary
        ) else {
            return nil
        }

        let size = 32
        let bytesPerRow = size * 4
        var pixels = [UInt8](repeating: 0, count: size * bytesPerRow)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: &pixels,
                width: size,
                height: size,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        ctx.interpolationQuality = .medium
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        // 12 hue buckets to find vibrant dominant theme color without washed grays
        struct Bucket {
            var rSum: CGFloat = 0
            var gSum: CGFloat = 0
            var bSum: CGFloat = 0
            var weight: CGFloat = 0
        }
        var buckets = Array(repeating: Bucket(), count: 12)
        var fallbackR: CGFloat = 0, fallbackG: CGFloat = 0, fallbackB: CGFloat = 0, fallbackW: CGFloat = 0

        for i in stride(from: 0, to: pixels.count, by: 4) {
            let a = CGFloat(pixels[i + 3]) / 255.0
            if a < 0.5 { continue }
            let r = CGFloat(pixels[i]) / 255.0
            let g = CGFloat(pixels[i + 1]) / 255.0
            let b = CGFloat(pixels[i + 2]) / 255.0

            let cMax = max(r, g, b)
            let cMin = min(r, g, b)
            let delta = cMax - cMin
            let sat = cMax > 0.01 ? (delta / cMax) : 0
            let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b

            fallbackR += r; fallbackG += g; fallbackB += b; fallbackW += 1

            // Skip near-black / near-white / gray background pixels for accent scoring
            if sat < 0.22 || lum < 0.08 || lum > 0.90 { continue }

            var hue: CGFloat = 0
            if delta > 0.001 {
                if cMax == r {
                    hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
                } else if cMax == g {
                    hue = ((b - r) / delta) + 2
                } else {
                    hue = ((r - g) / delta) + 4
                }
                hue /= 6.0
                if hue < 0 { hue += 1.0 }
            }

            let idx = min(11, max(0, Int(hue * 12.0)))
            let w = sat * sat * (0.4 + 0.6 * sin(min(1, max(0, lum)) * .pi))
            buckets[idx].rSum += r * w
            buckets[idx].gSum += g * w
            buckets[idx].bSum += b * w
            buckets[idx].weight += w
        }

        let sorted = buckets.enumerated()
            .filter { $0.element.weight > 0.05 }
            .sorted { $0.element.weight > $1.element.weight }

        let primary: NSColor
        if let best = sorted.first?.element {
            primary = NSColor(
                srgbRed: best.rSum / best.weight,
                green: best.gSum / best.weight,
                blue: best.bSum / best.weight,
                alpha: 1.0
            )
        } else if fallbackW > 0 {
            primary = NSColor(
                srgbRed: fallbackR / fallbackW,
                green: fallbackG / fallbackW,
                blue: fallbackB / fallbackW,
                alpha: 1.0
            )
        } else {
            return nil
        }

        // Pick secondary bucket separated in hue by >= 2 bins if available, else hue-shift 35 deg
        let secondary: NSColor
        if let firstIdx = sorted.first?.offset,
           let alt = sorted.dropFirst().first(where: {
               let dist = abs($0.offset - firstIdx)
               return min(dist, 12 - dist) >= 2 && $0.element.weight > (sorted[0].element.weight * 0.28)
           })?.element {
            secondary = NSColor(
                srgbRed: alt.rSum / alt.weight,
                green: alt.gSum / alt.weight,
                blue: alt.bSum / alt.weight,
                alpha: 1.0
            )
        } else {
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
            primary.usingColorSpace(.sRGB)?.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            let shiftedHue = (h + 0.09).truncatingRemainder(dividingBy: 1.0)
            secondary = NSColor(hue: shiftedHue, saturation: max(0.35, min(0.85, s * 0.9)), brightness: min(0.95, max(0.55, b)), alpha: 1.0)
        }

        return SongColorPalette(
            accent: primary,
            backingAccent: secondary,
            surfaceTint: primary
        )
    }
}

extension NSColor {
    func blended(with other: NSColor, fraction: CGFloat) -> NSColor {
        let f = min(max(fraction, 0), 1)
        let c1 = self.usingColorSpace(.sRGB) ?? self
        let c2 = other.usingColorSpace(.sRGB) ?? other
        return NSColor(
            srgbRed: c1.redComponent + (c2.redComponent - c1.redComponent) * f,
            green: c1.greenComponent + (c2.greenComponent - c1.greenComponent) * f,
            blue: c1.blueComponent + (c2.blueComponent - c1.blueComponent) * f,
            alpha: c1.alphaComponent + (c2.alphaComponent - c1.alphaComponent) * f
        )
    }

    func ensuringContrast(against background: NSColor, minRatio: CGFloat = 4.5) -> NSColor {
        if self.contrastRatio(with: background) >= minRatio {
            return self
        }
        let bgLum = background.relativeLuminance
        let target: NSColor = bgLum < 0.35
            ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
            : NSColor(srgbRed: 0.06, green: 0.06, blue: 0.07, alpha: 1)

        var lo: CGFloat = 0
        var hi: CGFloat = 1
        var best = target
        for _ in 0..<10 {
            let mid = 0.5 * (lo + hi)
            let candidate = self.blended(with: target, fraction: mid)
            if candidate.contrastRatio(with: background) >= minRatio {
                best = candidate
                hi = mid
            } else {
                lo = mid
            }
        }
        return best
    }
}
