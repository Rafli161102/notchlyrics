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

    static func isRTLScript(_ text: String) -> Bool {
        return text.unicodeScalars.contains { scalar in
            let v = scalar.value
            return (0x0590...0x05FF).contains(v)
                || (0x0600...0x06FF).contains(v)
                || (0x0750...0x077F).contains(v)
                || (0x08A0...0x08FF).contains(v)
        }
    }

    /// Arabic/Hebrew RTL, Thai, and Indic/Devanagari scripts rely on cross-glyph ligatures & diacritic stacking;
    /// breaking attributes per character destroys cursive joining, so renderers must group by word/cluster.
    static func requiresClusterGrouping(_ text: String) -> Bool {
        if isRTLScript(text) { return true }
        return text.unicodeScalars.contains { scalar in
            let v = scalar.value
            return (0x0900...0x0DFF).contains(v) || (0x0E00...0x0E7F).contains(v)
        }
    }

    static func containsHangul(_ text: String) -> Bool {
        return text.unicodeScalars.contains { scalar in
            let v = scalar.value
            return (0xAC00...0xD7AF).contains(v) || (0x1100...0x11FF).contains(v) || (0x3130...0x318F).contains(v)
        }
    }

    static func containsCyrillic(_ text: String) -> Bool {
        return text.unicodeScalars.contains { scalar in
            (0x0400...0x04FF).contains(scalar.value)
        }
    }

    static func romanize(_ text: String, preferJapanese: Bool = false) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, needsRomanization(trimmed) else { return text }

        let treatAsJapanese = containsJapaneseKana(trimmed) || (preferJapanese && containsCJK(trimmed))
        if treatAsJapanese {
            return romanizeJapanese(trimmed)
        }

        if containsHangul(trimmed) {
            return romanizeKoreanHangul(trimmed)
        }

        let isRussian = containsCyrillic(trimmed)

        var latin = cfTransform(trimmed, transform: kCFStringTransformToLatin)
        latin = cleanPhoneticMarkers(latin, isKorean: false, isCyrillic: isRussian)
        let clean = cfTransform(latin, transform: kCFStringTransformStripDiacritics)
        let strippedMods = clean.replacingOccurrences(
            of: "[\u{02B9}\u{02BA}\u{02BC}\u{02BD}\u{02BE}\u{02BF}-]",
            with: "",
            options: .regularExpression
        )
        return normalizeSpacing(strippedMods)
    }

    private static func romanizeKoreanHangul(_ text: String) -> String {
        let initials = ["g", "kk", "n", "d", "tt", "r", "m", "b", "pp", "s", "ss", "", "j", "jj", "ch", "k", "t", "p", "h"]
        let medials = ["a", "ae", "ya", "yae", "eo", "e", "yeo", "ye", "o", "wa", "wae", "oe", "yo", "u", "wo", "we", "wi", "yu", "eu", "ui", "i"]
        let finals = ["", "k", "k", "k", "n", "n", "n", "t", "l", "k", "m", "b", "l", "t", "p", "l", "m", "p", "p", "t", "t", "ng", "t", "t", "k", "t", "p", "t"]
        let liaisonCoda = ["", "g", "kk", "ks", "n", "nj", "n", "d", "r", "lg", "lm", "lb", "ls", "lt", "lp", "r", "m", "b", "bs", "s", "ss", "ng", "j", "ch", "k", "t", "p", ""]

        let scalars = Array(text.unicodeScalars)
        var out = ""
        var i = 0
        var prevFinalIdx = 0

        while i < scalars.count {
            let v = scalars[i].value
            if (0xAC00...0xD7A3).contains(v) {
                let sIdx = Int(v - 0xAC00)
                let lIdx = sIdx / 588
                let vIdx = (sIdx % 588) / 28
                let fIdx = sIdx % 28

                var onset = initials[lIdx]
                // ㄹ preceded by coda ㄹ assimilates as lateral "ll" (e.g. 빨리 -> ppalli)
                if lIdx == 5 && prevFinalIdx == 8 {
                    onset = "l"
                }

                // Look ahead to next scalar to apply smooth Korean consonant liaison before ㅇ + vowel
                var finalStr = finals[fIdx]
                if fIdx > 0 && fIdx != 21 && i + 1 < scalars.count {
                    let nextV = scalars[i + 1].value
                    if (0xAC00...0xD7A3).contains(nextV) {
                        let nextL = Int(nextV - 0xAC00) / 588
                        if nextL == 11 {
                            if fIdx == 17 && (lIdx == 9 || lIdx == 10 || lIdx == 12) {
                                // 싶은 / 싶어 common lyrical form -> sipeo
                                finalStr = "p"
                            } else {
                                finalStr = liaisonCoda[fIdx]
                            }
                        } else if nextL == 18 && (fIdx == 1 || fIdx == 7 || fIdx == 12 || fIdx == 17) {
                            // Aspirated fusion (ㄱ/ㄷ/ㅂ + ㅎ -> kh/th/ph)
                            finalStr = liaisonCoda[fIdx]
                        }
                    }
                }

                out += onset + medials[vIdx] + finalStr
                prevFinalIdx = fIdx
                i += 1
            } else {
                prevFinalIdx = 0
                let chStr = String(scalars[i])
                if needsRomanization(chStr) {
                    let t = cfTransform(chStr, transform: kCFStringTransformToLatin)
                    out += cfTransform(t, transform: kCFStringTransformStripDiacritics)
                } else {
                    out += chStr
                }
                i += 1
            }
        }
        return normalizeSpacing(out)
    }

    private static func cleanPhoneticMarkers(_ latin: String, isKorean: Bool, isCyrillic: Bool) -> String {
        var s = latin
        if isCyrillic {
            let cyrillicMap: [(String, String)] = [
                ("û", "yu"), ("Û", "Yu"),
                ("â", "ya"), ("Â", "Ya"),
                ("ŝ", "shch"), ("Ŝ", "Shch"),
                ("š", "sh"), ("Š", "Sh"),
                ("č", "ch"), ("Č", "Ch"),
                ("ž", "zh"), ("Ž", "Zh"),
                ("ë", "yo"), ("Ë", "Yo")
            ]
            for (k, v) in cyrillicMap {
                s = s.replacingOccurrences(of: k, with: v)
            }
        }
        if isKorean {
            s = s.replacingOccurrences(of: "ŏ", with: "eo").replacingOccurrences(of: "Ŏ", with: "Eo")
            s = s.replacingOccurrences(of: "ŭ", with: "u").replacingOccurrences(of: "Ŭ", with: "U")
            s = s.replacingOccurrences(of: "-", with: "")
            s = s.replacingOccurrences(of: "gh", with: "kh")
        }
        return s
    }

    static func romanizeLines(_ lines: [LyricLine], titleHint: String = "", artistHint: String = "") -> [LyricLine] {
        let songHasKana = containsJapaneseKana(titleHint)
            || containsJapaneseKana(artistHint)
            || lines.contains { containsJapaneseKana($0.mainText) || containsJapaneseKana($0.backingText ?? "") }

        func romanizeWordsList(_ srcWords: [LyricWord], fullLineText: String) -> (text: String?, words: [LyricWord]) {
            guard !srcWords.isEmpty else { return (nil, []) }
            let jpContextReadings: [String: String] = songHasKana ? buildJapaneseTokenMap(fullLineText) : [:]
            var outWords: [LyricWord] = []
            var combined = ""
            var pendingDoubleNext = false

            for (idx, w) in srcWords.enumerated() {
                let rawTrim = w.text.trimmingCharacters(in: .whitespacesAndNewlines)

                // Handle isolated YRC sokuon ("っ"/"ッ") or choonpu ("ー") split across character timings
                if songHasKana && (rawTrim == "っ" || rawTrim == "ッ") {
                    pendingDoubleNext = true
                    if !outWords.isEmpty {
                        outWords[outWords.count - 1] = LyricWord(
                            time: outWords[outWords.count - 1].time,
                            duration: outWords[outWords.count - 1].duration + w.duration,
                            text: outWords[outWords.count - 1].text
                        )
                    }
                    continue
                }
                if songHasKana && rawTrim == "ー" && !combined.isEmpty {
                    let prevLast = combined.last!
                    if "aeiou".contains(prevLast) {
                        let ext = String(prevLast)
                        combined += ext
                        outWords.append(LyricWord(time: w.time, duration: w.duration, text: ext))
                    }
                    continue
                }

                var piece: String
                if rawTrim.isEmpty {
                    piece = ""
                } else if songHasKana, let ctxReading = jpContextReadings[rawTrim], !ctxReading.isEmpty {
                    piece = ctxReading
                } else {
                    piece = romanize(rawTrim, preferJapanese: songHasKana)
                }

                if pendingDoubleNext && !piece.isEmpty {
                    if let first = piece.first, "bcdfghjklmnpqrstvwxyz".contains(first.lowercased()) {
                        let doubled = (first == "c" || first == "C") ? "t" : String(first)
                        piece = doubled + piece
                        pendingDoubleNext = false
                    }
                }
                if piece.isEmpty && !w.text.isEmpty {
                    piece = w.text
                }
                if songHasKana && rawTrim.hasSuffix("っ") && idx + 1 < srcWords.count {
                    // Already converted inside romanize if complete; clean stray tsu suffix at boundary
                    if piece.hasSuffix("tsu") && piece.count > 3 {
                        piece = String(piece.dropLast(3))
                        pendingDoubleNext = true
                    }
                }

                let wasDoubledJoin = !combined.isEmpty && piece.count >= 2
                    && outWords.last != nil
                    && idx > 0
                    && srcWords[idx - 1].text.trimmingCharacters(in: .whitespacesAndNewlines) == "っ"
                let needsSpace = !combined.isEmpty
                    && !wasDoubledJoin
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
            let mainPair = romanizeWordsList(line.words, fullLineText: line.mainText)
            let backPair = romanizeWordsList(line.backingWords, fullLineText: line.backingText ?? "")
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

    private static func expandJapaneseMacrons(_ text: String, hasChoonpu: Bool) -> String {
        var s = text
        if hasChoonpu {
            s = s.replacingOccurrences(of: "ō", with: "oo").replacingOccurrences(of: "Ō", with: "Oo")
            s = s.replacingOccurrences(of: "ū", with: "uu").replacingOccurrences(of: "Ū", with: "Uu")
            s = s.replacingOccurrences(of: "ē", with: "ee").replacingOccurrences(of: "Ē", with: "Ee")
            s = s.replacingOccurrences(of: "ī", with: "ii").replacingOccurrences(of: "Ī", with: "Ii")
            s = s.replacingOccurrences(of: "ā", with: "aa").replacingOccurrences(of: "Ā", with: "Aa")
        } else {
            s = s.replacingOccurrences(of: "ō", with: "ou").replacingOccurrences(of: "Ō", with: "Ou")
            s = s.replacingOccurrences(of: "ū", with: "uu").replacingOccurrences(of: "Ū", with: "Uu")
            s = s.replacingOccurrences(of: "ē", with: "ei").replacingOccurrences(of: "Ē", with: "Ei")
            s = s.replacingOccurrences(of: "ī", with: "ii").replacingOccurrences(of: "Ī", with: "Ii")
            s = s.replacingOccurrences(of: "ā", with: "aa").replacingOccurrences(of: "Ā", with: "Aa")
        }
        return cfTransform(s, transform: kCFStringTransformStripDiacritics)
    }

    private static func transcribeJapaneseToken(rawTok: String, tokenizer: CFStringTokenizer) -> String {
        if rawTok == "は" { return "wa" }
        if rawTok == "へ" { return "e" }
        if rawTok == "を" { return "o" }
        let rawLatin: String
        if let attr = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String {
            rawLatin = attr
        } else {
            rawLatin = cfTransform(rawTok, transform: kCFStringTransformToLatin)
        }
        let expanded = expandJapaneseMacrons(rawLatin, hasChoonpu: rawTok.contains("ー"))
        return expanded
    }

    private static func buildJapaneseTokenMap(_ text: String) -> [String: String] {
        guard !text.isEmpty, needsRomanization(text) else { return [:] }
        let cfStr = text as CFString
        let range = CFRangeMake(0, CFStringGetLength(cfStr))
        let locale = Locale(identifier: "ja") as CFLocale
        guard let tokenizer = CFStringTokenizerCreate(nil, cfStr, range, kCFStringTokenizerUnitWord, locale) else { return [:] }
        let ns = text as NSString
        var rawTokens: [(raw: String, latin: String)] = []

        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let tokRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let rawTok = ns.substring(with: NSRange(location: tokRange.location, length: tokRange.length))
            guard !rawTok.isEmpty, needsRomanization(rawTok) else { continue }
            rawTokens.append((rawTok, transcribeJapaneseToken(rawTok: rawTok, tokenizer: tokenizer)))
        }

        var map: [String: String] = [:]
        for idx in 0..<rawTokens.count {
            let cur = rawTokens[idx]
            var cleaned = cleanSokuon(cur.latin)
            if cur.latin.hasSuffix("~tsu") && idx + 1 < rawTokens.count {
                let nextCleaned = cleanSokuon(rawTokens[idx + 1].latin)
                if let first = nextCleaned.first, "bcdfghjklmnpqrstvwxyz".contains(first.lowercased()) {
                    cleaned = String(cur.latin.dropLast(4))
                    if cur.raw.hasSuffix("っ") || cur.raw.hasSuffix("ッ") {
                        let stemKey = String(cur.raw.dropLast())
                        if !stemKey.isEmpty && map[stemKey] == nil {
                            map[stemKey] = cleaned
                        }
                    }
                }
            }
            if !cleaned.isEmpty && map[cur.raw] == nil {
                map[cur.raw] = cleaned
            }
        }
        return map
    }

    private static func romanizeJapanese(_ text: String) -> String {
        let cfStr = text as CFString
        let range = CFRangeMake(0, CFStringGetLength(cfStr))
        let locale = Locale(identifier: "ja") as CFLocale
        guard let tokenizer = CFStringTokenizerCreate(nil, cfStr, range, kCFStringTokenizerUnitWord, locale) else { return text }

        var out = ""
        var lastEnd = 0
        var pendingSokuon = false
        var prevRawTok = ""
        let ns = text as NSString
        let verbSuffixes: Set<String> = ["て", "た", "で", "ます", "ました", "ません", "ない", "なかった", "たい"]
        let standaloneParticles: Set<String> = ["は", "が", "を", "に", "へ", "と", "の", "も", "か", "や"]

        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let tokRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let hadGap = tokRange.location > lastEnd
            if hadGap {
                let gap = ns.substring(with: NSRange(location: lastEnd, length: tokRange.location - lastEnd))
                out += gap
                pendingSokuon = false
                prevRawTok = ""
            }

            let rawTok = ns.substring(with: NSRange(location: tokRange.location, length: tokRange.length))
            var tokenLatin = transcribeJapaneseToken(rawTok: rawTok, tokenizer: tokenizer)

            var willPendSokuon = false
            if tokenLatin.hasSuffix("~tsu") || rawTok.hasSuffix("っ") || rawTok.hasSuffix("ッ") {
                if tokenLatin.hasSuffix("~tsu") {
                    tokenLatin = String(tokenLatin.dropLast(4))
                    willPendSokuon = true
                }
            }

            var cleanedTok = cleanSokuon(tokenLatin)
            var joinedWithoutSpace = false
            if pendingSokuon, let first = cleanedTok.first, "bcdfghjklmnpqrstvwxyz".contains(first.lowercased()) {
                let dbl = (first == "c" || first == "C") ? "t" : String(first)
                cleanedTok = dbl + cleanedTok
                joinedWithoutSpace = true
            } else if !hadGap && !prevRawTok.isEmpty && !standaloneParticles.contains(prevRawTok) {
                if verbSuffixes.contains(rawTok) || (prevRawTok == "い" && rawTok == "た") || (prevRawTok == "て" && rawTok == "い") {
                    if !(prevRawTok == "て" && rawTok == "い") {
                        joinedWithoutSpace = true
                    }
                }
            }
            pendingSokuon = willPendSokuon
            prevRawTok = rawTok

            if needsRomanization(rawTok) && !joinedWithoutSpace {
                if let last = out.last, (last.isLetter || last.isNumber),
                   let first = cleanedTok.first, (first.isLetter || first.isNumber) {
                    out += " "
                }
            }
            out += cleanedTok
            lastEnd = tokRange.location + tokRange.length
        }

        if pendingSokuon {
            out += "tsu"
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
