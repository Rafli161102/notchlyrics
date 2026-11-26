import Foundation

struct LyricWord: Codable, Equatable {
    let time: TimeInterval
    let duration: TimeInterval
    let text: String
}

struct LyricLine: Codable, Equatable {
    let time: TimeInterval
    let endTime: TimeInterval?
    let backingTime: TimeInterval?
    let backingEndTime: TimeInterval?
    let mainText: String
    let backingText: String?
    let backingIsSuffix: Bool
    let words: [LyricWord]
    let backingWords: [LyricWord]

    init(
        time: TimeInterval,
        endTime: TimeInterval? = nil,
        backingTime: TimeInterval? = nil,
        backingEndTime: TimeInterval? = nil,
        mainText: String,
        backingText: String?,
        backingIsSuffix: Bool = false,
        words: [LyricWord] = [],
        backingWords: [LyricWord] = []
    ) {
        self.time = time
        self.endTime = endTime
        self.backingTime = backingTime
        self.backingEndTime = backingEndTime
        self.mainText = mainText
        self.backingText = backingText
        self.backingIsSuffix = backingIsSuffix
        self.words = words
        self.backingWords = backingWords
    }

    var hasAnyText: Bool {
        !mainText.isEmpty || !(backingText ?? "").isEmpty
    }

    /// Computes exact per-character sweep progress [0, 1] at `elapsed` for the main vocal,
    /// scaled smoothly by `wordSpeedScale` (0.50x .. 2.00x) for accurate karaoke pacing.
    func singingProgress(at elapsed: TimeInterval, nextLineTime: TimeInterval, wordSpeedScale: Double = 1.0) -> CGFloat {
        return Self.progressForWords(
            words,
            textLength: mainText.count,
            fallbackStart: time,
            fallbackEnd: endTime,
            defaultSpanCap: nextLineTime,
            elapsed: elapsed,
            speedScale: wordSpeedScale
        )
    }

    /// Computes independent per-character sweep progress [0, 1] for backing vocals.
    func backingProgress(at elapsed: TimeInterval, nextLineTime: TimeInterval, wordSpeedScale: Double = 1.0) -> CGFloat {
        let len = (backingText ?? "").count
        let start = backingTime ?? time
        return Self.progressForWords(
            backingWords,
            textLength: len,
            fallbackStart: start,
            fallbackEnd: backingEndTime,
            defaultSpanCap: nextLineTime,
            elapsed: elapsed,
            speedScale: wordSpeedScale
        )
    }

    private static func progressForWords(
        _ words: [LyricWord],
        textLength: Int,
        fallbackStart: TimeInterval,
        fallbackEnd: TimeInterval?,
        defaultSpanCap: TimeInterval,
        elapsed: TimeInterval,
        speedScale: Double = 1.0
    ) -> CGFloat {
        let scale = max(0.5, min(2.0, speedScale))

        if !words.isEmpty {
            let phraseStart = words.first!.time
            let rawSpan = max(0.35, (words.last!.time + words.last!.duration) - phraseStart)
            let scaledElapsed: TimeInterval
            if abs(scale - 1.0) < 0.01 {
                scaledElapsed = elapsed
            } else {
                // Scale sweep cadence cleanly around line onset while capping before next line
                let maxAllowedSpan = max(0.35, defaultSpanCap - phraseStart)
                let desiredSpan = min(maxAllowedSpan, rawSpan / scale)
                let factor = rawSpan / max(0.25, desiredSpan)
                scaledElapsed = phraseStart + (elapsed - phraseStart) * factor
            }

            let totalChars = max(1, words.reduce(0) { $0 + $1.text.count })
            var charsBefore = 0
            for (idx, w) in words.enumerated() {
                let len = w.text.count
                let wEnd = w.time + max(0.07, w.duration)
                if scaledElapsed < w.time {
                    return CGFloat(charsBefore) / CGFloat(totalChars)
                }
                if scaledElapsed <= wEnd {
                    let frac = (scaledElapsed - w.time) / max(0.07, w.duration)
                    let pos = Double(charsBefore) + min(1.0, max(0.0, frac)) * Double(len)
                    return CGFloat(min(1.0, max(0.0, pos / Double(totalChars))))
                }
                if idx + 1 < words.count && scaledElapsed < words[idx + 1].time {
                    return CGFloat(charsBefore + len) / CGFloat(totalChars)
                }
                charsBefore += len
            }
            return 1.0
        }

        let gap = max(0.5, defaultSpanCap - fallbackStart)
        let baseEnd = fallbackEnd ?? (fallbackStart + min(gap * 0.86, max(1.0, Double(textLength) * 0.085)))
        let baseSpan = max(0.4, baseEnd - fallbackStart)
        let scaledSpan = min(gap, max(0.3, baseSpan / scale))
        return CGFloat(min(1.0, max(0.0, (elapsed - fallbackStart) / scaledSpan)))
    }
}

struct FetchedLyricsResult: Codable {
    let lines: [LyricLine]
    let romanizedLines: [LyricLine]
    let sourceName: String
    let isEstimated: Bool
    let hasWordTimings: Bool
    let referenceDuration: TimeInterval
    var calibratedLeadOffset: TimeInterval
    var calibratedBackingOffset: TimeInterval
    var cachedBPM: Double

    enum CodingKeys: String, CodingKey {
        case lines, romanizedLines, sourceName, isEstimated, hasWordTimings, referenceDuration
        case calibratedLeadOffset, calibratedBackingOffset, cachedBPM
    }

    init(
        lines: [LyricLine],
        romanizedLines: [LyricLine]? = nil,
        sourceName: String,
        isEstimated: Bool,
        hasWordTimings: Bool = false,
        referenceDuration: TimeInterval,
        calibratedLeadOffset: TimeInterval = 0,
        calibratedBackingOffset: TimeInterval = 0,
        cachedBPM: Double = 0
    ) {
        self.lines = lines
        self.romanizedLines = romanizedLines ?? lines
        self.sourceName = sourceName
        self.isEstimated = isEstimated
        self.hasWordTimings = hasWordTimings
        self.referenceDuration = referenceDuration
        self.calibratedLeadOffset = calibratedLeadOffset
        self.calibratedBackingOffset = calibratedBackingOffset
        self.cachedBPM = cachedBPM
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lines = try c.decode([LyricLine].self, forKey: .lines)
        romanizedLines = try c.decodeIfPresent([LyricLine].self, forKey: .romanizedLines) ?? lines
        sourceName = try c.decode(String.self, forKey: .sourceName)
        isEstimated = try c.decode(Bool.self, forKey: .isEstimated)
        hasWordTimings = try c.decodeIfPresent(Bool.self, forKey: .hasWordTimings) ?? false
        referenceDuration = try c.decode(TimeInterval.self, forKey: .referenceDuration)
        calibratedLeadOffset = try c.decodeIfPresent(TimeInterval.self, forKey: .calibratedLeadOffset) ?? 0
        calibratedBackingOffset = try c.decodeIfPresent(TimeInterval.self, forKey: .calibratedBackingOffset) ?? 0
        cachedBPM = try c.decodeIfPresent(Double.self, forKey: .cachedBPM) ?? 0
    }

    func activeLines(romanize: Bool) -> [LyricLine] {
        return romanize ? romanizedLines : lines
    }

    var hasNonLatinScript: Bool {
        lines.contains {
            TextRomanizer.needsRomanization($0.mainText)
                || TextRomanizer.needsRomanization($0.backingText ?? "")
        }
    }
}

final class DiskLyricsCache {
    let cacheDir: String
    private let ioQueue = DispatchQueue(label: "com.user.TouchBarLyrics.diskcache", qos: .utility)
    private let maxFiles = 400

    init(directory: String? = nil) {
        self.cacheDir = directory ?? ((NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Application Support/TouchBarLyrics/LyricsCache"))
        try? FileManager.default.createDirectory(atPath: self.cacheDir, withIntermediateDirectories: true)
    }

    private static func fnv1aHex(_ key: String) -> String {
        var hash: UInt64 = 14695981039346656037
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return String(format: "%016llx", hash)
    }

    private func fileURL(forKey key: String) -> URL {
        URL(fileURLWithPath: (cacheDir as NSString).appendingPathComponent("\(Self.fnv1aHex(key)).json"))
    }

    func load(cacheKey: String, fuzzyKey: String, targetDuration: TimeInterval) -> FetchedLyricsResult? {
        for candidateKey in [cacheKey, fuzzyKey] where !candidateKey.isEmpty {
            let url = fileURL(forKey: candidateKey)
            guard let data = try? Data(contentsOf: url),
                  var decoded = try? JSONDecoder().decode(FetchedLyricsResult.self, from: data),
                  !decoded.lines.isEmpty else {
                continue
            }
            if targetDuration > 20 && decoded.referenceDuration > 20 && abs(decoded.referenceDuration - targetDuration) > 8.0 && candidateKey != cacheKey {
                continue
            }
            if !decoded.sourceName.contains("Cache") {
                decoded = FetchedLyricsResult(
                    lines: decoded.lines,
                    romanizedLines: decoded.romanizedLines,
                    sourceName: "\(decoded.sourceName) • Cache",
                    isEstimated: decoded.isEstimated,
                    hasWordTimings: decoded.hasWordTimings,
                    referenceDuration: decoded.referenceDuration,
                    calibratedLeadOffset: decoded.calibratedLeadOffset,
                    calibratedBackingOffset: decoded.calibratedBackingOffset,
                    cachedBPM: decoded.cachedBPM
                )
            }
            return decoded
        }
        return nil
    }

    func save(_ result: FetchedLyricsResult, cacheKey: String, fuzzyKey: String) {
        guard !result.lines.isEmpty, result.sourceName != "None" else { return }
        // Normalize source name before writing so repeat loads don't stack "• Cache"
        var clean = result
        if clean.sourceName.hasSuffix(" • Cache") {
            clean = FetchedLyricsResult(
                lines: result.lines,
                romanizedLines: result.romanizedLines,
                sourceName: String(result.sourceName.dropLast(" • Cache".count)),
                isEstimated: result.isEstimated,
                hasWordTimings: result.hasWordTimings,
                referenceDuration: result.referenceDuration,
                calibratedLeadOffset: result.calibratedLeadOffset,
                calibratedBackingOffset: result.calibratedBackingOffset,
                cachedBPM: result.cachedBPM
            )
        }
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            let fm = FileManager.default
            try? fm.createDirectory(atPath: self.cacheDir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(clean) else { return }
            try? data.write(to: self.fileURL(forKey: cacheKey), options: .atomic)
            if !fuzzyKey.isEmpty && fuzzyKey != cacheKey {
                try? data.write(to: self.fileURL(forKey: fuzzyKey), options: .atomic)
            }
            self.pruneIfNeeded()
        }
    }

    func remove(cacheKey: String, fuzzyKey: String) {
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            try? FileManager.default.removeItem(at: self.fileURL(forKey: cacheKey))
            if !fuzzyKey.isEmpty {
                try? FileManager.default.removeItem(at: self.fileURL(forKey: fuzzyKey))
            }
        }
    }

    private func pruneIfNeeded() {
        let dirURL = URL(fileURLWithPath: cacheDir)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ), urls.count > maxFiles else { return }

        let sorted = urls.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da < db
        }
        for oldURL in sorted.prefix(urls.count - maxFiles) {
            try? FileManager.default.removeItem(at: oldURL)
        }
    }
}

final class LyricsParserAndFetcher {
    private var cache: [String: FetchedLyricsResult] = [:]
    private let cacheLock = NSLock()
    private var currentFetchToken = UUID()
    private var activeTasks: [UUID: [UUID: URLSessionDataTask]] = [:]
    private let taskLock = NSLock()
    let diskCache: DiskLyricsCache

    private let fastSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 2.6
        cfg.timeoutIntervalForResource = 4.2
        cfg.httpMaximumConnectionsPerHost = 8
        cfg.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 32 * 1024 * 1024)
        return URLSession(configuration: cfg)
    }()

    private func startManagedTask(url: URL, token: UUID, headers: [String: String] = [:], completion: @escaping (Data?, URLResponse?, Error?) -> Void) {
        var req = URLRequest(url: url, timeoutInterval: 2.6)
        for (k, v) in headers {
            req.setValue(v, forHTTPHeaderField: k)
        }
        let taskID = UUID()
        let task = fastSession.dataTask(with: req) { [weak self] data, resp, err in
            if let self = self {
                self.taskLock.lock()
                self.activeTasks[token]?.removeValue(forKey: taskID)
                self.taskLock.unlock()
            }
            completion(data, resp, err)
        }

        taskLock.lock()
        let isStillCurrent = (token == currentFetchToken)
        if isStillCurrent {
            var tokenMap = activeTasks[token] ?? [:]
            tokenMap[taskID] = task
            activeTasks[token] = tokenMap
        }
        taskLock.unlock()

        if isStillCurrent {
            task.resume()
        } else {
            completion(nil, nil, nil)
        }
    }

    private func cancelStaleTasks(keeping activeToken: UUID) {
        taskLock.lock()
        currentFetchToken = activeToken
        var toCancel: [URLSessionDataTask] = []
        for (tok, map) in activeTasks where tok != activeToken {
            toCancel.append(contentsOf: map.values)
            activeTasks.removeValue(forKey: tok)
        }
        taskLock.unlock()
        for t in toCancel { t.cancel() }
    }

    private func isTokenCurrent(_ token: UUID) -> Bool {
        taskLock.lock()
        defer { taskLock.unlock() }
        return token == currentFetchToken
    }

    init(diskCache: DiskLyricsCache = DiskLyricsCache()) {
        self.diskCache = diskCache
    }

    private struct RankedCandidate {
        let lines: [LyricLine]
        let sourceName: String
        let isEstimated: Bool
        let hasWordTimings: Bool
        let referenceDuration: TimeInterval
        let matchScore: Double
    }

    private func finalizeResult(
        lines: [LyricLine],
        sourceName: String,
        isEstimated: Bool,
        hasWordTimings: Bool,
        referenceDuration: TimeInterval,
        titleHint: String,
        artistHint: String
    ) -> FetchedLyricsResult {
        let withWords = hasWordTimings ? lines : Self.synthesizeWordTimings(for: lines)
        let rom = TextRomanizer.romanizeLines(withWords, titleHint: titleHint, artistHint: artistHint)
        return FetchedLyricsResult(
            lines: withWords,
            romanizedLines: rom,
            sourceName: sourceName,
            isEstimated: isEstimated,
            hasWordTimings: hasWordTimings,
            referenceDuration: referenceDuration
        )
    }

    func cachedResult(forKey key: String) -> FetchedLyricsResult? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cache[key]
    }

    func updateCalibration(forKey key: String, rawTitle: String, rawArtist: String, leadOffset: TimeInterval, backingOffset: TimeInterval, bpm: Double) {
        let fuzzy = fuzzyCacheKey(rawTitle: rawTitle, rawArtist: rawArtist)
        cacheLock.lock()
        guard var current = cache[key] else {
            cacheLock.unlock()
            return
        }
        current.calibratedLeadOffset = leadOffset
        current.calibratedBackingOffset = backingOffset
        if bpm >= 55 { current.cachedBPM = bpm }
        cache[key] = current
        cacheLock.unlock()
        diskCache.save(current, cacheKey: key, fuzzyKey: fuzzy)
    }

    func clearCacheEntry(forKey key: String, rawTitle: String, rawArtist: String) {
        let fuzzy = fuzzyCacheKey(rawTitle: rawTitle, rawArtist: rawArtist)
        cacheLock.lock()
        cache.removeValue(forKey: key)
        cacheLock.unlock()
        diskCache.remove(cacheKey: key, fuzzyKey: fuzzy)
    }

    private func fuzzyCacheKey(rawTitle: String, rawArtist: String) -> String {
        let t = cleanTitle(rawTitle).lowercased()
        let a = cleanArtist(rawArtist).lowercased()
        return t.isEmpty ? "" : "\(t)|\(a)"
    }

    func normalizeDashSeparators(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+[\u2013\u2014\u2015~]\s+"#, with: " - ", options: .regularExpression)
    }

    func cleanTitle(_ raw: String) -> String {
        var s = raw
        // Extract inner title from Japanese quotes e.g. YOASOBI「夜に駆ける」
        if let jpQuoteRegex = try? NSRegularExpression(pattern: #"[「『]([^」』]+)[」』]"#),
           let m = jpQuoteRegex.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) {
            let inner = (s as NSString).substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            if inner.count >= 2 { s = inner }
        }
        let bracketNoise = #"\s*[\(\[]\s*(Official\s*(Music\s*)?Video|Official\s*Audio|Official\s*MV|Official\s*Lyric\s*Video|Lyric\s*Video|Lyrics?\s*Video|Lyrics?|Lirik(\s*Terjemahan)?|Sub\s*(Indo|Eng|Indonesia|English)|Audio(\s*Only)?|Visualizer|M/?V|HD|4K|Live(\s*Performance)?|Explicit|Clean(\s*Version)?|Single\s*Version|Radio\s*Edit|Album\s*Version|Remaster(ed)?(\s*\d+)?|Slowed(\s*\+\s*Reverb)?|Sped\s*Up|Speed\s*Up|Karaoke|Color\s*Coded|Prod\.?\s*by\s+[^\)\]]+|From\s+["“][^"”]+["”])\s*[\)\]]"#
        s = s.replacingOccurrences(of: bracketNoise, with: "", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"^\s*\[(MV|M/V|Lyrics?|Audio|Official)\]\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"\s*[-\u2013\u2014]\s*(Official\s*(Music\s*)?Video|Official\s*Audio|Official\s*MV|Lyric\s*Video|Lyrics?|Lirik(\s*Terjemahan)?|Audio(\s*Only)?|Remaster(ed)?(\s*\d+)?|Single\s*Version|Radio\s*Edit|YouTube)\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"\s*\|\s*.*$"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s*//\s*.*$"#, with: "", options: .regularExpression)
        s = normalizeDashSeparators(s)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cleanArtist(_ raw: String) -> String {
        var s = raw.replacingOccurrences(of: #"\s*[-\u2013\u2014]\s*Topic$"#, with: "", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"\s*VEVO$"#, with: "", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"\s*(Official|Channel)$"#, with: "", options: [.regularExpression, .caseInsensitive])
        if let first = s.components(separatedBy: ",").first {
            s = first
        }
        s = s.replacingOccurrences(of: #"\s+(feat\.?|ft\.?|featuring|x|&)\s+.*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanArtistFull(_ raw: String) -> String {
        var s = raw.replacingOccurrences(of: #"\s*[-\u2013\u2014]\s*Topic$"#, with: "", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"\s*VEVO$"#, with: "", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"\s*(Official|Channel)$"#, with: "", options: [.regularExpression, .caseInsensitive])
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func resolveExpectedTitleArtist(rawTitle: String, rawArtist: String) -> (title: String, artist: String) {
        let baseTitle = cleanTitle(rawTitle)
        let baseArtist = cleanArtist(rawArtist)
        if baseTitle.contains(" - ") {
            let parts = baseTitle.components(separatedBy: " - ")
            if parts.count >= 2 {
                let left = cleanArtist(parts[0])
                let right = cleanTitle(parts[1...].joined(separator: " - "))
                if !left.isEmpty && !right.isEmpty {
                    let normRawArt = baseArtist.lowercased()
                    if normRawArt == right.lowercased() || (!normRawArt.isEmpty && right.lowercased().contains(normRawArt)) {
                        return (cleanTitle(parts[0]), right)
                    }
                    return (right, left)
                }
            }
        }
        if let jpMatch = rawTitle.range(of: #"^([^「『]+)[「『]([^」』]+)[」』]"#, options: .regularExpression) {
            let full = String(rawTitle[jpMatch])
            if let openIdx = full.firstIndex(where: { $0 == "「" || $0 == "『" }),
               let closeIdx = full.lastIndex(where: { $0 == "」" || $0 == "』" }) {
                let artPart = cleanArtist(String(full[..<openIdx]))
                let titPart = cleanTitle(String(full[full.index(after: openIdx)..<closeIdx]))
                if !titPart.isEmpty {
                    return (titPart, artPart.isEmpty ? baseArtist : artPart)
                }
            }
        }
        return (baseTitle, baseArtist)
    }

    func stripFeaturing(_ text: String) -> String {
        let noFeat = text.replacingOccurrences(
            of: #"\s*[\(\[]?\s*(feat\.?|ft\.?|featuring|with|prod\.?\s*by)\s+[^\)\]]+[\)\]]?"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return noFeat.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Checks instant memory & persistent disk cache (< 1ms) first; on miss, cancels stale tasks,
    /// concurrently races LRCLIB + NetEase YRC with progressive early emission, and normalizes messy
    /// metadata via iTunes Search fallback when needed.
    func fetchLyrics(
        cacheKey: String,
        rawTitle: String,
        rawArtist: String,
        album: String = "",
        duration: TimeInterval,
        forceRefresh: Bool = false,
        completion: @escaping (FetchedLyricsResult) -> Void
    ) {
        let token = UUID()
        cancelStaleTasks(keeping: token)

        let fuzzyKey = fuzzyCacheKey(rawTitle: rawTitle, rawArtist: rawArtist)
        if !forceRefresh {
            cacheLock.lock()
            let memHit = cache[cacheKey]
            cacheLock.unlock()
            if let hit = memHit {
                completion(hit)
                return
            }

            if let diskHit = diskCache.load(cacheKey: cacheKey, fuzzyKey: fuzzyKey, targetDuration: duration) {
                cacheLock.lock()
                cache[cacheKey] = diskHit
                cacheLock.unlock()
                completion(diskHit)
                return
            }
        }

        let resolvedHints = resolveExpectedTitleArtist(rawTitle: rawTitle, rawArtist: rawArtist)
        let titleHint = resolvedHints.title
        let artistHint = resolvedHints.artist
        let candidates = buildQueryCandidates(rawTitle: rawTitle, rawArtist: rawArtist)

        let stateLock = NSLock()
        let coordGroup = DispatchGroup()
        var pool: [RankedCandidate] = []
        var emittedScore: Double = -999
        var emittedHasWordTimings = false
        var finalizedBest = false
        let searchStart = Date()
        var firstSyncedHitAt: Date?

        func commitToCacheAndEmit(_ cand: RankedCandidate) {
            guard isTokenCurrent(token) else { return }
            let result = self.finalizeResult(
                lines: cand.lines,
                sourceName: cand.sourceName,
                isEstimated: cand.isEstimated,
                hasWordTimings: cand.hasWordTimings,
                referenceDuration: cand.referenceDuration,
                titleHint: titleHint,
                artistHint: artistHint
            )
            self.cacheLock.lock()
            self.cache[cacheKey] = result
            self.cacheLock.unlock()
            if !cand.isEstimated || cand.matchScore >= 15.0 {
                self.diskCache.save(result, cacheKey: cacheKey, fuzzyKey: fuzzyKey)
            }
            completion(result)
        }

        func ingest(_ items: [RankedCandidate]) {
            guard !items.isEmpty, isTokenCurrent(token) else { return }
            var immediateEmit: RankedCandidate?

            stateLock.lock()
            pool.append(contentsOf: items)
            let validSynced = pool.filter { !$0.isEstimated && $0.matchScore >= 65.0 }
            if !validSynced.isEmpty && firstSyncedHitAt == nil {
                firstSyncedHitAt = Date()
            }
            if let best = validSynced.max(by: { $0.matchScore < $1.matchScore }) {
                if !finalizedBest {
                    let isInstantExact = (best.matchScore >= 145.0 && (best.hasWordTimings || Date().timeIntervalSince(searchStart) >= 0.45))
                    if isInstantExact {
                        emittedScore = best.matchScore
                        emittedHasWordTimings = best.hasWordTimings
                        immediateEmit = best
                    }
                } else if best.hasWordTimings && !emittedHasWordTimings && best.matchScore >= emittedScore - 8.0 {
                    // Seamless upgrade from fast LRC to per-word YRC once it lands for the same track
                    emittedScore = best.matchScore
                    emittedHasWordTimings = true
                    immediateEmit = best
                } else if best.matchScore > emittedScore + 20.0 {
                    emittedScore = best.matchScore
                    emittedHasWordTimings = best.hasWordTimings
                    immediateEmit = best
                }
            }
            stateLock.unlock()

            if let hit = immediateEmit {
                commitToCacheAndEmit(hit)
            }
        }

        coordGroup.enter()
        fetchLRCLIBCandidates(
            token: token,
            candidates: candidates,
            album: album,
            rawTitle: rawTitle,
            expectedTitle: titleHint,
            expectedArtist: artistHint,
            targetDuration: duration,
            onBatch: { batch in ingest(batch) },
            completion: { coordGroup.leave() }
        )

        coordGroup.enter()
        fetchNetEaseCandidates(
            token: token,
            candidates: candidates,
            rawTitle: rawTitle,
            expectedTitle: titleHint,
            expectedArtist: artistHint,
            targetDuration: duration,
            onBatch: { batch in ingest(batch) },
            completion: { coordGroup.leave() }
        )

        coordGroup.enter()
        fetchKugouCandidates(
            token: token,
            candidates: candidates,
            rawTitle: rawTitle,
            expectedTitle: titleHint,
            expectedArtist: artistHint,
            targetDuration: duration,
            onBatch: { batch in ingest(batch) },
            completion: { coordGroup.leave() }
        )

        coordGroup.enter()
        fetchKuwoCandidates(
            token: token,
            candidates: candidates,
            rawTitle: rawTitle,
            expectedTitle: titleHint,
            expectedArtist: artistHint,
            targetDuration: duration,
            onBatch: { batch in ingest(batch) },
            completion: { coordGroup.leave() }
        )

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Smart responsive wait: emit in <= 0.45s after first confident synced hit instead of blocking 3.8s
            let hardDeadline = Date().addingTimeInterval(2.5)
            while Date() < hardDeadline && self?.isTokenCurrent(token) == true {
                if coordGroup.wait(timeout: .now() + 0.08) == .success {
                    break
                }
                stateLock.lock()
                let earlyHitTime = firstSyncedHitAt
                let alreadyEmitted = (emittedScore >= 65.0)
                stateLock.unlock()
                if alreadyEmitted { break }
                if let hitTime = earlyHitTime, Date().timeIntervalSince(hitTime) >= 0.45 {
                    break
                }
            }

            guard let self = self, self.isTokenCurrent(token) else { return }

            stateLock.lock()
            finalizedBest = true
            let validSynced = pool.filter { !$0.isEstimated && $0.matchScore >= 65.0 }
            let pickedSynced = validSynced.max(by: { $0.matchScore < $1.matchScore })
            let pickedEstimated = pool.filter { $0.matchScore >= 15.0 }.max(by: { $0.matchScore < $1.matchScore })
            let alreadySentScore = emittedScore
            stateLock.unlock()

            if let best = pickedSynced {
                if best.matchScore > alreadySentScore + 0.5 {
                    commitToCacheAndEmit(best)
                }
                return
            }

            // Tier 2B: Canonical iTunes Search metadata repair + second rapid LRCLIB lookup + Lyrics.ovh
            self.recoverViaCanonicalMetadataAndPlainFallback(
                token: token,
                candidates: candidates,
                rawTitle: rawTitle,
                expectedTitle: titleHint,
                expectedArtist: artistHint,
                targetDuration: duration,
                existingEstimated: pickedEstimated
            ) { recovered in
                guard self.isTokenCurrent(token) else { return }
                if let finalCand = recovered {
                    commitToCacheAndEmit(finalCand)
                } else {
                    let empty = FetchedLyricsResult(
                        lines: [],
                        romanizedLines: [],
                        sourceName: "None",
                        isEstimated: false,
                        hasWordTimings: false,
                        referenceDuration: duration
                    )
                    self.cacheLock.lock()
                    self.cache[cacheKey] = empty
                    self.cacheLock.unlock()
                    completion(empty)
                }
            }
        }
    }

    func buildQueryCandidates(rawTitle: String, rawArtist: String) -> [(track: String, artist: String)] {
        let baseTitle = cleanTitle(rawTitle)
        let baseArtist = cleanArtist(rawArtist)
        let fullCollabArtist = cleanArtistFull(rawArtist)
        var pairs: [(String, String)] = []

        func addPair(_ t: String, _ a: String) {
            let ct = t.trimmingCharacters(in: .whitespacesAndNewlines)
            let ca = a.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ct.isEmpty else { return }
            if !pairs.contains(where: { $0.0.caseInsensitiveCompare(ct) == .orderedSame && $0.1.caseInsensitiveCompare(ca) == .orderedSame }) {
                pairs.append((ct, ca))
            }
        }

        if let jpMatch = rawTitle.range(of: #"^([^「『]+)[「『]([^」』]+)[」』]"#, options: .regularExpression) {
            let full = String(rawTitle[jpMatch])
            if let openIdx = full.firstIndex(where: { $0 == "「" || $0 == "『" }),
               let closeIdx = full.lastIndex(where: { $0 == "」" || $0 == "』" }) {
                let artPart = cleanArtist(String(full[..<openIdx]))
                let titPart = cleanTitle(String(full[full.index(after: openIdx)..<closeIdx]))
                if !titPart.isEmpty {
                    addPair(titPart, artPart.isEmpty ? baseArtist : artPart)
                    addPair(titPart, "")
                }
            }
        }

        if baseTitle.contains(" - ") {
            let parts = baseTitle.components(separatedBy: " - ")
            if parts.count >= 2 {
                let left = cleanArtist(parts[0])
                let right = cleanTitle(parts[1...].joined(separator: " - "))
                addPair(right, left)
                addPair(stripFeaturing(right), left)
                if !baseArtist.isEmpty && baseArtist.caseInsensitiveCompare(left) != .orderedSame {
                    addPair(right, baseArtist)
                }
                addPair(left, right)
                addPair(right, "")
            }
        }

        addPair(baseTitle, baseArtist)
        if !fullCollabArtist.isEmpty && fullCollabArtist != baseArtist {
            addPair(baseTitle, fullCollabArtist)
        }
        addPair(stripFeaturing(baseTitle), baseArtist)

        if TextRomanizer.needsRomanization(baseTitle) {
            let romT = TextRomanizer.romanize(baseTitle, preferJapanese: TextRomanizer.containsJapaneseKana(baseTitle))
            let romA = TextRomanizer.needsRomanization(baseArtist)
                ? TextRomanizer.romanize(baseArtist, preferJapanese: TextRomanizer.containsJapaneseKana(baseArtist))
                : baseArtist
            addPair(romT, romA)
        }

        if !baseArtist.isEmpty {
            addPair(baseTitle, "")
            addPair(stripFeaturing(baseTitle), "")
        }

        return pairs
    }

    private static func normalizedTokens(_ text: String) -> Set<String> {
        let lower = text.lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
        let parts = lower.split(separator: " ").map { String($0) }.filter { !$0.isEmpty }
        var set = Set(parts)
        // Cross-script romanized expansion so "夜に駆ける" matches "Yoru ni Kakeru"
        if TextRomanizer.needsRomanization(text) {
            let rom = TextRomanizer.romanize(text, preferJapanese: TextRomanizer.containsJapaneseKana(text))
                .lowercased()
                .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
            for p in rom.split(separator: " ") where !p.isEmpty {
                set.insert(String(p))
            }
        }
        return set
    }

    private static func lineCoveragePenalty(lines: [LyricLine], targetDuration: TimeInterval) -> Double {
        guard !lines.isEmpty else { return -100.0 }
        if lines.count < 4 && targetDuration > 35 {
            // Stub placeholder like "[00:00.00]Instrumental"
            return -85.0
        }
        if targetDuration > 40, let lastTime = lines.last?.time {
            if lastTime > targetDuration + 18.0 {
                return -48.0
            }
            if lastTime < targetDuration * 0.25 {
                return -42.0
            }
        }
        return 0.0
    }

    private static func scriptConsistencyScore(
        lines: [LyricLine],
        trackName: String,
        artistName: String,
        rawInputTitle: String,
        expectedTitle: String,
        expectedArtist: String
    ) -> Double {
        let metaText = "\(rawInputTitle) \(expectedTitle) \(expectedArtist) \(trackName) \(artistName)"
        let expectsJapanese = TextRomanizer.containsJapaneseKana(metaText)
        let expectsKorean = TextRomanizer.containsHangul(metaText)
        let expectsCyrillic = TextRomanizer.containsCyrillic(metaText)
        let expectsArabic = TextRomanizer.isRTLScript(metaText)
        let expectsCJK = metaText.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }

        let sample = lines.prefix(16).map { $0.mainText }.joined(separator: " ")
        guard !sample.isEmpty else { return 0.0 }

        let hasJP = TextRomanizer.containsJapaneseKana(sample)
        let hasKO = TextRomanizer.containsHangul(sample)
        let hasRU = TextRomanizer.containsCyrillic(sample)
        let hasAR = TextRomanizer.isRTLScript(sample)
        let sampleCJKCount = sample.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) }.count
        let nonLatinRatio = Double(sample.unicodeScalars.filter { $0.value > 0x024F && $0.properties.isAlphabetic }.count)
            / Double(max(1, sample.unicodeScalars.filter { $0.properties.isAlphabetic }.count))

        let lowerSample = " " + sample.lowercased() + " "
        let englishMarkers = [" the ", " and ", " you ", " my ", " your ", " into ", " night ", " love ", " with ", " that "]
        let englishHits = englishMarkers.reduce(0) { $0 + (lowerSample.contains($1) ? 1 : 0) }

        if expectsJapanese {
            if hasJP { return 36.0 }
            if englishHits >= 3 && !hasJP && sampleCJKCount == 0 { return -150.0 }
            if nonLatinRatio < 0.05 { return -65.0 }
        } else if expectsKorean {
            if hasKO { return 36.0 }
            if englishHits >= 3 && !hasKO { return -150.0 }
            if nonLatinRatio < 0.05 { return -65.0 }
        } else if expectsCJK {
            if sampleCJKCount >= 8 { return 30.0 }
            if englishHits >= 3 && sampleCJKCount == 0 { return -140.0 }
        } else if expectsCyrillic {
            if hasRU { return 30.0 }
            if englishHits >= 3 && !hasRU { return -135.0 }
        } else if expectsArabic {
            if hasAR { return 30.0 }
        } else {
            // Pure Latin/Indonesian/English song should not display unrelated CJK/Cyrillic/Arabic translations
            if nonLatinRatio >= 0.45 && (hasJP || hasKO || hasRU || hasAR || sampleCJKCount >= 8) {
                return -140.0
            }
        }
        return 0.0
    }

    static func scoreCandidate(
        trackName: String,
        artistName: String,
        rawInputTitle: String,
        expectedTitle: String,
        expectedArtist: String,
        refDuration: TimeInterval,
        targetDuration: TimeInterval,
        hasSynced: Bool,
        hasWordTimings: Bool,
        parsedLines: [LyricLine]? = nil
    ) -> Double {
        var score: Double = hasSynced ? 100.0 : 20.0
        if hasWordTimings {
            score += 26.0
        }

        // 1. Duration accuracy scoring
        if targetDuration > 20 && refDuration > 20 {
            let diff = abs(refDuration - targetDuration)
            if diff <= 1.5 {
                score += 34.0
            } else if diff <= 3.5 {
                score += 24.0 - (diff - 1.5) * 4.5
            } else if diff <= 8.0 {
                score += 8.0 - diff * 2.5
            } else {
                score -= min(95.0, diff * 3.8)
            }
        }

        // 2. Cross-script Title similarity (handles Latin <-> Japanese/Korean/Mandarin!)
        let normTrack = trackName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normExpTitle = expectedTitle.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normRawAll = rawInputTitle.lowercased()
        let eTokCount = normalizedTokens(normExpTitle).count
        if !normExpTitle.isEmpty {
            let tTokens = normalizedTokens(normTrack)
            let eTokens = normalizedTokens(normExpTitle)
            let rawTokens = normalizedTokens(normRawAll)
            let overlap = max(tTokens.intersection(eTokens).count, tTokens.intersection(rawTokens).count)
            let unionCount = max(1, tTokens.union(eTokens).count)
            let jaccard = Double(overlap) / Double(unionCount)

            if normTrack == normExpTitle {
                score += 34.0
            } else if normTrack.contains(normExpTitle) || normExpTitle.contains(normTrack) || (!normTrack.isEmpty && normRawAll.contains(normTrack)) {
                score += 20.0
            } else if jaccard >= 0.42 {
                score += 18.0 * jaccard
            } else if overlap >= 2 && overlap >= min(tTokens.count, eTokens.count) {
                score += 12.0
            } else if overlap == 0 {
                // Zero title token match must never accept an unrelated track even if artist/duration aligns
                score -= 125.0
            } else {
                score -= 72.0
            }
        }

        // 3. Cross-script Artist matching (strictly rejects wrong artist on ambiguous short titles)
        let normArtist = artistName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normExpArtist = expectedArtist.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if !normArtist.isEmpty {
            let aTokens = normalizedTokens(normArtist)
            let eTokens = normalizedTokens(normExpArtist)
            let rawTitleTokens = normalizedTokens(normRawAll)
            let aOverlap = !eTokens.isEmpty && !aTokens.intersection(eTokens).isEmpty
            let inRawTitle = !aTokens.isEmpty && aTokens.isSubset(of: rawTitleTokens)

            if !normExpArtist.isEmpty && (normArtist == normExpArtist || normArtist.contains(normExpArtist) || normExpArtist.contains(normArtist) || aOverlap) {
                score += 30.0
            } else if inRawTitle || normRawAll.contains(normArtist) {
                score += 26.0
            } else if !normExpArtist.isEmpty {
                score -= (eTokCount <= 2) ? 105.0 : 78.0
            }
        }

        // 4. Reject unwanted covers, English adaptations, instrumentals, or speed-altered edits unless requested
        let variantTags = [
            "remix", "live", "cover", "karaoke", "instrumental", "(inst", "inst)", "off vocal",
            "sped up", "spedup", "slowed", "nightcore", "acoustic", "8d", "lofi", "lo-fi",
            "tribute", "piano version", "guitar version", "english ver", "english version",
            "eng ver", "english cover", "indonesian ver", "tv size", "short ver", "music box", "8-bit"
        ]
        for tag in variantTags {
            let inCandidate = normTrack.contains(tag)
            let requested = normRawAll.contains(tag) || normExpArtist.contains(tag)
            if inCandidate && !requested {
                score -= 68.0
                break
            }
        }

        // 5. Lyric line count, timestamp coverage & script-language consistency check
        if let lines = parsedLines, hasSynced {
            score += lineCoveragePenalty(lines: lines, targetDuration: targetDuration)
            score += scriptConsistencyScore(
                lines: lines,
                trackName: trackName,
                artistName: artistName,
                rawInputTitle: rawInputTitle,
                expectedTitle: expectedTitle,
                expectedArtist: expectedArtist
            )
        }

        return score
    }

    // MARK: - Tier 1: LRCLIB (Exact /get + Field /search + Full-Text ?q=)

    private func decodeLRCLIBItem(
        _ item: [String: Any],
        fallbackTrack: String,
        fallbackArtist: String,
        rawTitle: String,
        expectedTitle: String,
        expectedArtist: String,
        targetDuration: TimeInterval
    ) -> RankedCandidate? {
        let refDur = (item["duration"] as? Double) ?? targetDuration
        let trName = (item["trackName"] as? String) ?? fallbackTrack
        let arName = (item["artistName"] as? String) ?? fallbackArtist
        if let synced = item["syncedLyrics"] as? String, !synced.isEmpty {
            let parsed = Self.parseLRCWithMeta(synced)
            guard !parsed.lines.isEmpty else { return nil }
            let sc = Self.scoreCandidate(
                trackName: trName, artistName: arName,
                rawInputTitle: rawTitle,
                expectedTitle: expectedTitle, expectedArtist: expectedArtist,
                refDuration: refDur, targetDuration: targetDuration,
                hasSynced: true, hasWordTimings: parsed.hasWordTimings,
                parsedLines: parsed.lines
            )
            return RankedCandidate(
                lines: parsed.lines,
                sourceName: parsed.hasWordTimings ? "LRCLIB (Kata)" : "LRCLIB",
                isEstimated: false,
                hasWordTimings: parsed.hasWordTimings,
                referenceDuration: refDur,
                matchScore: sc
            )
        } else if let plain = item["plainLyrics"] as? String, !plain.isEmpty {
            let est = Self.distributePlainLyrics(plain, duration: max(60, refDur))
            let sc = Self.scoreCandidate(
                trackName: trName, artistName: arName,
                rawInputTitle: rawTitle,
                expectedTitle: expectedTitle, expectedArtist: expectedArtist,
                refDuration: refDur, targetDuration: targetDuration,
                hasSynced: false, hasWordTimings: false
            )
            return RankedCandidate(
                lines: est,
                sourceName: "LRCLIB (Estimasi)",
                isEstimated: true,
                hasWordTimings: false,
                referenceDuration: refDur,
                matchScore: sc
            )
        }
        return nil
    }

    private func fetchLRCLIBCandidates(
        token: UUID,
        candidates: [(track: String, artist: String)],
        album: String,
        rawTitle: String,
        expectedTitle: String,
        expectedArtist: String,
        targetDuration: TimeInterval,
        onBatch: @escaping ([RankedCandidate]) -> Void,
        completion: @escaping () -> Void
    ) {
        let localGroup = DispatchGroup()

        if let first = candidates.first,
           !first.artist.isEmpty,
           let tEnc = first.track.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let aEnc = first.artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            let durParam = targetDuration > 15 ? "&duration=\(Int(round(targetDuration)))" : ""
            let cleanAlb = album.trimmingCharacters(in: .whitespacesAndNewlines)
            let albParam = (!cleanAlb.isEmpty ? (cleanAlb.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).map { "&album_name=\($0)" } ?? "") : "")
            if let url = URL(string: "https://lrclib.net/api/get?track_name=\(tEnc)&artist_name=\(aEnc)\(albParam)\(durParam)") {
                localGroup.enter()
                startManagedTask(url: url, token: token) { [weak self] data, _, _ in
                    defer { localGroup.leave() }
                    guard let self = self, let data = data,
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let cand = self.decodeLRCLIBItem(json, fallbackTrack: first.track, fallbackArtist: first.artist, rawTitle: rawTitle, expectedTitle: expectedTitle, expectedArtist: expectedArtist, targetDuration: targetDuration) else { return }
                    onBatch([cand])
                }
            }
        }

        var builtURLs: [URL] = []
        func appendURL(_ url: URL?) {
            guard let url = url, !builtURLs.contains(url) else { return }
            builtURLs.append(url)
        }

        if let first = candidates.first {
            if !first.artist.isEmpty,
               let tEnc = first.track.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let aEnc = first.artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                appendURL(URL(string: "https://lrclib.net/api/search?track_name=\(tEnc)&artist_name=\(aEnc)"))
            }
            let combined = first.artist.isEmpty ? first.track : "\(first.track) \(first.artist)"
            if let qEnc = combined.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                appendURL(URL(string: "https://lrclib.net/api/search?q=\(qEnc)"))
            }
        }

        for cand in candidates.dropFirst().prefix(3) {
            let q = cand.artist.isEmpty ? cand.track : "\(cand.track) \(cand.artist)"
            if let qEnc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                appendURL(URL(string: "https://lrclib.net/api/search?q=\(qEnc)"))
            }
        }

        for url in builtURLs.prefix(4) {
            localGroup.enter()
            startManagedTask(url: url, token: token) { [weak self] data, _, _ in
                defer { localGroup.leave() }
                guard let self = self, let data = data,
                      let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
                let items = arr.prefix(10).compactMap {
                    self.decodeLRCLIBItem($0, fallbackTrack: expectedTitle, fallbackArtist: expectedArtist, rawTitle: rawTitle, expectedTitle: expectedTitle, expectedArtist: expectedArtist, targetDuration: targetDuration)
                }
                if !items.isEmpty { onBatch(items) }
            }
        }

        localGroup.notify(queue: DispatchQueue.global(qos: .userInitiated)) {
            completion()
        }
    }

    // MARK: - Tier 2: NetEase Cloud Music (Multi-Candidate YRC Word-Timing + LRC)

    private func fetchNetEaseCandidates(
        token: UUID,
        candidates: [(track: String, artist: String)],
        rawTitle: String,
        expectedTitle: String,
        expectedArtist: String,
        targetDuration: TimeInterval,
        onBatch: @escaping ([RankedCandidate]) -> Void,
        completion: @escaping () -> Void
    ) {
        let queries = Array(candidates.prefix(2))
        guard !queries.isEmpty else {
            completion()
            return
        }

        let outerGroup = DispatchGroup()
        let seenLock = NSLock()
        var seenSongIDs = Set<Int>()

        for cand in queries {
            let q = cand.artist.isEmpty ? cand.track : "\(cand.track) \(cand.artist)"
            guard let qEnc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let searchURL = URL(string: "https://music.163.com/api/search/get?s=\(qEnc)&type=1&limit=8") else {
                continue
            }

            outerGroup.enter()
            startManagedTask(url: searchURL, token: token, headers: ["User-Agent": "Mozilla/5.0"]) { [weak self] data, _, _ in
                guard let self = self,
                      let data = data,
                      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let res = root["result"] as? [String: Any],
                      let songs = res["songs"] as? [[String: Any]], !songs.isEmpty else {
                    outerGroup.leave()
                    return
                }

                let topSongs = songs.sorted { a, b in
                    let durA = (a["duration"] as? Double ?? 0) / 1000.0
                    let durB = (b["duration"] as? Double ?? 0) / 1000.0
                    let nameA = (a["name"] as? String) ?? ""
                    let nameB = (b["name"] as? String) ?? ""
                    let artA = ((a["artists"] as? [[String: Any]])?.first?["name"] as? String) ?? ""
                    let artB = ((b["artists"] as? [[String: Any]])?.first?["name"] as? String) ?? ""
                    let sA = Self.scoreCandidate(trackName: nameA, artistName: artA, rawInputTitle: rawTitle, expectedTitle: expectedTitle, expectedArtist: expectedArtist, refDuration: durA, targetDuration: targetDuration, hasSynced: true, hasWordTimings: false)
                    let sB = Self.scoreCandidate(trackName: nameB, artistName: artB, rawInputTitle: rawTitle, expectedTitle: expectedTitle, expectedArtist: expectedArtist, refDuration: durB, targetDuration: targetDuration, hasSynced: true, hasWordTimings: false)
                    return sA > sB
                }.prefix(3)

                for song in topSongs {
                    guard let songID = song["id"] as? Int else { continue }
                    seenLock.lock()
                    let isNew = seenSongIDs.insert(songID).inserted
                    seenLock.unlock()
                    guard isNew else { continue }

                    let sName = (song["name"] as? String) ?? ""
                    let artistsArr = song["artists"] as? [[String: Any]]
                    let sArtist = (artistsArr?.first?["name"] as? String) ?? ""
                    let sDur = (song["duration"] as? Double ?? 0) / 1000.0
                    let refDur = sDur > 10 ? sDur : targetDuration

                    outerGroup.enter()
                    self.fetchNetEaseLyricPayload(songID: songID, token: token) { yrcStr, lrcStr in
                        defer { outerGroup.leave() }
                        var localItems: [RankedCandidate] = []

                        if let yrc = yrcStr, !yrc.isEmpty {
                            let yrcLines = Self.parseYRC(yrc)
                            if !yrcLines.isEmpty {
                                let sc = Self.scoreCandidate(
                                    trackName: sName, artistName: sArtist,
                                    rawInputTitle: rawTitle,
                                    expectedTitle: expectedTitle, expectedArtist: expectedArtist,
                                    refDuration: refDur, targetDuration: targetDuration,
                                    hasSynced: true, hasWordTimings: true,
                                    parsedLines: yrcLines
                                )
                                localItems.append(RankedCandidate(
                                    lines: yrcLines,
                                    sourceName: "NetEase YRC (Per Kata)",
                                    isEstimated: false,
                                    hasWordTimings: true,
                                    referenceDuration: refDur,
                                    matchScore: sc
                                ))
                            }
                        }

                        if let lrc = lrcStr, !lrc.isEmpty {
                            let parsed = Self.parseLRCWithMeta(lrc)
                            if !parsed.lines.isEmpty {
                                let sc = Self.scoreCandidate(
                                    trackName: sName, artistName: sArtist,
                                    rawInputTitle: rawTitle,
                                    expectedTitle: expectedTitle, expectedArtist: expectedArtist,
                                    refDuration: refDur, targetDuration: targetDuration,
                                    hasSynced: true, hasWordTimings: parsed.hasWordTimings,
                                    parsedLines: parsed.lines
                                )
                                localItems.append(RankedCandidate(
                                    lines: parsed.lines,
                                    sourceName: "NetEase LRC",
                                    isEstimated: false,
                                    hasWordTimings: parsed.hasWordTimings,
                                    referenceDuration: refDur,
                                    matchScore: sc
                                ))
                            }
                        }
                        if !localItems.isEmpty { onBatch(localItems) }
                    }
                }
                outerGroup.leave()
            }
        }

        outerGroup.notify(queue: DispatchQueue.global(qos: .userInitiated)) {
            completion()
        }
    }

    private func fetchNetEaseLyricPayload(songID: Int, token: UUID, completion: @escaping (String?, String?) -> Void) {
        guard let url = URL(string: "https://music.163.com/api/song/lyric?os=pc&id=\(songID)&lv=-1&yv=-1") else {
            completion(nil, nil)
            return
        }
        startManagedTask(url: url, token: token, headers: ["User-Agent": "Mozilla/5.0"]) { data, _, _ in
            guard let data = data,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(nil, nil)
                return
            }
            let yrcStr = (root["yrc"] as? [String: Any])?["lyric"] as? String
            let lrcStr = (root["lrc"] as? [String: Any])?["lyric"] as? String
            completion(yrcStr, lrcStr)
        }
    }

    // MARK: - Tier 1C: Kugou Music (Fast Synced LRC for Global / J-Pop / K-Pop / SEA)

    private func fetchKugouCandidates(
        token: UUID,
        candidates: [(track: String, artist: String)],
        rawTitle: String,
        expectedTitle: String,
        expectedArtist: String,
        targetDuration: TimeInterval,
        onBatch: @escaping ([RankedCandidate]) -> Void,
        completion: @escaping () -> Void
    ) {
        guard let cand = candidates.first else {
            completion()
            return
        }
        let keyword = cand.artist.isEmpty ? cand.track : "\(cand.artist) - \(cand.track)"
        guard let kEnc = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "https://lyrics.kugou.com/search?ver=1&man=yes&client=pc&keyword=\(kEnc)&duration=\(Int(max(0, targetDuration) * 1000))") else {
            completion()
            return
        }

        let kgGroup = DispatchGroup()
        kgGroup.enter()
        startManagedTask(url: searchURL, token: token, headers: ["User-Agent": "Mozilla/5.0"]) { [weak self] data, _, _ in
            guard let self = self,
                  let data = data,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = root["candidates"] as? [[String: Any]], !list.isEmpty else {
                kgGroup.leave()
                return
            }

            let ranked = list.sorted { a, b in
                let dA = (a["duration"] as? Double ?? 0) / 1000.0
                let dB = (b["duration"] as? Double ?? 0) / 1000.0
                let sA = Self.scoreCandidate(
                    trackName: (a["song"] as? String) ?? "",
                    artistName: (a["singer"] as? String) ?? "",
                    rawInputTitle: rawTitle,
                    expectedTitle: expectedTitle,
                    expectedArtist: expectedArtist,
                    refDuration: dA,
                    targetDuration: targetDuration,
                    hasSynced: true,
                    hasWordTimings: false
                )
                let sB = Self.scoreCandidate(
                    trackName: (b["song"] as? String) ?? "",
                    artistName: (b["singer"] as? String) ?? "",
                    rawInputTitle: rawTitle,
                    expectedTitle: expectedTitle,
                    expectedArtist: expectedArtist,
                    refDuration: dB,
                    targetDuration: targetDuration,
                    hasSynced: true,
                    hasWordTimings: false
                )
                return sA > sB
            }.prefix(2)

            for item in ranked {
                guard let cid = item["id"] as? String,
                      let accessKey = item["accesskey"] as? String,
                      let dlURL = URL(string: "https://lyrics.kugou.com/download?ver=1&client=pc&id=\(cid)&accesskey=\(accessKey)&fmt=lrc&charset=utf8") else {
                    continue
                }
                let sName = (item["song"] as? String) ?? expectedTitle
                let sArtist = (item["singer"] as? String) ?? expectedArtist
                let refDur = ((item["duration"] as? Double) ?? 0) / 1000.0

                kgGroup.enter()
                self.startManagedTask(url: dlURL, token: token, headers: ["User-Agent": "Mozilla/5.0"]) { dData, _, _ in
                    defer { kgGroup.leave() }
                    guard let dData = dData,
                          let dJson = try? JSONSerialization.jsonObject(with: dData) as? [String: Any],
                          let b64 = dJson["content"] as? String,
                          let rawBytes = Data(base64Encoded: b64),
                          var lrc = String(data: rawBytes, encoding: .utf8) else {
                        return
                    }
                    lrc = lrc.replacingOccurrences(of: "\u{FEFF}", with: "")
                    let parsed = Self.parseLRCWithMeta(lrc)
                    guard !parsed.lines.isEmpty else { return }
                    let durVal = refDur > 10 ? refDur : targetDuration
                    let sc = Self.scoreCandidate(
                        trackName: sName,
                        artistName: sArtist,
                        rawInputTitle: rawTitle,
                        expectedTitle: expectedTitle,
                        expectedArtist: expectedArtist,
                        refDuration: durVal,
                        targetDuration: targetDuration,
                        hasSynced: true,
                        hasWordTimings: parsed.hasWordTimings,
                        parsedLines: parsed.lines
                    )
                    onBatch([RankedCandidate(
                        lines: parsed.lines,
                        sourceName: "Kugou LRC",
                        isEstimated: false,
                        hasWordTimings: parsed.hasWordTimings,
                        referenceDuration: durVal,
                        matchScore: sc
                    )])
                }
            }
            kgGroup.leave()
        }

        kgGroup.notify(queue: DispatchQueue.global(qos: .userInitiated)) {
            completion()
        }
    }

    // MARK: - Tier 1D: Kuwo Music (Synced LRC Fallback for Asian / Global Catalogs)

    private func fetchKuwoCandidates(
        token: UUID,
        candidates: [(track: String, artist: String)],
        rawTitle: String,
        expectedTitle: String,
        expectedArtist: String,
        targetDuration: TimeInterval,
        onBatch: @escaping ([RankedCandidate]) -> Void,
        completion: @escaping () -> Void
    ) {
        guard let cand = candidates.first else {
            completion()
            return
        }
        let keyword = cand.artist.isEmpty ? cand.track : "\(cand.track) \(cand.artist)"
        guard let kEnc = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "https://search.kuwo.cn/r.s?all=\(kEnc)&ft=music&pn=0&rn=4&rformat=json&encoding=utf8") else {
            completion()
            return
        }

        let kwGroup = DispatchGroup()
        kwGroup.enter()
        startManagedTask(url: searchURL, token: token, headers: ["User-Agent": "Mozilla/5.0"]) { [weak self] data, _, _ in
            guard let self = self,
                  let data = data,
                  let body = String(data: data, encoding: .utf8),
                  !body.isEmpty else {
                kwGroup.leave()
                return
            }

            func firstCapture(_ pattern: String, in text: String) -> String? {
                guard let rx = try? NSRegularExpression(pattern: pattern),
                      let match = rx.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                      let range = Range(match.range(at: 1), in: text) else { return nil }
                return String(text[range])
            }

            let chunks = body.components(separatedBy: "{'")
            var parsedItems: [(rid: String, song: String, artist: String, dur: TimeInterval, preScore: Double)] = []
            for chunk in chunks where chunk.contains("MUSIC_") {
                guard let rid = firstCapture("MUSIC_(\\d+)", in: chunk) else { continue }
                let sName = firstCapture("'SONGNAME':'([^']*)'", in: chunk) ?? expectedTitle
                let sArtist = (firstCapture("'ARTIST':'([^']*)'", in: chunk) ?? expectedArtist)
                    .replacingOccurrences(of: "&", with: ", ")
                let dur = Double(firstCapture("'DURATION':'(\\d+)'", in: chunk) ?? "") ?? 0
                let pre = Self.scoreCandidate(
                    trackName: sName,
                    artistName: sArtist,
                    rawInputTitle: rawTitle,
                    expectedTitle: expectedTitle,
                    expectedArtist: expectedArtist,
                    refDuration: dur,
                    targetDuration: targetDuration,
                    hasSynced: true,
                    hasWordTimings: false
                )
                parsedItems.append((rid, sName, sArtist, dur, pre))
            }

            let topHits = parsedItems.sorted { $0.preScore > $1.preScore }.prefix(2)
            for item in topHits {
                guard let lrcURL = URL(string: "https://m.kuwo.cn/newh5/singles/songinfoandlrc?musicId=\(item.rid)") else {
                    continue
                }
                kwGroup.enter()
                self.startManagedTask(url: lrcURL, token: token, headers: ["User-Agent": "Mozilla/5.0"]) { lData, _, _ in
                    defer { kwGroup.leave() }
                    guard let lData = lData,
                          let root = try? JSONSerialization.jsonObject(with: lData) as? [String: Any],
                          let dataObj = root["data"] as? [String: Any],
                          let lrcList = dataObj["lrclist"] as? [[String: Any]], !lrcList.isEmpty else {
                        return
                    }

                    var lrcLinesText: [String] = []
                    for (idx, row) in lrcList.enumerated() {
                        let txt = ((row["lineLyric"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let timeStr = (row["time"] as? String) ?? ""
                        guard !txt.isEmpty, let tVal = Double(timeStr), tVal >= 0 else { continue }
                        if idx == 0 && (txt.contains("词：") || txt.contains("曲：") || txt.contains(" - ")) {
                            continue
                        }
                        let mins = Int(tVal) / 60
                        let secs = tVal - Double(mins * 60)
                        lrcLinesText.append(String(format: "[%02d:%06.3f]%@", mins, secs, txt))
                    }
                    guard !lrcLinesText.isEmpty else { return }

                    let parsed = Self.parseLRCWithMeta(lrcLinesText.joined(separator: "\n"))
                    guard !parsed.lines.isEmpty else { return }
                    let durVal = item.dur > 10 ? item.dur : targetDuration
                    let sc = Self.scoreCandidate(
                        trackName: item.song,
                        artistName: item.artist,
                        rawInputTitle: rawTitle,
                        expectedTitle: expectedTitle,
                        expectedArtist: expectedArtist,
                        refDuration: durVal,
                        targetDuration: targetDuration,
                        hasSynced: true,
                        hasWordTimings: parsed.hasWordTimings,
                        parsedLines: parsed.lines
                    )
                    onBatch([RankedCandidate(
                        lines: parsed.lines,
                        sourceName: "Kuwo LRC",
                        isEstimated: false,
                        hasWordTimings: parsed.hasWordTimings,
                        referenceDuration: durVal,
                        matchScore: sc
                    )])
                }
            }
            kwGroup.leave()
        }

        kwGroup.notify(queue: DispatchQueue.global(qos: .userInitiated)) {
            completion()
        }
    }

    // MARK: - Tier 2B & 3: iTunes + Deezer Canonical Track Resolver + Lyrics.ovh Fallback

    private func recoverViaCanonicalMetadataAndPlainFallback(
        token: UUID,
        candidates: [(track: String, artist: String)],
        rawTitle: String,
        expectedTitle: String,
        expectedArtist: String,
        targetDuration: TimeInterval,
        existingEstimated: RankedCandidate?,
        completion: @escaping (RankedCandidate?) -> Void
    ) {
        let searchTerm = [expectedTitle, expectedArtist].filter { !$0.isEmpty }.joined(separator: " ")
        guard !searchTerm.isEmpty,
              let termEnc = searchTerm.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let itunesURL = URL(string: "https://itunes.apple.com/search?term=\(termEnc)&media=music&entity=song&limit=4") else {
            tryLyricsOVH(token: token, candidates: candidates, targetDuration: targetDuration) { ovh in
                completion(existingEstimated ?? ovh)
            }
            return
        }
        let deezerURL = URL(string: "https://api.deezer.com/search?q=\(termEnc)&limit=4")

        let metaGroup = DispatchGroup()
        let mLock = NSLock()
        var metaHits: [(track: String, artist: String, score: Double)] = []

        metaGroup.enter()
        startManagedTask(url: itunesURL, token: token) { [weak self] data, _, _ in
            defer { metaGroup.leave() }
            guard let self = self,
                  let data = data,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = root["results"] as? [[String: Any]] else { return }
            var local: [(track: String, artist: String, score: Double)] = []
            for item in results {
                let tn = self.cleanTitle((item["trackName"] as? String) ?? "")
                let an = self.cleanArtist((item["artistName"] as? String) ?? "")
                guard !tn.isEmpty, !an.isEmpty else { continue }
                let dur = (item["trackTimeMillis"] as? Double ?? 0) / 1000.0
                let sc = Self.scoreCandidate(
                    trackName: tn, artistName: an,
                    rawInputTitle: rawTitle, expectedTitle: expectedTitle, expectedArtist: expectedArtist,
                    refDuration: dur, targetDuration: targetDuration, hasSynced: true, hasWordTimings: false
                )
                local.append((tn, an, sc))
            }
            mLock.lock()
            metaHits.append(contentsOf: local)
            mLock.unlock()
        }

        if let deezerURL = deezerURL {
            metaGroup.enter()
            startManagedTask(url: deezerURL, token: token) { [weak self] data, _, _ in
                defer { metaGroup.leave() }
                guard let self = self,
                      let data = data,
                      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let results = root["data"] as? [[String: Any]] else { return }
                var local: [(track: String, artist: String, score: Double)] = []
                for item in results {
                    let tn = self.cleanTitle((item["title"] as? String) ?? "")
                    let an = self.cleanArtist(((item["artist"] as? [String: Any])?["name"] as? String) ?? "")
                    guard !tn.isEmpty, !an.isEmpty else { continue }
                    let dur = item["duration"] as? Double ?? 0
                    let sc = Self.scoreCandidate(
                        trackName: tn, artistName: an,
                        rawInputTitle: rawTitle, expectedTitle: expectedTitle, expectedArtist: expectedArtist,
                        refDuration: dur, targetDuration: targetDuration, hasSynced: true, hasWordTimings: false
                    )
                    local.append((tn, an, sc))
                }
                mLock.lock()
                metaHits.append(contentsOf: local)
                mLock.unlock()
            }
        }

        metaGroup.notify(queue: DispatchQueue.global(qos: .userInitiated)) { [weak self] in
            guard let self = self, self.isTokenCurrent(token) else { return }
            mLock.lock()
            let sortedHits = metaHits.sorted { $0.score > $1.score }
            mLock.unlock()

            var seen = Set<String>()
            var repairedPairs: [(track: String, artist: String)] = []
            for h in sortedHits {
                let k = "\(h.track.lowercased())|\(h.artist.lowercased())"
                if seen.insert(k).inserted {
                    repairedPairs.append((h.track, h.artist))
                    if repairedPairs.count >= 3 { break }
                }
            }

            guard let canonical = repairedPairs.first else {
                self.tryLyricsOVH(token: token, candidates: candidates, targetDuration: targetDuration) { ovh in
                    completion(existingEstimated ?? ovh)
                }
                return
            }

            let secondGroup = DispatchGroup()
            let rLock = NSLock()
            var recoveredPool: [RankedCandidate] = []
            let ingestRecovered: ([RankedCandidate]) -> Void = { batch in
                rLock.lock()
                recoveredPool.append(contentsOf: batch)
                rLock.unlock()
            }

            secondGroup.enter()
            self.fetchLRCLIBCandidates(
                token: token,
                candidates: repairedPairs,
                album: "",
                rawTitle: rawTitle,
                expectedTitle: canonical.track,
                expectedArtist: canonical.artist,
                targetDuration: targetDuration,
                onBatch: ingestRecovered,
                completion: { secondGroup.leave() }
            )

            secondGroup.enter()
            self.fetchKugouCandidates(
                token: token,
                candidates: repairedPairs,
                rawTitle: rawTitle,
                expectedTitle: canonical.track,
                expectedArtist: canonical.artist,
                targetDuration: targetDuration,
                onBatch: ingestRecovered,
                completion: { secondGroup.leave() }
            )

            secondGroup.enter()
            self.fetchKuwoCandidates(
                token: token,
                candidates: repairedPairs,
                rawTitle: rawTitle,
                expectedTitle: canonical.track,
                expectedArtist: canonical.artist,
                targetDuration: targetDuration,
                onBatch: ingestRecovered,
                completion: { secondGroup.leave() }
            )

            secondGroup.notify(queue: DispatchQueue.global(qos: .userInitiated)) {
                guard self.isTokenCurrent(token) else { return }
                rLock.lock()
                let syncedHit = recoveredPool.filter { !$0.isEstimated && $0.matchScore >= 65.0 }.max(by: { $0.matchScore < $1.matchScore })
                let estHit = recoveredPool.filter { $0.matchScore >= 15.0 }.max(by: { $0.matchScore < $1.matchScore })
                rLock.unlock()

                if let best = syncedHit {
                    completion(best)
                    return
                }
                self.tryLyricsOVH(token: token, candidates: repairedPairs + candidates, targetDuration: targetDuration) { ovh in
                    completion(estHit ?? existingEstimated ?? ovh)
                }
            }
        }
    }

    private func tryLyricsOVH(
        token: UUID,
        candidates: [(track: String, artist: String)],
        targetDuration: TimeInterval,
        completion: @escaping (RankedCandidate?) -> Void
    ) {
        guard let cand = candidates.first(where: { !$0.artist.isEmpty }),
              let aEnc = cand.artist.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let tEnc = cand.track.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.lyrics.ovh/v1/\(aEnc)/\(tEnc)") else {
            completion(nil)
            return
        }

        startManagedTask(url: url, token: token) { data, _, _ in
            guard let data = data,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let plain = root["lyrics"] as? String, !plain.isEmpty else {
                completion(nil)
                return
            }
            let est = Self.distributePlainLyrics(plain, duration: max(60, targetDuration))
            completion(RankedCandidate(
                lines: est,
                sourceName: "Lyrics.ovh (Estimasi)",
                isEstimated: true,
                hasWordTimings: false,
                referenceDuration: targetDuration,
                matchScore: 20.0
            ))
        }
    }

    // MARK: - Word-Timed NetEase YRC Parser

    static func parseYRC(_ yrc: String) -> [LyricLine] {
        guard let headerRegex = try? NSRegularExpression(pattern: #"^\[(\d+),(\d+)\]"#),
              let wordRegex = try? NSRegularExpression(pattern: #"\((\d+),(\d+),\d+\)(.*?)(?=\(\d+,\d+,\d+\)|$)"#) else {
            return []
        }

        var result: [LyricLine] = []
        let creditPrefixes = ["作词", "作曲", "编曲", "制作人", "混音", "母带", "和声", "吉他", "贝斯", "鼓", "录音"]

        for rawLine in yrc.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("{") { continue }

            let nsLine = trimmed as NSString
            guard let hMatch = headerRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: nsLine.length)) else {
                continue
            }
            let lineStartMs = Double(nsLine.substring(with: hMatch.range(at: 1))) ?? 0
            let lineDurMs = Double(nsLine.substring(with: hMatch.range(at: 2))) ?? 0
            let bodyStart = hMatch.range.location + hMatch.range.length
            let bodyRange = NSRange(location: bodyStart, length: nsLine.length - bodyStart)

            let matches = wordRegex.matches(in: trimmed, range: bodyRange)
            var rawWords: [LyricWord] = []
            for m in matches {
                let wStart = (Double(nsLine.substring(with: m.range(at: 1))) ?? lineStartMs) / 1000.0
                let wDur = max(0.05, (Double(nsLine.substring(with: m.range(at: 2))) ?? 200.0) / 1000.0)
                let txt = nsLine.substring(with: m.range(at: 3))
                if !txt.isEmpty {
                    rawWords.append(LyricWord(time: wStart, duration: wDur, text: txt))
                }
            }
            guard !rawWords.isEmpty else { continue }

            let joinedText = rawWords.map { $0.text }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            if joinedText.isEmpty { continue }
            if creditPrefixes.contains(where: { joinedText.hasPrefix($0) }) { continue }
            if joinedText.lowercased().contains("instrumental music") { continue }

            // Split oversized YRC sentences into Touch Bar-friendly clauses while keeping parenthetical backing attached
            var chunks: [[LyricWord]] = []
            var currentChunk: [LyricWord] = []
            var currentLen = 0
            var parenDepth = 0
            for (idx, w) in rawWords.enumerated() {
                currentChunk.append(w)
                currentLen += w.text.count
                for ch in w.text {
                    if ch == "(" { parenDepth += 1 }
                    else if ch == ")" && parenDepth > 0 { parenDepth -= 1 }
                }
                let endedClause = w.text.contains(",") || w.text.contains(";") || w.text.contains("?") || w.text.contains("!")
                let nextExists = idx + 1 < rawWords.count
                let nextStartsParen = nextExists && rawWords[idx + 1].text.trimmingCharacters(in: .whitespaces).hasPrefix("(")
                let timeGapAfter = nextExists ? (rawWords[idx + 1].time - (w.time + w.duration)) : 0
                if nextExists && parenDepth == 0 && !nextStartsParen && ((endedClause && currentLen >= 18) || currentLen >= 42 || timeGapAfter >= 0.85) {
                    chunks.append(currentChunk)
                    currentChunk = []
                    currentLen = 0
                }
            }
            if !currentChunk.isEmpty {
                chunks.append(currentChunk)
            }

            for chunk in chunks {
                let chunkRaw = chunk.map { $0.text }.joined()
                let split = splitMainAndBackingWithMeta(chunkRaw)
                if split.main.isEmpty && (split.backing ?? "").isEmpty { continue }

                let chunkStart = chunk.first?.time ?? (lineStartMs / 1000.0)
                let lastW = chunk.last
                let chunkEnd = lastW.map { $0.time + $0.duration } ?? ((lineStartMs + lineDurMs) / 1000.0)

                let splitWords = Self.splitWordsMainAndBacking(words: chunk, hasBacking: !(split.backing ?? "").isEmpty)
                let mainStart = splitWords.main.first?.time ?? chunkStart
                let mainEnd = splitWords.main.last.map { $0.time + $0.duration } ?? chunkEnd
                let bgStart = splitWords.backing.first?.time
                let bgEnd = splitWords.backing.last.map { $0.time + $0.duration }

                result.append(LyricLine(
                    time: mainStart,
                    endTime: max(mainStart + 0.3, mainEnd),
                    backingTime: bgStart,
                    backingEndTime: bgEnd,
                    mainText: split.main,
                    backingText: split.backing,
                    backingIsSuffix: split.backingAtEnd,
                    words: splitWords.main,
                    backingWords: splitWords.backing
                ))
            }
        }

        return result.sorted { $0.time < $1.time }
    }

    private static func splitWordsMainAndBacking(words: [LyricWord], hasBacking: Bool) -> (main: [LyricWord], backing: [LyricWord]) {
        guard hasBacking else { return (words, []) }
        var insideParen = false
        var mainList: [LyricWord] = []
        var backList: [LyricWord] = []
        for w in words {
            var mainBuf = ""
            var backBuf = ""
            for ch in w.text {
                if ch == "(" {
                    insideParen = true
                } else if ch == ")" {
                    insideParen = false
                } else if insideParen {
                    backBuf.append(ch)
                } else {
                    mainBuf.append(ch)
                }
            }
            if !mainBuf.trimmingCharacters(in: .whitespaces).isEmpty || (mainBuf == " " && !mainList.isEmpty) {
                mainList.append(LyricWord(time: w.time, duration: w.duration, text: mainBuf))
            }
            if !backBuf.trimmingCharacters(in: .whitespaces).isEmpty || (backBuf == " " && !backList.isEmpty) {
                backList.append(LyricWord(time: w.time, duration: w.duration, text: backBuf))
            }
        }
        return (mainList.isEmpty ? words : mainList, backList)
    }

    // MARK: - LRC & Enhanced LRC Parsing

    static func parseLRC(_ lrc: String) -> [LyricLine] {
        return parseLRCWithMeta(lrc).lines
    }

    private static func parseLRCWithMeta(_ lrc: String) -> (lines: [LyricLine], hasWordTimings: Bool) {
        var rawEntries: [(TimeInterval, String)] = []
        var pauseBoundaries: [TimeInterval] = []
        let regex = try? NSRegularExpression(pattern: #"\[(\d{1,2}):(\d{2})(?:[\.:](\d{1,3}))?\]"#)
        var detectedEnhanced = false

        for rawLine in lrc.components(separatedBy: .newlines) {
            let nsLine = rawLine as NSString
            let range = NSRange(location: 0, length: nsLine.length)
            guard let matches = regex?.matches(in: rawLine, range: range), !matches.isEmpty,
                  let lastMatch = matches.last else { continue }

            let textStart = lastMatch.range.location + lastMatch.range.length
            let text = nsLine.substring(from: textStart).trimmingCharacters(in: .whitespacesAndNewlines)

            for m in matches {
                let minStr = nsLine.substring(with: m.range(at: 1))
                let secStr = nsLine.substring(with: m.range(at: 2))
                let fracRange = m.range(at: 3)
                var frac = 0.0
                if fracRange.location != NSNotFound {
                    let fracStr = nsLine.substring(with: fracRange)
                    let div = fracStr.count == 3 ? 1000.0 : (fracStr.count == 2 ? 100.0 : 10.0)
                    frac = (Double(fracStr) ?? 0) / div
                }
                let time = (Double(minStr) ?? 0) * 60.0 + (Double(secStr) ?? 0) + frac
                if text.isEmpty {
                    // Preserve empty LRC timestamps as explicit instrumental/breath end markers
                    pauseBoundaries.append(time)
                } else if !text.hasPrefix("作词") && !text.hasPrefix("作曲") && !text.hasPrefix("编曲") && !text.hasPrefix("制作人") {
                    rawEntries.append((time, text))
                }
            }
        }

        rawEntries.sort { $0.0 < $1.0 }
        pauseBoundaries.sort()

        func clampedEnd(from start: TimeInterval, fallbackNext: TimeInterval?) -> TimeInterval? {
            guard let p = pauseBoundaries.first(where: { $0 > start + 0.35 }) else { return nil }
            if let nxt = fallbackNext, p >= nxt { return nil }
            return p
        }

        var parsed: [LyricLine] = []
        var i = 0
        while i < rawEntries.count {
            let (t1, text1) = rawEntries[i]

            if i + 1 < rawEntries.count {
                let (t2, text2) = rawEntries[i + 1]
                let gap = t2 - t1
                let s1 = splitEnhancedAndBacking(lineTime: t1, raw: text1)
                let s2 = splitEnhancedAndBacking(lineTime: t2, raw: text2)
                if !s1.words.isEmpty || !s2.words.isEmpty { detectedEnhanced = true }

                // Simultaneous OR call-and-response backing line arriving up to 3.2s after main phrase
                if !s1.main.isEmpty && s2.main.isEmpty, let bg2 = s2.backing, gap >= 0, gap <= 3.2 {
                    let endBoundary = clampedEnd(from: t1, fallbackNext: (i + 2 < rawEntries.count) ? rawEntries[i + 2].0 : nil)
                    parsed.append(LyricLine(
                        time: t1,
                        endTime: endBoundary,
                        backingTime: t2,
                        mainText: s1.main,
                        backingText: mergeBacking(s1.backing, bg2),
                        backingIsSuffix: gap > 0.35 || s1.backingAtEnd,
                        words: s1.words,
                        backingWords: s2.backingWords
                    ))
                    i += 2
                    continue
                } else if s1.main.isEmpty, let bg1 = s1.backing, !s2.main.isEmpty, gap <= 0.40 {
                    let endBoundary = clampedEnd(from: t2, fallbackNext: (i + 2 < rawEntries.count) ? rawEntries[i + 2].0 : nil)
                    parsed.append(LyricLine(
                        time: t2,
                        endTime: endBoundary,
                        backingTime: t1,
                        mainText: s2.main,
                        backingText: mergeBacking(bg1, s2.backing),
                        backingIsSuffix: s2.backingAtEnd,
                        words: s2.words,
                        backingWords: s1.backingWords
                    ))
                    i += 2
                    continue
                } else if !s1.main.isEmpty && !s2.main.isEmpty && gap <= 0.14 && s2.main.count < s1.main.count {
                    // Only collapse unparenthesized simultaneous harmony pairs (<140ms) so fast chorus lines stay distinct
                    let endBoundary = clampedEnd(from: t1, fallbackNext: (i + 2 < rawEntries.count) ? rawEntries[i + 2].0 : nil)
                    parsed.append(LyricLine(
                        time: t1,
                        endTime: endBoundary,
                        backingTime: t2,
                        mainText: s1.main,
                        backingText: s2.main,
                        backingIsSuffix: false,
                        words: s1.words,
                        backingWords: s2.words
                    ))
                    i += 2
                    continue
                }
            }

            let split = splitEnhancedAndBacking(lineTime: t1, raw: text1)
            if !split.words.isEmpty { detectedEnhanced = true }
            if !split.main.isEmpty || !(split.backing ?? "").isEmpty {
                let nxtTime = (i + 1 < rawEntries.count) ? rawEntries[i + 1].0 : nil
                let endBoundary = clampedEnd(from: t1, fallbackNext: nxtTime)
                parsed.append(LyricLine(
                    time: t1,
                    endTime: endBoundary,
                    backingTime: split.backingWords.first?.time,
                    backingEndTime: split.backingWords.last.map { $0.time + $0.duration },
                    mainText: split.main,
                    backingText: split.backing,
                    backingIsSuffix: split.backingAtEnd,
                    words: split.words,
                    backingWords: split.backingWords
                ))
            }
            i += 1
        }
        return (parsed, detectedEnhanced)
    }

    private static func splitEnhancedAndBacking(lineTime: TimeInterval, raw: String) -> (main: String, backing: String?, backingAtEnd: Bool, words: [LyricWord], backingWords: [LyricWord]) {
        if let enhRegex = try? NSRegularExpression(pattern: #"<(\d{1,2}):(\d{2})(?:[\.:](\d{1,3}))?>"#) {
            let ns = raw as NSString
            let matches = enhRegex.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            if !matches.isEmpty {
                var parsedWords: [(TimeInterval, String)] = []
                for (idx, m) in matches.enumerated() {
                    let minV = Double(ns.substring(with: m.range(at: 1))) ?? 0
                    let secV = Double(ns.substring(with: m.range(at: 2))) ?? 0
                    var fracV = 0.0
                    let fr = m.range(at: 3)
                    if fr.location != NSNotFound {
                        let fs = ns.substring(with: fr)
                        fracV = (Double(fs) ?? 0) / (fs.count == 3 ? 1000.0 : (fs.count == 2 ? 100.0 : 10.0))
                    }
                    let t = minV * 60.0 + secV + fracV
                    let startLoc = m.range.location + m.range.length
                    let endLoc = (idx + 1 < matches.count) ? matches[idx + 1].range.location : ns.length
                    let txt = ns.substring(with: NSRange(location: startLoc, length: max(0, endLoc - startLoc)))
                    if !txt.isEmpty {
                        parsedWords.append((t, txt))
                    }
                }

                let strippedRaw = enhRegex.stringByReplacingMatches(in: raw, range: NSRange(location: 0, length: ns.length), withTemplate: "")
                let split = splitMainAndBackingWithMeta(strippedRaw)
                var wordList: [LyricWord] = []
                for idx in 0..<parsedWords.count {
                    let cur = parsedWords[idx]
                    let dur = (idx + 1 < parsedWords.count)
                        ? max(0.08, min(3.0, parsedWords[idx + 1].0 - cur.0))
                        : 0.45
                    wordList.append(LyricWord(time: cur.0, duration: dur, text: cur.1))
                }
                let splitW = splitWordsMainAndBacking(words: wordList, hasBacking: !(split.backing ?? "").isEmpty)
                return (split.main, split.backing, split.backingAtEnd, splitW.main, splitW.backing)
            }
        }

        let split = splitMainAndBackingWithMeta(raw)
        return (split.main, split.backing, split.backingAtEnd, [], [])
    }

    private static func mergeBacking(_ a: String?, _ b: String?) -> String? {
        let parts = [a, b].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func splitMainAndBacking(_ raw: String) -> (main: String, backing: String?) {
        let res = splitMainAndBackingWithMeta(raw)
        return (res.main, res.backing)
    }

    private static func splitMainAndBackingWithMeta(_ raw: String) -> (main: String, backing: String?, backingAtEnd: Bool) {
        var working = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var backingParts: [String] = []
        var lastExtractEndRatio = 0.0
        let totalLen = max(1, (working as NSString).length)

        if let bgRegex = try? NSRegularExpression(pattern: #"(?:\[bg:\s*([^\]]+)\]|<bg>([^<]+)</bg>)"#, options: .caseInsensitive) {
            let ns = working as NSString
            let matches = bgRegex.matches(in: working, range: NSRange(location: 0, length: ns.length))
            if !matches.isEmpty {
                for m in matches.reversed() {
                    lastExtractEndRatio = max(lastExtractEndRatio, Double(m.range.location) / Double(totalLen))
                    let g1 = m.range(at: 1)
                    let g2 = m.range(at: 2)
                    let extracted = g1.location != NSNotFound ? ns.substring(with: g1) : ns.substring(with: g2)
                    let cleaned = extracted.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleaned.isEmpty { backingParts.insert(cleaned, at: 0) }
                    working = (working as NSString).replacingCharacters(in: m.range, with: "")
                }
            }
        }

        let nonBackingMarkers: Set<String> = ["x2", "x3", "x4", "2x", "3x", "4x", "instrumental", "intro", "outro", "verse", "chorus", "bridge", "solo"]
        if let parenRegex = try? NSRegularExpression(pattern: #"\(([^()]{1,60})\)"#) {
            let ns = working as NSString
            let matches = parenRegex.matches(in: working, range: NSRange(location: 0, length: ns.length))
            var rangesToRemove: [NSRange] = []
            for m in matches {
                let inner = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                let lower = inner.lowercased()
                if inner.isEmpty || nonBackingMarkers.contains(lower) || lower.hasPrefix("verse ") || lower.hasPrefix("chorus ") {
                    continue
                }
                lastExtractEndRatio = max(lastExtractEndRatio, Double(m.range.location) / Double(max(1, ns.length)))
                backingParts.append(inner)
                rangesToRemove.append(m.range)
            }
            for r in rangesToRemove.reversed() {
                working = (working as NSString).replacingCharacters(in: r, with: "")
            }
        }

        let mainCleaned = working
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let backingJoined = backingParts.isEmpty ? nil : backingParts.joined(separator: " · ")
        let isSuffix = !mainCleaned.isEmpty && lastExtractEndRatio >= 0.42
        return (mainCleaned, backingJoined, isSuffix)
    }

    /// Synthesizes proportional syllable-weighted word timings calibrated by song-wide singing cadence
    /// so short lines before long instrumental breaks don't drag while dense choruses track vocal speed.
    static func synthesizeWordTimings(for lines: [LyricLine]) -> [LyricLine] {
        guard !lines.isEmpty else { return lines }

        func weightedUnits(_ text: String) -> (units: Double, count: Int) {
            let cjkCount = text.unicodeScalars.filter {
                (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) || (0xAC00...0xD7A3).contains($0.value)
            }.count
            let latinCount = max(0, text.count - cjkCount)
            return (Double(cjkCount) * 1.9 + Double(latinCount), text.count)
        }

        // Compute median vocal unit duration across normal-paced lines in this song
        var unitRates: [Double] = []
        for idx in 0..<lines.count where idx + 1 < lines.count {
            let gap = lines[idx + 1].time - lines[idx].time
            guard gap >= 0.8, gap <= 4.5 else { continue }
            let wu = weightedUnits(lines[idx].mainText)
            guard wu.units >= 4.0 else { continue }
            let rate = min(0.145, max(0.042, (gap * 0.82) / wu.units))
            unitRates.append(rate)
        }
        let sortedRates = unitRates.sorted()
        let rawMedianRate = sortedRates.isEmpty ? 0.078 : sortedRates[sortedRates.count / 2]
        let trackSecPerUnit = min(0.130, max(0.048, rawMedianRate))

        var out: [LyricLine] = []
        out.reserveCapacity(lines.count)

        for idx in 0..<lines.count {
            let line = lines[idx]
            let nextTime = (idx + 1 < lines.count) ? lines[idx + 1].time : (line.time + 4.5)
            let gap = max(0.6, nextTime - line.time)

            // Main phrase window & natural breath gap before next line
            let wu = weightedUnits(line.mainText)
            let speechEst = line.mainText.isEmpty ? 0.0 : max(0.65, wu.units * trackSecPerUnit)
            let breathMargin = gap >= 4.0 ? min(1.25, gap * 0.28) : min(0.38, max(0.14, gap * 0.12))
            let maxWindow = max(0.50, gap - breathMargin)
            let targetSpan = gap > 3.6
                ? min(maxWindow, max(speechEst, 1.40))
                : min(maxWindow, max(speechEst * 0.96, gap * 0.64))
            let computedMainEnd = line.endTime.map { min(maxWindow + line.time, max(line.time + 0.5, $0)) } ?? (line.time + targetSpan)
            let finalMainWords = !line.words.isEmpty
                ? line.words
                : buildWeightedWords(text: line.mainText, start: line.time, duration: max(0.5, computedMainEnd - line.time))

            // Independent Backing Vocal window & word timings
            var finalBackStart = line.backingTime
            var finalBackEnd = line.backingEndTime
            var finalBackWords = line.backingWords

            if let bg = line.backingText, !bg.isEmpty {
                let bgUnits = weightedUnits(bg).units
                let unitRate = min(0.115, max(0.055, trackSecPerUnit * 1.05))
                let estBackDur = max(0.60, min(gap * 0.78, bgUnits * unitRate))
                if finalBackStart == nil {
                    if line.backingIsSuffix && !line.mainText.isEmpty {
                        // Call-and-response / echo: enter after lead peaks while leaving room to finish
                        let anchor = line.time + min(gap * 0.50, max(0.55, (computedMainEnd - line.time) * 0.58))
                        finalBackStart = min(anchor, max(line.time + 0.35, nextTime - estBackDur - 0.08))
                    } else {
                        // Unison / chorus backing: lock directly to lead vocal onset
                        finalBackStart = line.time
                    }
                }
                let bs = finalBackStart ?? line.time
                if finalBackEnd == nil {
                    finalBackEnd = min(nextTime - 0.05, bs + estBackDur)
                }
                if finalBackWords.isEmpty {
                    let be = max(bs + 0.35, finalBackEnd ?? (bs + estBackDur))
                    finalBackWords = buildWeightedWords(text: bg, start: bs, duration: be - bs)
                }
            }

            out.append(LyricLine(
                time: line.time,
                endTime: computedMainEnd,
                backingTime: finalBackStart,
                backingEndTime: finalBackEnd,
                mainText: line.mainText,
                backingText: line.backingText,
                backingIsSuffix: line.backingIsSuffix,
                words: finalMainWords,
                backingWords: finalBackWords
            ))
        }
        return out
    }

    private static func buildWeightedWords(text: String, start: TimeInterval, duration: TimeInterval) -> [LyricWord] {
        guard !text.isEmpty else { return [] }
        let rawTokens = text.split(separator: " ", omittingEmptySubsequences: false)
        var tokens: [String] = []
        for (tIdx, tok) in rawTokens.enumerated() {
            let piece = String(tok) + (tIdx + 1 < rawTokens.count ? " " : "")
            if !piece.isEmpty { tokens.append(piece) }
        }
        guard !tokens.isEmpty else { return [] }

        let weights: [Double] = tokens.enumerated().map { idx, tok in
            let lower = tok.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let alpha = tok.unicodeScalars.filter { $0.properties.isAlphabetic || ($0.isASCII && $0.value >= 48) }.count
            let vowelCount = tok.unicodeScalars.filter { "aeiouyAEIOUY".unicodeScalars.contains($0) }.count
            let isFunctionWord = ["the", "a", "an", "to", "in", "on", "of", "and", "di", "ke", "yang", "dan", "ni", "no", "wa", "ga", "o", "e"].contains(lower)
            let paceMult = isFunctionWord ? 0.74 : (idx + 1 == tokens.count ? 1.25 : 1.0)
            let base = Double(alpha) + Double(vowelCount) * 0.22
            return max(1.0, base * paceMult)
        }
        // Reserve real inter-clause breath pauses after commas/semicolons so karaoke rests gently during singer breaths
        let pauseSlots = tokens.enumerated().map { idx, tok -> Double in
            guard idx + 1 < tokens.count else { return 0.0 }
            if tok.contains(",") || tok.contains(";") || tok.contains("、") || tok.contains("...") {
                return min(0.24, duration * 0.12)
            }
            return 0.0
        }
        let totalPauses = pauseSlots.reduce(0, +)
        let activeSingDuration = max(0.35, duration - totalPauses)
        let totalWeight = max(1.0, weights.reduce(0, +))

        var cursor = start
        var wordTimings: [LyricWord] = []
        for (wIdx, tok) in tokens.enumerated() {
            let dur = max(0.08, (weights[wIdx] / totalWeight) * activeSingDuration)
            wordTimings.append(LyricWord(time: cursor, duration: dur, text: tok))
            cursor += dur + pauseSlots[wIdx]
        }
        return wordTimings
    }

    static func distributePlainLyrics(_ plain: String, duration: TimeInterval) -> [LyricLine] {
        let lines = plain.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return [] }
        let step = duration / Double(lines.count)
        return lines.enumerated().map { idx, text in
            let split = splitMainAndBacking(text)
            return LyricLine(time: Double(idx) * step, mainText: split.main, backingText: split.backing)
        }
    }
}
