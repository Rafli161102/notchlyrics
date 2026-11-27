import Cocoa
import Foundation

@main
enum CoreEngineTests {
    static var failures = 0

    static func check(_ cond: Bool, _ name: String) {
        if cond {
            print("PASS \(name)")
        } else {
            failures += 1
            print("FAIL \(name)")
        }
    }

    static func main() {
        // 1. Strict Title + Artist + Variant Rejection Tests
        let fetcher = LyricsParserAndFetcher()
        check(fetcher.cleanTitle("YOASOBI「夜に駆ける」Official Music Video") == "夜に駆ける", "cleanTitle extracts Japanese quoted title")
        check(fetcher.cleanArtist("Hindia - Topic") == "Hindia", "cleanArtist strips - Topic")

        let origScore = LyricsParserAndFetcher.scoreCandidate(
            trackName: "Wish You Were Here",
            artistName: "Neck Deep",
            rawInputTitle: "Wish You Were Here",
            expectedTitle: "Wish You Were Here",
            expectedArtist: "Neck Deep",
            refDuration: 248.2,
            targetDuration: 248.3,
            hasSynced: true,
            hasWordTimings: true
        )
        let wrongArtistScore = LyricsParserAndFetcher.scoreCandidate(
            trackName: "Wish You Were Here",
            artistName: "Pink Floyd",
            rawInputTitle: "Wish You Were Here",
            expectedTitle: "Wish You Were Here",
            expectedArtist: "Neck Deep",
            refDuration: 248.2,
            targetDuration: 248.3,
            hasSynced: true,
            hasWordTimings: true
        )
        let remixPenaltyScore = LyricsParserAndFetcher.scoreCandidate(
            trackName: "Wish You Were Here (Sped Up)",
            artistName: "Neck Deep",
            rawInputTitle: "Wish You Were Here",
            expectedTitle: "Wish You Were Here",
            expectedArtist: "Neck Deep",
            refDuration: 248.2,
            targetDuration: 248.3,
            hasSynced: true,
            hasWordTimings: false
        )
        check(origScore > wrongArtistScore + 40, "exact artist dominates wrong artist match")
        check(origScore > remixPenaltyScore + 35, "original version dominates unwanted Sped Up remix")

        // 2. YRC & LRC Backing Vocal Sync + Speed Scale Tests
        let cr = LyricsParserAndFetcher.synthesizeWordTimings(for: LyricsParserAndFetcher.parseLRC("""
        [00:10.00]Say it again (say it again)
        [00:16.00]Next
        """))
        check((cr[0].backingTime ?? 0) > 10.4, "inline suffix backing enters after main phrase")

        let slowP = cr[0].singingProgress(at: 11.1, nextLineTime: 16.0, wordSpeedScale: 0.65)
        let fastP = cr[0].singingProgress(at: 11.1, nextLineTime: 16.0, wordSpeedScale: 1.75)
        check(slowP < fastP, "wordSpeedScale adjusts karaoke speed cleanly")

        // 3. Romanization preserving YRC words
        let jpYrc = LyricsParserAndFetcher.parseYRC("[1000,2000](1000,800,0)夜(1800,400,0)に(2200,800,0)駆ける")
        let rom = TextRomanizer.romanizeLines(jpYrc, titleHint: "夜に駆ける", artistHint: "YOASOBI")
        check(!rom[0].words.isEmpty && rom[0].mainText.lowercased().contains("yoru"), "YRC words survive Japanese romanization")

        // 4. Cross-script & Line-Coverage Scoring Tests
        let crossScript = LyricsParserAndFetcher.scoreCandidate(
            trackName: "夜に駆ける",
            artistName: "YOASOBI",
            rawInputTitle: "YOASOBI - Yoru ni Kakeru",
            expectedTitle: "Yoru ni Kakeru",
            expectedArtist: "YOASOBI",
            refDuration: 248.0,
            targetDuration: 248.4,
            hasSynced: true,
            hasWordTimings: false
        )
        check(crossScript >= 145, "cross-script Japanese Kanji title matches romanized query")

        let stubLines = [LyricLine(time: 0, mainText: "Instrumental", backingText: nil)]
        let fullLines = (0..<12).map { LyricLine(time: Double($0) * 18.0, mainText: "Line \($0)", backingText: nil) }
        let stubScore = LyricsParserAndFetcher.scoreCandidate(
            trackName: "Track", artistName: "Artist", rawInputTitle: "Track",
            expectedTitle: "Track", expectedArtist: "Artist",
            refDuration: 210, targetDuration: 210, hasSynced: true, hasWordTimings: false, parsedLines: stubLines
        )
        let fullScore = LyricsParserAndFetcher.scoreCandidate(
            trackName: "Track", artistName: "Artist", rawInputTitle: "Track",
            expectedTitle: "Track", expectedArtist: "Artist",
            refDuration: 210, targetDuration: 210, hasSynced: true, hasWordTimings: false, parsedLines: fullLines
        )
        check(fullScore > stubScore + 60, "complete synced lyrics dominate 1-line stub placeholder")

        // 5. Persistent Disk Cache & Offset Calibration Roundtrip Test
        let tmpCacheDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("tbl_test_\(UUID().uuidString)")
        let disk = DiskLyricsCache(directory: tmpCacheDir)
        let sampleRes = FetchedLyricsResult(
            lines: fullLines,
            sourceName: "LRCLIB",
            isEstimated: false,
            hasWordTimings: false,
            referenceDuration: 210,
            calibratedLeadOffset: 0.35,
            calibratedBackingOffset: -0.20,
            cachedBPM: 128
        )
        disk.save(sampleRes, cacheKey: "track|artist|210", fuzzyKey: "track|artist")
        // Give async background save brief flush window
        Thread.sleep(forTimeInterval: 0.12)
        let reloaded = disk.load(cacheKey: "track|artist|210", fuzzyKey: "track|artist", targetDuration: 210)
        check(reloaded != nil && reloaded!.lines.count == 12, "disk cache restores saved track lyrics")
        check(abs((reloaded?.calibratedLeadOffset ?? 0) - 0.35) < 0.01 && abs((reloaded?.calibratedBackingOffset ?? 0) + 0.20) < 0.01, "disk cache restores calibrated lead & backing offsets")
        check(reloaded?.sourceName == "LRCLIB • Cache", "disk cache tags source cleanly")
        try? FileManager.default.removeItem(atPath: tmpCacheDir)

        // 6. Built-in WCAG AA contrast & Codable schema roundtrip
        for theme in TouchBarTheme.builtInThemes {
            let bg = NSColor(hex: theme.backgroundHex)
            check(NSColor(hex: theme.mainTextHex).contrastRatio(with: bg) >= 4.5, "WCAG mainText >= 4.5 for \(theme.name)")
            check(NSColor(hex: theme.backingTextHex).contrastRatio(with: bg) >= 4.5, "WCAG backingText >= 4.5 for \(theme.name)")
        }

        // 7. Pure OLED Black Background Preservation + Album-Tinted Text + Hover Time Formatting
        let vibrantPalette = SongColorPalette(
            accent: NSColor(calibratedRed: 0.25, green: 0.85, blue: 0.95, alpha: 1.0),
            backingAccent: NSColor(calibratedRed: 0.98, green: 0.65, blue: 0.20, alpha: 1.0),
            surfaceTint: NSColor(calibratedRed: 0.90, green: 0.18, blue: 0.28, alpha: 1.0)
        )
        var oledTheme = TouchBarTheme.builtInThemes.first { $0.backgroundHex == "#000000" } ?? TouchBarTheme.builtInThemes[0]
        oledTheme.colorSyncMode = .vividArtwork
        let view = TouchBarLyricsView {}
        view.applyTheme(oledTheme)
        view.update(
            trackTitle: "Test Track",
            mainText: "Pure OLED Lyrics",
            backingText: "Ooh",
            songProgress: 0.4,
            lineProgress: 0.5,
            backingLineProgress: 0.5,
            vocalEnergy: 0.85,
            backingVocalEnergy: 0.60,
            isPlaying: true,
            isVocalSynced: true,
            songPalette: vibrantPalette
        )
        if let renderedBg = view.renderedBackgroundColor?.usingColorSpace(.deviceRGB) {
            check(
                renderedBg.redComponent < 0.005 && renderedBg.greenComponent < 0.005 && renderedBg.blueComponent < 0.005,
                "OLED #000000 background stays pure black even with vivid artwork palette"
            )
            if let renderedText = view.renderedMainTextColor?.usingColorSpace(.deviceRGB) {
                check(
                    renderedText.contrastRatio(with: renderedBg) >= 4.5 && renderedText.redComponent < 0.95,
                    "album palette colors lyrics text while preserving WCAG contrast on OLED black"
                )
            } else {
                check(false, "renderedMainTextColor populated for active lyrics")
            }
        } else {
            check(false, "renderedBackgroundColor populated")
        }

        if let paperLight = TouchBarTheme.builtInThemes.first(where: { $0.backgroundHex.uppercased() == "#EAE5DC" }) {
            var lightTheme = paperLight
            lightTheme.colorSyncMode = .vividArtwork
            let lightView = TouchBarLyricsView {}
            lightView.applyTheme(lightTheme)
            lightView.update(
                trackTitle: "Light Track",
                mainText: "Paper Light",
                backingText: nil,
                songProgress: 0.2,
                lineProgress: 0.4,
                backingLineProgress: nil,
                vocalEnergy: 0.8,
                backingVocalEnergy: 0.2,
                isPlaying: true,
                isVocalSynced: false,
                songPalette: vibrantPalette
            )
            let baseLight = NSColor(hex: paperLight.backgroundHex).usingColorSpace(.deviceRGB)!
            if let renderedLight = lightView.renderedBackgroundColor?.usingColorSpace(.deviceRGB) {
                let delta = abs(renderedLight.redComponent - baseLight.redComponent)
                    + abs(renderedLight.greenComponent - baseLight.greenComponent)
                    + abs(renderedLight.blueComponent - baseLight.blueComponent)
                check(delta > 0.01, "non-black light theme keeps subtle album background tint")
            } else {
                check(false, "light renderedBackgroundColor populated")
            }
        }

        check(NotchLyricsWindowController.formatTimePair(elapsed: 84, duration: 248) == "01:24 / 04:08", "hover time formats MM:SS / MM:SS cleanly")
        check(NotchLyricsWindowController.formatTimePair(elapsed: 3909, duration: 6300) == "1:05:09 / 1:45:00", "hover time formats H:MM:SS for long mixes")
        check(NotchLyricsWindowController.formatTimePair(elapsed: -5, duration: 0) == "00:00", "hover time clamps negative elapsed and omits missing duration")
        check(NotchLyricsWindowController.formatTimePair(elapsed: 300, duration: 200) == "03:20 / 03:20", "hover time clamps elapsed to song duration")

        // 8. Notch Multi-Line Zero-Truncation Auto-Fit + Enhanced Matching Accuracy
        let longNotchLyric = "And when the night feels endless across the quiet city lights we still keep singing together until the morning sun arrives"
        let fittedSize = TouchBarLyricsView.fittedFontSize(
            text: longNotchLyric,
            targetSize: 13.5,
            minSize: 9.5,
            weight: .bold,
            fontStyle: .rounded,
            maxWidth: 312,
            maxHeight: 40
        )
        let measurePara = NSMutableParagraphStyle()
        measurePara.lineBreakMode = .byWordWrapping
        measurePara.lineSpacing = 1.0
        let fittedRect = (longNotchLyric as NSString).boundingRect(
            with: NSSize(width: 312, height: 400),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: ThemeFontStyle.rounded.font(size: fittedSize, weight: .bold), .paragraphStyle: measurePara]
        )
        check(fittedSize <= 13.5 && ceil(fittedRect.height) <= 40.0, "long lyric scales cleanly inside Notch bounds without truncation (fitted=\(fittedSize)pt height=\(ceil(fittedRect.height)))")

        let enDashCleaned = fetcher.cleanTitle("Tulus \u{2013} Hati-Hati di Jalan - Official Music Video")
        check(enDashCleaned == "Tulus - Hati-Hati di Jalan", "normalizes en-dash separator and strips unparenthesized video noise")

        let resolvedPair = fetcher.resolveExpectedTitleArtist(rawTitle: "Tulus \u{2013} Hati-Hati di Jalan (Official Video)", rawArtist: "Musica Studios")
        check(resolvedPair.title == "Hati-Hati di Jalan" && resolvedPair.artist == "Tulus", "extracts true title & artist when YouTube channel differs")

        let queryPairs = fetcher.buildQueryCandidates(rawTitle: "Tulus - Hati-Hati di Jalan", rawArtist: "Musica Studios")
        check(queryPairs.contains(where: { $0.track == "Hati-Hati di Jalan" && $0.artist == "Tulus" }), "query builder prioritizes parsed artist+title pair")

        let unrelatedTrackScore = LyricsParserAndFetcher.scoreCandidate(
            trackName: "Completely Different Song",
            artistName: "Tulus",
            rawInputTitle: "Hati-Hati di Jalan",
            expectedTitle: "Hati-Hati di Jalan",
            expectedArtist: "Tulus",
            refDuration: 242,
            targetDuration: 242,
            hasSynced: true,
            hasWordTimings: false
        )
        check(unrelatedTrackScore < 65.0, "zero title overlap is rejected below 65.0 even when artist and duration match")

        // 9. All-Language Script Romanization & Cluster-Safe Transitions
        let ruRom = TextRomanizer.romanize("Привет мир любовь")
        check(ruRom == "Privet mir lyubov", "Russian Cyrillic romanizes cleanly without soft-sign symbols (\(ruRom))")

        let koRom = TextRomanizer.romanize("어떡해 보고 싶어")
        check(koRom.contains("bogo sipeo") && !koRom.contains("-"), "Korean Hangul removes syllable hyphens cleanly (\(koRom))")

        let zhRom = TextRomanizer.romanize("月亮代表我的心")
        check(zhRom.lowercased().contains("yue") && zhRom.lowercased().contains("xin"), "Chinese Mandarin romanizes cleanly (\(zhRom))")

        let arText = "حبيبي يا نور العين"
        check(TextRomanizer.isRTLScript(arText) && TextRomanizer.requiresClusterGrouping(arText), "detects Arabic RTL script and requires ligature preservation")
        check(TextRomanizer.requiresClusterGrouping("तुम ही हो") && TextRomanizer.requiresClusterGrouping("คิดถึงเธอ"), "preserves ligature clusters for Hindi Devanagari and Thai")

        let rtlView = TouchBarLyricsView {}
        var rtlTheme = TouchBarTheme.builtInThemes[0]
        rtlTheme.wordAnimation = .karaokeLift
        rtlView.applyTheme(rtlTheme)
        rtlView.update(
            trackTitle: "Arabic Song",
            mainText: arText,
            backingText: nil,
            songProgress: 0.3,
            lineProgress: 0.5,
            backingLineProgress: nil,
            vocalEnergy: 0.7,
            backingVocalEnergy: 0.4,
            isPlaying: true,
            isVocalSynced: false
        )
        let attrOut = rtlView.renderedMainAttributedString
        let paraStyle = attrOut.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        var runCount = 0
        attrOut.enumerateAttributes(in: NSRange(location: 0, length: attrOut.length), options: []) { _, _, _ in
            runCount += 1
        }
        check(paraStyle?.baseWritingDirection == .rightToLeft && runCount <= 4, "Arabic lyrics keep RTL writing direction and intact word runs (runs=\(runCount))")

        for style in ThemeLineTransition.allCases {
            var animTheme = rtlTheme
            animTheme.lineTransition = style
            rtlView.applyTheme(animTheme)
            rtlView.update(
                trackTitle: "Transition Test",
                mainText: "Line transitioning softly \(style.rawValue)",
                backingText: "Ooh",
                songProgress: 0.5,
                lineProgress: 0.6,
                backingLineProgress: 0.4,
                vocalEnergy: 0.8,
                backingVocalEnergy: 0.5,
                isPlaying: true,
                isVocalSynced: true
            )
        }
        check(!rtlView.renderedMainAttributedString.string.isEmpty, "all line transition modes execute smoothly across line & backing changes")

        // 10. Japanese Particles/Sokuon/Macrons, Algorithmic Korean & Intonation-Driven Karaoke Animation
        let jaParticles = TextRomanizer.romanize("君は僕のもの 明日へ走れ 夢を見て", preferJapanese: true)
        check(jaParticles.contains("kimi wa boku") && jaParticles.contains("e hashire") && jaParticles.contains("o mite"), "Japanese particlesは/へ/を romanize accurately (\(jaParticles))")

        let jaSokuonCoffee = TextRomanizer.romanize("ずっと待っていた コーヒーを飲んで", preferJapanese: true)
        check(jaSokuonCoffee.contains("zutto matte ita") && jaSokuonCoffee.contains("koohii o nonde"), "Japanese cross-token sokuon & choonpu render cleanly (\(jaSokuonCoffee))")

        let jaYrcSokuon = LyricsParserAndFetcher.parseYRC("[1000,2000](1000,400,0)待(1400,200,0)っ(1600,400,0)て")
        let jaYrcRom = TextRomanizer.romanizeLines(jaYrcSokuon, titleHint: "待って", artistHint: "JPop")
        check(jaYrcRom[0].mainText.lowercased().contains("matte"), "Japanese YRC isolated small-tsu doubles consonant without emitting 'tsu' (\(jaYrcRom[0].mainText))")

        let koFull = TextRomanizer.romanize("사랑해요 괜찮아 빨리")
        check(koFull == "saranghaeyo gwaenchana ppalli", "Algorithmic Korean Revised Romanization handles liaison & ㄹ/l assimilation (\(koFull))")

        let softView = TouchBarLyricsView {}
        var karaTheme = TouchBarTheme.builtInThemes[0]
        karaTheme.wordAnimation = .karaokeLift
        softView.applyTheme(karaTheme)
        softView.update(
            trackTitle: "Intonation",
            mainText: "Belting high note",
            backingText: nil,
            songProgress: 0.4,
            lineProgress: 0.5,
            backingLineProgress: nil,
            vocalEnergy: 0.15,
            backingVocalEnergy: 0.10,
            vocalIntonation: 0.10,
            vocalOnset: 0.0,
            isPlaying: true,
            isVocalSynced: true
        )
        let softAttr = softView.renderedMainAttributedString
        let midCharIdx = softAttr.length / 2
        let softLift = (softAttr.attribute(.baselineOffset, at: midCharIdx, effectiveRange: nil) as? NSNumber)?.doubleValue ?? 0.0

        let loudView = TouchBarLyricsView {}
        loudView.applyTheme(karaTheme)
        for _ in 0..<8 {
            loudView.update(
                trackTitle: "Intonation",
                mainText: "Belting high note",
                backingText: nil,
                songProgress: 0.4,
                lineProgress: 0.5,
                backingLineProgress: nil,
                vocalEnergy: 0.95,
                backingVocalEnergy: 0.50,
                vocalIntonation: 0.95,
                vocalOnset: 0.90,
                isPlaying: true,
                isVocalSynced: true
            )
        }
        let loudAttr = loudView.renderedMainAttributedString
        let loudLift = (loudAttr.attribute(.baselineOffset, at: midCharIdx, effectiveRange: nil) as? NSNumber)?.doubleValue ?? 0.0
        check(loudLift > softLift + 0.6, "high vocal intonation & syllable onset increases karaoke syllable lift (soft=\(softLift) loud=\(loudLift))")

        let engine = VocalAutoSyncEngine()
        let pace = engine.realtimeDeliveryTempoScale()
        check(pace >= 0.70 && pace <= 1.55, "realtime delivery tempo scale stays safely bounded (\(pace))")

        // 11. Language/Script Guard, Variant Rejection & Empty-LRC Breath Pause Clamping
        let jpNativeLines = (0..<6).map { LyricLine(time: Double($0) * 18.0, mainText: "夜に駆ける夢を見てる", backingText: nil) }
        let jpEngTranslationLines = (0..<6).map { LyricLine(time: Double($0) * 18.0, mainText: "Into the night we run and see the moon in your eyes", backingText: nil) }
        let jpNativeScore = LyricsParserAndFetcher.scoreCandidate(
            trackName: "夜に駆ける", artistName: "YOASOBI", rawInputTitle: "夜に駆ける",
            expectedTitle: "夜に駆ける", expectedArtist: "YOASOBI",
            refDuration: 260, targetDuration: 260, hasSynced: true, hasWordTimings: false, parsedLines: jpNativeLines
        )
        let jpEngScore = LyricsParserAndFetcher.scoreCandidate(
            trackName: "夜に駆ける", artistName: "YOASOBI", rawInputTitle: "夜に駆ける",
            expectedTitle: "夜に駆ける", expectedArtist: "YOASOBI",
            refDuration: 260, targetDuration: 260, hasSynced: true, hasWordTimings: false, parsedLines: jpEngTranslationLines
        )
        check(jpNativeScore > 140 && jpEngScore < 65, "Japanese track prioritizes native Kana lyrics and rejects English translations (jp=\(jpNativeScore) eng=\(jpEngScore))")

        let instPenalty = LyricsParserAndFetcher.scoreCandidate(
            trackName: "YOASOBI 夜に駆ける(inst)", artistName: "YOASOBI", rawInputTitle: "YOASOBI 夜に駆ける",
            expectedTitle: "夜に駆ける", expectedArtist: "YOASOBI",
            refDuration: 260, targetDuration: 260, hasSynced: true, hasWordTimings: false, parsedLines: jpNativeLines
        )
        check(jpNativeScore > instPenalty + 50, "(inst) instrumental candidate loses cleanly to original vocal track")

        let wrongArtistLemon = LyricsParserAndFetcher.scoreCandidate(
            trackName: "Lemon", artistName: "U2", rawInputTitle: "Kenshi Yonezu - Lemon",
            expectedTitle: "Lemon", expectedArtist: "Kenshi Yonezu",
            refDuration: 255, targetDuration: 255, hasSynced: true, hasWordTimings: false, parsedLines: jpEngTranslationLines
        )
        check(wrongArtistLemon < 65, "short 1-word title with mismatched artist is rejected (\(wrongArtistLemon))")

        let pauseParsed = LyricsParserAndFetcher.parseLRC("""
        [00:45.00]Aku pulang
        [00:48.00]
        [00:56.00]Sampai akhir waktu
        """)
        let synthesized = LyricsParserAndFetcher.synthesizeWordTimings(for: pauseParsed)
        check((pauseParsed.first?.endTime ?? 99) <= 48.1, "empty LRC timestamp preserves instrumental/breath end boundary")
        check((synthesized.first?.words.last.map { $0.time + $0.duration } ?? 99) <= 48.0, "karaoke words finish before breath gap instead of dragging across 8s pause")

        // v2.3: Rapid non-parenthesized chorus lines (0.28s apart) stay separate lead lines, while unison backing locks to 0.0s lead start
        let rapidChorus = LyricsParserAndFetcher.parseLRC("""
        [00:10.00]Wait for me in the rain
        [00:10.28]Run away
        [00:11.20](hold on) Hold on now
        """)
        check(rapidChorus.count == 3, "rapid 0.28s chorus lines stay separate main lines instead of collapsing into backing")
        let synthRapid = LyricsParserAndFetcher.synthesizeWordTimings(for: rapidChorus)
        check(abs((synthRapid.last?.backingTime ?? -1) - 11.20) < 0.05, "unison backing vocal starts right on lead onset (11.20s)")

        // v2.3: Track-wide cadence calibration prevents short phrase before long break from dragging
        let calibratedSong = LyricsParserAndFetcher.synthesizeWordTimings(for: LyricsParserAndFetcher.parseLRC("""
        [00:01.00]Fast beat one two three four
        [00:02.10]Fast beat five six seven eight
        [00:03.20]Fast beat nine ten eleven
        [00:04.30]Short line
        [00:11.30]Next chorus drops here now
        """))
        let shortPhraseEnd = calibratedSong[3].words.last.map { $0.time + $0.duration } ?? 99
        check(shortPhraseEnd < 7.5, "track-calibrated cadence keeps short phrase concise before 7s instrumental pause (end=\(shortPhraseEnd))")

        // v2.3: Theme Codable defaults + new VocalSyncMode & backingOffsetSeconds roundtrip
        var customTheme = TouchBarTheme.builtInThemes[0]
        customTheme.vocalSyncMode = .strictCrowded
        customTheme.backingOffsetSeconds = -0.35
        if let encoded = try? JSONEncoder().encode(customTheme),
           let decoded = try? JSONDecoder().decode(TouchBarTheme.self, from: encoded) {
            check(decoded.vocalSyncMode == .strictCrowded && abs(decoded.backingOffsetSeconds - (-0.35)) < 0.001, "TouchBarTheme persists vocalSyncMode and backingOffsetSeconds")
        } else {
            check(false, "TouchBarTheme encodes and decodes cleanly")
        }

        let syncEngine = VocalAutoSyncEngine()
        syncEngine.syncMode = .strictCrowded
        check(syncEngine.syncMode == .strictCrowded, "VocalAutoSyncEngine exposes syncMode configuration")
        syncEngine.resetForNewTrack()
        let unsortedLyrics = [
            LyricLine(time: 20.0, mainText: "Later", backingText: nil),
            LyricLine(time: 5.0, mainText: "Earlier", backingText: nil)
        ]
        syncEngine.recordAndAlign(mediaElapsed: 5.5, lyrics: unsortedLyrics, isEstimated: false)
        check(
            syncEngine.currentNormalizedEnergy() >= 0 && syncEngine.currentNormalizedEnergy() <= 1 &&
            syncEngine.currentNormalizedBackingEnergy() >= 0 && syncEngine.currentNormalizedBackingEnergy() <= 1,
            "VocalAutoSyncEngine resets lock-free state and handles unsorted lyrics safely"
        )

        // v2.3: Multi-language i18n parity & English default check across all AppLanguage cases
        let savedLangRaw = UserDefaults.standard.string(forKey: "appLanguage")
        UserDefaults.standard.removeObject(forKey: "appLanguage")
        check(L10n.currentLanguage == .english, "default settings language is English")
        var missingOrEmpty = 0
        for (key, row) in L10n.translations {
            for lang in AppLanguage.allCases {
                let val = row[lang] ?? ""
                if val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    missingOrEmpty += 1
                    print("Missing translation: \(key) [\(lang.rawValue)]")
                }
            }
        }
        check(missingOrEmpty == 0, "all \(L10n.translations.count) UI keys are translated across all \(AppLanguage.allCases.count) languages")
        L10n.currentLanguage = .japanese
        check(VocalSyncMode.manual.displayName == "手動 (固定オフセット)", "enum displayName switches dynamically with selected language")
        if let prev = savedLangRaw {
            UserDefaults.standard.set(prev, forKey: "appLanguage")
        } else {
            UserDefaults.standard.removeObject(forKey: "appLanguage")
        }

        if failures > 0 {
            print("\(failures) failing core test(s)")
            exit(1)
        }
        print("All core engine tests passed")
    }
}
