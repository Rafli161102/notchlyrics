import Foundation

struct LyricWord: Equatable {
    let time: TimeInterval
    let duration: TimeInterval
    let text: String
}

struct LyricLine: Equatable {
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

struct FetchedLyricsResult {
    let lines: [LyricLine]
    let romanizedLines: [LyricLine]
    let sourceName: String
    let isEstimated: Bool
    let hasWordTimings: Bool
    let referenceDuration: TimeInterval

    init(
        lines: [LyricLine],
        romanizedLines: [LyricLine]? = nil,
        sourceName: String,
        isEstimated: Bool,
        hasWordTimings: Bool = false,
        referenceDuration: TimeInterval
    ) {
        self.lines = lines
        self.romanizedLines = romanizedLines ?? lines
        self.sourceName = sourceName
        self.isEstimated = isEstimated
        self.hasWordTimings = hasWordTimings
        self.referenceDuration = referenceDuration
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

final class LyricsParserAndFetcher {
    private var cache: [String: FetchedLyricsResult] = [:]

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
        return cache[key]
    }

    func cleanTitle(_ raw: String) -> String {
        var s = raw
        let bracketNoise = #"\s*[\(\[]\s*(Official\s*(Music\s*)?Video|Official\s*Audio|Official\s*MV|Lyric\s*Video|Lyrics?\s*Video|Lyrics?|Lirik(\s*Terjemahan)?|Sub\s*Indo|Audio|Visualizer|MV|HD|4K|Live(\s*Performance)?|Explicit|Remastered(\s*\d+)?|Slowed(\s*\+\s*Reverb)?|Sped\s*Up|Karaoke)\s*[\)\]]"#
        s = s.replacingOccurrences(of: bracketNoise, with: "", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"\s*\|\s*.*$"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s*//\s*.*$"#, with: "", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cleanArtist(_ raw: String) -> String {
        var s = raw.replacingOccurrences(of: #"\s*-\s*Topic$"#, with: "", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"\s*VEVO$"#, with: "", options: [.regularExpression, .caseInsensitive])
        if let first = s.components(separatedBy: ",").first {
            s = first
        }
        s = s.replacingOccurrences(of: #"\s+(feat\.?|ft\.?|featuring)\s+.*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func stripFeaturing(_ text: String) -> String {
        let noFeat = text.replacingOccurrences(
            of: #"\s*[\(\[]?\s*(feat\.?|ft\.?|featuring|with)\s+[^\)\]]+[\)\]]?"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return noFeat.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Concurrently queries LRCLIB (exact w/ duration + search) & NetEase (word-timed YRC + LRC),
    /// then selects the candidate with the closest song duration and highest timing granularity.
    func fetchLyrics(
        cacheKey: String,
        rawTitle: String,
        rawArtist: String,
        duration: TimeInterval,
        completion: @escaping (FetchedLyricsResult) -> Void
    ) {
        if let hit = cache[cacheKey] {
            completion(hit)
            return
        }

        let titleHint = cleanTitle(rawTitle)
        let artistHint = cleanArtist(rawArtist)
        let candidates = buildQueryCandidates(rawTitle: rawTitle, rawArtist: rawArtist)

        let group = DispatchGroup()
        let lock = NSLock()
        var pool: [RankedCandidate] = []

        func collect(_ item: RankedCandidate?) {
            guard let item = item, !item.lines.isEmpty else { return }
            lock.lock()
            pool.append(item)
            lock.unlock()
        }

        group.enter()
        fetchLRCLIBCandidates(candidates: candidates, expectedTitle: titleHint, expectedArtist: artistHint, targetDuration: duration) { items in
            items.forEach { collect($0) }
            group.leave()
        }

        group.enter()
        fetchNetEaseCandidates(candidates: candidates, expectedTitle: titleHint, expectedArtist: artistHint, targetDuration: duration) { items in
            items.forEach { collect($0) }
            group.leave()
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = group.wait(timeout: .now() + 5.5)
            guard let self = self else { return }

            lock.lock()
            let picked = pool.max(by: { $0.matchScore < $1.matchScore })
            lock.unlock()

            if let best = picked, (!best.isEstimated || pool.count > 0) {
                if !best.isEstimated {
                    let result = self.finalizeResult(
                        lines: best.lines,
                        sourceName: best.sourceName,
                        isEstimated: false,
                        hasWordTimings: best.hasWordTimings,
                        referenceDuration: best.referenceDuration,
                        titleHint: titleHint,
                        artistHint: artistHint
                    )
                    self.cache[cacheKey] = result
                    completion(result)
                    return
                }
            }

            // Tier 3 plain lyrics fallback if synced search yielded nothing
            self.tryLyricsOVH(candidates: candidates, targetDuration: duration) { ovhCand in
                let finalCand = picked ?? ovhCand
                if let c = finalCand {
                    let result = self.finalizeResult(
                        lines: c.lines,
                        sourceName: c.sourceName,
                        isEstimated: c.isEstimated,
                        hasWordTimings: c.hasWordTimings,
                        referenceDuration: c.referenceDuration,
                        titleHint: titleHint,
                        artistHint: artistHint
                    )
                    self.cache[cacheKey] = result
                    completion(result)
                } else {
                    let empty = FetchedLyricsResult(
                        lines: [],
                        romanizedLines: [],
                        sourceName: "None",
                        isEstimated: false,
                        hasWordTimings: false,
                        referenceDuration: duration
                    )
                    self.cache[cacheKey] = empty
                    completion(empty)
                }
            }
        }
    }

    private func buildQueryCandidates(rawTitle: String, rawArtist: String) -> [(track: String, artist: String)] {
        let baseTitle = cleanTitle(rawTitle)
        let baseArtist = cleanArtist(rawArtist)
        var pairs: [(String, String)] = []

        func addPair(_ t: String, _ a: String) {
            let ct = t.trimmingCharacters(in: .whitespacesAndNewlines)
            let ca = a.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ct.isEmpty else { return }
            if !pairs.contains(where: { $0.0.caseInsensitiveCompare(ct) == .orderedSame && $0.1.caseInsensitiveCompare(ca) == .orderedSame }) {
                pairs.append((ct, ca))
            }
        }

        if baseTitle.contains(" - ") {
            let parts = baseTitle.components(separatedBy: " - ")
            if parts.count >= 2 {
                let left = cleanArtist(parts[0])
                let right = cleanTitle(parts[1...].joined(separator: " - "))
                addPair(right, left)
                addPair(stripFeaturing(right), left)
                addPair(left, right)
            }
        }

        addPair(baseTitle, baseArtist)
        addPair(stripFeaturing(baseTitle), baseArtist)
        if !baseArtist.isEmpty {
            addPair(baseTitle, "")
            addPair(stripFeaturing(baseTitle), "")
        }

        return pairs
    }

    private static func scoreCandidate(
        trackName: String,
        artistName: String,
        expectedTitle: String,
        expectedArtist: String,
        refDuration: TimeInterval,
        targetDuration: TimeInterval,
        hasSynced: Bool,
        hasWordTimings: Bool
    ) -> Double {
        var score: Double = hasSynced ? 100.0 : 20.0
        if hasWordTimings {
            score += 28.0
        }

        // Strict duration accuracy scoring so remixes/wrong edits never hijack the lyrics
        if targetDuration > 20 && refDuration > 20 {
            let diff = abs(refDuration - targetDuration)
            if diff <= 1.5 {
                score += 30.0
            } else if diff <= 3.5 {
                score += 20.0 - (diff - 1.5) * 4.0
            } else if diff <= 8.0 {
                score += 8.0 - diff * 2.5
            } else {
                score -= min(90.0, diff * 3.5)
            }
        }

        let normTrack = trackName.lowercased()
        let normExpTitle = expectedTitle.lowercased()
        if !normExpTitle.isEmpty {
            if normTrack == normExpTitle {
                score += 18.0
            } else if normTrack.contains(normExpTitle) || normExpTitle.contains(normTrack) {
                score += 10.0
            } else {
                score -= 12.0
            }
        }

        let normArtist = artistName.lowercased()
        let normExpArtist = expectedArtist.lowercased()
        if !normExpArtist.isEmpty && !normArtist.isEmpty {
            if normArtist == normExpArtist || normArtist.contains(normExpArtist) || normExpArtist.contains(normArtist) {
                score += 16.0
            } else {
                score -= 22.0
            }
        }
        return score
    }

    // MARK: - Tier 1: LRCLIB (Duration-Matched)

    private func fetchLRCLIBCandidates(
        candidates: [(track: String, artist: String)],
        expectedTitle: String,
        expectedArtist: String,
        targetDuration: TimeInterval,
        completion: @escaping ([RankedCandidate]) -> Void
    ) {
        let localGroup = DispatchGroup()
        let lock = NSLock()
        var results: [RankedCandidate] = []

        // 1A. Exact match including duration parameter
        if let first = candidates.first,
           !first.artist.isEmpty,
           let tEnc = first.track.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let aEnc = first.artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            let durParam = targetDuration > 15 ? "&duration=\(Int(round(targetDuration)))" : ""
            if let url = URL(string: "https://lrclib.net/api/get?track_name=\(tEnc)&artist_name=\(aEnc)\(durParam)") {
                localGroup.enter()
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    defer { localGroup.leave() }
                    guard let data = data,
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
                    let refDur = (json["duration"] as? Double) ?? targetDuration
                    let trName = (json["trackName"] as? String) ?? first.track
                    let arName = (json["artistName"] as? String) ?? first.artist
                    if let synced = json["syncedLyrics"] as? String, !synced.isEmpty {
                        let parsed = Self.parseLRCWithMeta(synced)
                        if !parsed.lines.isEmpty {
                            let sc = Self.scoreCandidate(
                                trackName: trName, artistName: arName,
                                expectedTitle: expectedTitle, expectedArtist: expectedArtist,
                                refDuration: refDur, targetDuration: targetDuration,
                                hasSynced: true, hasWordTimings: parsed.hasWordTimings
                            )
                            lock.lock()
                            results.append(RankedCandidate(
                                lines: parsed.lines,
                                sourceName: parsed.hasWordTimings ? "LRCLIB (Kata)" : "LRCLIB",
                                isEstimated: false,
                                hasWordTimings: parsed.hasWordTimings,
                                referenceDuration: refDur,
                                matchScore: sc
                            ))
                            lock.unlock()
                        }
                    } else if let plain = json["plainLyrics"] as? String, !plain.isEmpty {
                        let est = Self.distributePlainLyrics(plain, duration: max(60, refDur))
                        let sc = Self.scoreCandidate(
                            trackName: trName, artistName: arName,
                            expectedTitle: expectedTitle, expectedArtist: expectedArtist,
                            refDuration: refDur, targetDuration: targetDuration,
                            hasSynced: false, hasWordTimings: false
                        )
                        lock.lock()
                        results.append(RankedCandidate(
                            lines: est,
                            sourceName: "LRCLIB (Estimasi)",
                            isEstimated: true,
                            hasWordTimings: false,
                            referenceDuration: refDur,
                            matchScore: sc
                        ))
                        lock.unlock()
                    }
                }.resume()
            }
        }

        // 1B. Search top 2 query candidates
        for cand in candidates.prefix(2) {
            let q = cand.artist.isEmpty ? cand.track : "\(cand.track) \(cand.artist)"
            guard let qEnc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "https://lrclib.net/api/search?q=\(qEnc)") else { continue }
            localGroup.enter()
            URLSession.shared.dataTask(with: url) { data, _, _ in
                defer { localGroup.leave() }
                guard let data = data,
                      let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
                for item in arr.prefix(8) {
                    let refDur = (item["duration"] as? Double) ?? targetDuration
                    let trName = (item["trackName"] as? String) ?? ""
                    let arName = (item["artistName"] as? String) ?? ""
                    if let synced = item["syncedLyrics"] as? String, !synced.isEmpty {
                        let parsed = Self.parseLRCWithMeta(synced)
                        if !parsed.lines.isEmpty {
                            let sc = Self.scoreCandidate(
                                trackName: trName, artistName: arName,
                                expectedTitle: expectedTitle, expectedArtist: expectedArtist,
                                refDuration: refDur, targetDuration: targetDuration,
                                hasSynced: true, hasWordTimings: parsed.hasWordTimings
                            )
                            lock.lock()
                            results.append(RankedCandidate(
                                lines: parsed.lines,
                                sourceName: parsed.hasWordTimings ? "LRCLIB (Kata)" : "LRCLIB",
                                isEstimated: false,
                                hasWordTimings: parsed.hasWordTimings,
                                referenceDuration: refDur,
                                matchScore: sc
                            ))
                            lock.unlock()
                        }
                    } else if let plain = item["plainLyrics"] as? String, !plain.isEmpty {
                        let est = Self.distributePlainLyrics(plain, duration: max(60, refDur))
                        let sc = Self.scoreCandidate(
                            trackName: trName, artistName: arName,
                            expectedTitle: expectedTitle, expectedArtist: expectedArtist,
                            refDuration: refDur, targetDuration: targetDuration,
                            hasSynced: false, hasWordTimings: false
                        )
                        lock.lock()
                        results.append(RankedCandidate(
                            lines: est,
                            sourceName: "LRCLIB (Estimasi)",
                            isEstimated: true,
                            hasWordTimings: false,
                            referenceDuration: refDur,
                            matchScore: sc
                        ))
                        lock.unlock()
                    }
                }
            }.resume()
        }

        DispatchQueue.global(qos: .userInitiated).async {
            _ = localGroup.wait(timeout: .now() + 4.5)
            completion(results)
        }
    }

    // MARK: - Tier 2: NetEase Cloud Music (YRC Word-Timing + LRC)

    private func fetchNetEaseCandidates(
        candidates: [(track: String, artist: String)],
        expectedTitle: String,
        expectedArtist: String,
        targetDuration: TimeInterval,
        completion: @escaping ([RankedCandidate]) -> Void
    ) {
        guard let cand = candidates.first else {
            completion([])
            return
        }
        let q = cand.artist.isEmpty ? cand.track : "\(cand.track) \(cand.artist)"
        guard let qEnc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "https://music.163.com/api/search/get?s=\(qEnc)&type=1&limit=5") else {
            completion([])
            return
        }

        var req = URLRequest(url: searchURL, timeoutInterval: 4.5)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self = self,
                  let data = data,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let res = root["result"] as? [String: Any],
                  let songs = res["songs"] as? [[String: Any]], !songs.isEmpty else {
                completion([])
                return
            }

            // Pick top 2 duration/artist-compatible candidates to inspect YRC + LRC
            let sortedSongs = songs.sorted { a, b in
                let da = targetDuration > 15 ? abs(((a["duration"] as? Double ?? 0) / 1000.0) - targetDuration) : 0
                let db = targetDuration > 15 ? abs(((b["duration"] as? Double ?? 0) / 1000.0) - targetDuration) : 0
                return da < db
            }.prefix(2)

            let localGroup = DispatchGroup()
            let lock = NSLock()
            var out: [RankedCandidate] = []

            for song in sortedSongs {
                guard let songID = song["id"] as? Int else { continue }
                let sName = (song["name"] as? String) ?? ""
                let artistsArr = song["artists"] as? [[String: Any]]
                let sArtist = (artistsArr?.first?["name"] as? String) ?? ""
                let sDur = (song["duration"] as? Double ?? 0) / 1000.0
                let refDur = sDur > 10 ? sDur : targetDuration

                localGroup.enter()
                self.fetchNetEaseLyricPayload(songID: songID) { yrcStr, lrcStr in
                    defer { localGroup.leave() }

                    if let yrc = yrcStr, !yrc.isEmpty {
                        let yrcLines = Self.parseYRC(yrc)
                        if !yrcLines.isEmpty {
                            let sc = Self.scoreCandidate(
                                trackName: sName, artistName: sArtist,
                                expectedTitle: expectedTitle, expectedArtist: expectedArtist,
                                refDuration: refDur, targetDuration: targetDuration,
                                hasSynced: true, hasWordTimings: true
                            )
                            lock.lock()
                            out.append(RankedCandidate(
                                lines: yrcLines,
                                sourceName: "NetEase YRC (Per Kata)",
                                isEstimated: false,
                                hasWordTimings: true,
                                referenceDuration: refDur,
                                matchScore: sc
                            ))
                            lock.unlock()
                        }
                    }

                    if let lrc = lrcStr, !lrc.isEmpty {
                        let parsed = Self.parseLRCWithMeta(lrc)
                        if !parsed.lines.isEmpty {
                            let sc = Self.scoreCandidate(
                                trackName: sName, artistName: sArtist,
                                expectedTitle: expectedTitle, expectedArtist: expectedArtist,
                                refDuration: refDur, targetDuration: targetDuration,
                                hasSynced: true, hasWordTimings: parsed.hasWordTimings
                            )
                            lock.lock()
                            out.append(RankedCandidate(
                                lines: parsed.lines,
                                sourceName: "NetEase LRC",
                                isEstimated: false,
                                hasWordTimings: parsed.hasWordTimings,
                                referenceDuration: refDur,
                                matchScore: sc
                            ))
                            lock.unlock()
                        }
                    }
                }
            }

            DispatchQueue.global(qos: .userInitiated).async {
                _ = localGroup.wait(timeout: .now() + 4.0)
                completion(out)
            }
        }.resume()
    }

    private func fetchNetEaseLyricPayload(songID: Int, completion: @escaping (String?, String?) -> Void) {
        guard let url = URL(string: "https://music.163.com/api/song/lyric?os=pc&id=\(songID)&lv=-1&yv=-1") else {
            completion(nil, nil)
            return
        }
        var req = URLRequest(url: url, timeoutInterval: 4.0)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(nil, nil)
                return
            }
            let yrcStr = (root["yrc"] as? [String: Any])?["lyric"] as? String
            let lrcStr = (root["lrc"] as? [String: Any])?["lyric"] as? String
            completion(yrcStr, lrcStr)
        }.resume()
    }

    // MARK: - Tier 3: Lyrics.ovh Plain Fallback

    private func tryLyricsOVH(
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

        URLSession.shared.dataTask(with: url) { data, _, _ in
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
                matchScore: 10.0
            ))
        }.resume()
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
        let regex = try? NSRegularExpression(pattern: #"\[(\d{1,2}):(\d{2})(?:[\.:](\d{1,3}))?\]"#)
        var detectedEnhanced = false

        for rawLine in lrc.components(separatedBy: .newlines) {
            let nsLine = rawLine as NSString
            let range = NSRange(location: 0, length: nsLine.length)
            guard let matches = regex?.matches(in: rawLine, range: range), !matches.isEmpty,
                  let lastMatch = matches.last else { continue }

            let textStart = lastMatch.range.location + lastMatch.range.length
            let text = nsLine.substring(from: textStart).trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }

            if text.hasPrefix("作词") || text.hasPrefix("作曲") || text.hasPrefix("编曲") {
                continue
            }

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
                rawEntries.append((time, text))
            }
        }

        rawEntries.sort { $0.0 < $1.0 }

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
                    parsed.append(LyricLine(
                        time: t1,
                        backingTime: t2,
                        mainText: s1.main,
                        backingText: mergeBacking(s1.backing, bg2),
                        backingIsSuffix: gap > 0.35 || s1.backingAtEnd,
                        words: s1.words,
                        backingWords: s2.backingWords
                    ))
                    i += 2
                    continue
                } else if gap <= 0.40 {
                    if s1.main.isEmpty, let bg1 = s1.backing, !s2.main.isEmpty {
                        parsed.append(LyricLine(
                            time: t2,
                            backingTime: t1,
                            mainText: s2.main,
                            backingText: mergeBacking(bg1, s2.backing),
                            backingIsSuffix: s2.backingAtEnd,
                            words: s2.words,
                            backingWords: s1.backingWords
                        ))
                        i += 2
                        continue
                    } else if !s1.main.isEmpty && !s2.main.isEmpty && s2.main.count < s1.main.count {
                        parsed.append(LyricLine(
                            time: t1,
                            backingTime: t2,
                            mainText: s1.main,
                            backingText: s2.main,
                            backingIsSuffix: t2 > t1 + 0.35,
                            words: s1.words,
                            backingWords: s2.words
                        ))
                        i += 2
                        continue
                    }
                }
            }

            let split = splitEnhancedAndBacking(lineTime: t1, raw: text1)
            if !split.words.isEmpty { detectedEnhanced = true }
            if !split.main.isEmpty || !(split.backing ?? "").isEmpty {
                parsed.append(LyricLine(
                    time: t1,
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

    /// Synthesizes proportional syllable-weighted word timings for BOTH main and backing vocals
    /// so lead lines and call-and-response/harmony backing vocals enter and highlight on beat.
    static func synthesizeWordTimings(for lines: [LyricLine]) -> [LyricLine] {
        guard !lines.isEmpty else { return lines }
        var out: [LyricLine] = []
        out.reserveCapacity(lines.count)

        for idx in 0..<lines.count {
            let line = lines[idx]
            let nextTime = (idx + 1 < lines.count) ? lines[idx + 1].time : (line.time + 4.5)
            let gap = max(0.6, nextTime - line.time)

            // Main phrase window & word timings
            let estMainDur = line.mainText.isEmpty ? 0.0 : max(0.85, Double(line.mainText.count) * 0.086)
            let mainPhraseDur = gap > 3.6
                ? min(gap * 0.80, max(estMainDur, 1.8))
                : min(gap * 0.92, max(estMainDur, gap * 0.72))
            let computedMainEnd = line.endTime ?? (line.time + mainPhraseDur)
            let finalMainWords = !line.words.isEmpty
                ? line.words
                : buildWeightedWords(text: line.mainText, start: line.time, duration: max(0.5, computedMainEnd - line.time))

            // Independent Backing Vocal window & word timings
            var finalBackStart = line.backingTime
            var finalBackEnd = line.backingEndTime
            var finalBackWords = line.backingWords

            if let bg = line.backingText, !bg.isEmpty {
                let estBackDur = max(0.65, min(gap * 0.75, Double(bg.count) * 0.088))
                if finalBackStart == nil {
                    if line.backingIsSuffix && !line.mainText.isEmpty {
                        // Call-and-response / echo: enter after the main vocal peaks
                        let anchor = line.time + min(gap * 0.48, max(0.55, (computedMainEnd - line.time) * 0.56))
                        finalBackStart = min(anchor, nextTime - 0.55)
                    } else {
                        // Harmonic / unison backing: enter tightly alongside main vocal (+120ms stagger)
                        finalBackStart = line.time + (line.mainText.isEmpty ? 0.0 : 0.12)
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

        let weights: [Double] = tokens.map { tok in
            let alpha = tok.unicodeScalars.filter { $0.properties.isAlphabetic || ($0.isASCII && $0.value >= 48) }.count
            let punctPause = (tok.contains(",") || tok.contains(";")) ? 1.5 : 0.0
            return max(1.2, Double(alpha) + punctPause)
        }
        let totalWeight = max(1.0, weights.reduce(0, +))

        var cursor = start
        var wordTimings: [LyricWord] = []
        for (wIdx, tok) in tokens.enumerated() {
            let dur = max(0.08, (weights[wIdx] / totalWeight) * duration)
            wordTimings.append(LyricWord(time: cursor, duration: dur, text: tok))
            cursor += dur
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
