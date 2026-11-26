import Foundation
import CoreAudio
import Accelerate
import os
import os.lock

struct VocalEnergySample {
    let mediaElapsed: TimeInterval
    let energy: Float
    let backingEnergy: Float
}

final class VocalAutoSyncEngine {
    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var sampleRate: Double = 48000.0
    private var isInterleaved: Bool = true
    private var isFloat32: Bool = true
    private var numChannels: Int = 2

    // Dual 2-pole biquad bandpass filters (300 Hz - 3400 Hz vocal band) for Mid (L+R) and Side (L-R)
    private var b0: Float = 0, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
    private var mx1: Float = 0, mx2: Float = 0, my1: Float = 0, my2: Float = 0
    private var sx1: Float = 0, sx2: Float = 0, sy1: Float = 0, sy2: Float = 0

    private var lock = os_unfair_lock()
    private var latestVocalProminence: Float = 0
    private var latestBackingProminence: Float = 0
    private var latestVocalIntonation: Float = 0.45
    private var latestSyllableOnset: Float = 0.0
    private var prevProminenceForOnset: Float = 0.0
    private var samplesBuffer: [VocalEnergySample] = []
    private var lastSampleElapsed: TimeInterval = -1
    private var lastEvalTime: Date = .distantPast
    private var lastStartAttemptTime: Date = .distantPast

    private var candidateHistory: [Double] = []
    private var backingCandidateHistory: [Double] = []
    private var lastAutoOffset: TimeInterval = 0
    private var lastBackingOffset: TimeInterval = 0
    private var lastVocalClarity: Float = 0
    private var adaptivePeak: Float = 0.01
    private var adaptiveFloor: Float = 0.0005
    private var backingPeak: Float = 0.006
    private var backingFloor: Float = 0.0002

    // Preallocated fixed ring buffer for zero-allocation real-time BPM onset flux
    private static let beatRingCapacity = 512
    private var beatTimestamps = [Double](repeating: 0, count: 512)
    private var beatFluxValues = [Float](repeating: 0, count: 512)
    private var beatWriteIdx: Int = 0
    private var beatCount: Int = 0
    private var prevFullRMS: Float = 0
    private var bpmHistory: [Double] = []
    private(set) var detectedBPM: Double = 0

    private(set) var isTapActive: Bool = false
    private(set) var statusDescription: String = "Standby"
    var onAutoOffsetUpdated: ((TimeInterval, TimeInterval, String) -> Void)?

    func startIfNeeded() {
        guard !isTapActive else { return }
        let now = Date()
        // Cooldown retry to avoid hammering CoreAudio if permission prompt is still open
        guard now.timeIntervalSince(lastStartAttemptTime) >= 4.0 else { return }
        lastStartAttemptTime = now

        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.name = "TouchBarLyricsVocalTap"
        desc.muteBehavior = .unmuted

        var newTapID: AudioObjectID = kAudioObjectUnknown
        let tapStatus = AudioHardwareCreateProcessTap(desc, &newTapID)
        guard tapStatus == noErr, newTapID != kAudioObjectUnknown else {
            statusDescription = "Butuh izin System Audio (fallback timestamp)"
            NSLog("[TouchBarLyrics] process tap rejected status=%d", tapStatus)
            return
        }
        tapID = newTapID

        let aggDict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "TouchBarLyricsAggregateTap",
            kAudioAggregateDeviceUIDKey: "com.user.TouchBarLyrics.agg.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: desc.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true
                ]
            ]
        ]

        var newAggID: AudioObjectID = kAudioObjectUnknown
        let aggStatus = AudioHardwareCreateAggregateDevice(aggDict as CFDictionary, &newAggID)
        guard aggStatus == noErr, newAggID != kAudioObjectUnknown else {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
            statusDescription = "Gagal membuat audio tap"
            NSLog("[TouchBarLyrics] aggregate device failed status=%d", aggStatus)
            return
        }
        aggregateDeviceID = newAggID

        configureFilterAndFormat(for: aggregateDeviceID, tapID: tapID)

        var procID: AudioDeviceIOProcID?
        let ioStatus = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateDeviceID, nil) { [weak self] _, inInputData, _, _, _ in
            self?.processAudioBufferList(inInputData)
        }
        guard ioStatus == noErr, let validProcID = procID else {
            NSLog("[TouchBarLyrics] IO proc failed status=%d", ioStatus)
            stop()
            statusDescription = "Gagal memulai audio monitor"
            return
        }
        ioProcID = validProcID

        let startStatus = AudioDeviceStart(aggregateDeviceID, validProcID)
        guard startStatus == noErr else {
            NSLog("[TouchBarLyrics] audio device start failed status=%d", startStatus)
            stop()
            statusDescription = "Audio tap ditolak (fallback timestamp)"
            return
        }

        isTapActive = true
        statusDescription = "Aktif (mendengar vokal...)"
        NSLog("[TouchBarLyrics] audio tap active sampleRate=%.0f channels=%d", self.sampleRate, self.numChannels)
    }

    func stop() {
        if aggregateDeviceID != kAudioObjectUnknown {
            if let proc = ioProcID {
                AudioDeviceStop(aggregateDeviceID, proc)
                AudioDeviceDestroyIOProcID(aggregateDeviceID, proc)
                ioProcID = nil
            }
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
        isTapActive = false
        // A pause/resume within the retry cooldown used to delay the tap
        // restart by up to 4 seconds. Restarting immediately keeps the first
        // line of the resumed section in sync.
        lastStartAttemptTime = .distantPast
        lastEvalTime = .distantPast
    }

    func resetForNewTrack() {
        os_unfair_lock_lock(&lock)
        samplesBuffer.removeAll(keepingCapacity: true)
        latestVocalProminence = 0
        latestBackingProminence = 0
        latestVocalIntonation = 0.45
        latestSyllableOnset = 0.0
        prevProminenceForOnset = 0.0
        lastSampleElapsed = -1
        candidateHistory.removeAll()
        backingCandidateHistory.removeAll()
        lastAutoOffset = 0
        lastBackingOffset = 0
        lastVocalClarity = 0
        beatWriteIdx = 0
        beatCount = 0
        prevFullRMS = 0
        bpmHistory.removeAll()
        detectedBPM = 0
        os_unfair_lock_unlock(&lock)
        if isTapActive {
            statusDescription = "Menganalisa vokal & BPM..."
        }
    }

    func autoTempoScale() -> Double {
        os_unfair_lock_lock(&lock)
        let bpm = detectedBPM
        os_unfair_lock_unlock(&lock)
        guard bpm >= 55 && bpm <= 190 else { return 1.0 }
        return min(1.45, max(0.72, bpm / 112.0))
    }

    /// Combines track BPM with real-time vocal phrasing dynamics: gently slows on sustained breath/vibrato
    /// and crisply locks onto rapid articulated syllable bursts.
    func realtimeDeliveryTempoScale() -> Double {
        let base = autoTempoScale()
        let e = Double(currentNormalizedEnergy())
        os_unfair_lock_lock(&lock)
        let inton = Double(latestVocalIntonation)
        let onset = Double(latestSyllableOnset)
        os_unfair_lock_unlock(&lock)
        let deliveryMod = min(1.16, max(0.86, 0.88 + e * 0.14 + onset * 0.12 + inton * 0.04))
        return min(1.55, max(0.70, base * deliveryMod))
    }

    func currentVocalIntonation() -> Float {
        os_unfair_lock_lock(&lock)
        let v = latestVocalIntonation
        os_unfair_lock_unlock(&lock)
        return v
    }

    func currentSyllableOnset() -> Float {
        os_unfair_lock_lock(&lock)
        let v = latestSyllableOnset
        os_unfair_lock_unlock(&lock)
        return v
    }

    func currentBPM() -> Double {
        os_unfair_lock_lock(&lock)
        let bpm = detectedBPM
        os_unfair_lock_unlock(&lock)
        return bpm
    }

    func resetOffsetManual() {
        os_unfair_lock_lock(&lock)
        lastAutoOffset = 0
        lastBackingOffset = 0
        candidateHistory.removeAll()
        backingCandidateHistory.removeAll()
        os_unfair_lock_unlock(&lock)
        statusDescription = "Auto-Sync Vokal: Direset (0.00s)"
        onAutoOffsetUpdated?(0, 0, statusDescription)
    }

    func currentLiveEnergy() -> Float {
        os_unfair_lock_lock(&lock)
        let e = latestVocalProminence
        os_unfair_lock_unlock(&lock)
        return e
    }

    func currentLiveBackingEnergy() -> Float {
        os_unfair_lock_lock(&lock)
        let e = latestBackingProminence
        os_unfair_lock_unlock(&lock)
        return e
    }

    /// Returns smooth normalized [0, 1] vocal activity relative to recent track dynamics.
    func currentNormalizedEnergy() -> Float {
        os_unfair_lock_lock(&lock)
        let e = latestVocalProminence
        let fl = adaptiveFloor
        let pk = max(fl + 1e-5, adaptivePeak)
        os_unfair_lock_unlock(&lock)
        let norm = (e - fl) / (pk - fl)
        return min(1.0, max(0.0, norm))
    }

    /// Returns normalized [0, 1] stereo-side backing vocal activity relative to track dynamics.
    func currentNormalizedBackingEnergy() -> Float {
        os_unfair_lock_lock(&lock)
        let e = latestBackingProminence
        let fl = backingFloor
        let pk = max(fl + 1e-5, backingPeak)
        os_unfair_lock_unlock(&lock)
        let norm = (e - fl) / (pk - fl)
        return min(1.0, max(0.0, norm))
    }

    func recordAndAlign(mediaElapsed: TimeInterval, lyrics: [LyricLine], isEstimated: Bool) {
        if !isTapActive {
            startIfNeeded()
        }
        guard isTapActive, !lyrics.isEmpty, !isEstimated else { return }

        let energy = currentLiveEnergy()
        let bgEnergy = currentLiveBackingEnergy()
        let now = Date()

        os_unfair_lock_lock(&lock)
        // Detect manual seek / scrub / chapter jump and flush stale audio history
        if lastSampleElapsed >= 0 && (mediaElapsed < lastSampleElapsed - 0.35 || mediaElapsed - lastSampleElapsed > 1.8) {
            samplesBuffer.removeAll(keepingCapacity: true)
            candidateHistory.removeAll()
            backingCandidateHistory.removeAll()
            statusDescription = "Menyelaraskan ulang posisi..."
        }
        lastSampleElapsed = mediaElapsed

        // Downsample intake to ~10 Hz (record if >= 0.08s elapsed since last sample)
        if let prev = samplesBuffer.last, abs(mediaElapsed - prev.mediaElapsed) < 0.08 {
            if energy > prev.energy || bgEnergy > prev.backingEnergy {
                samplesBuffer[samplesBuffer.count - 1] = VocalEnergySample(
                    mediaElapsed: mediaElapsed,
                    energy: max(prev.energy, energy),
                    backingEnergy: max(prev.backingEnergy, bgEnergy)
                )
            }
        } else {
            samplesBuffer.append(VocalEnergySample(mediaElapsed: mediaElapsed, energy: energy, backingEnergy: bgEnergy))
            if samplesBuffer.count > 320 {
                samplesBuffer.removeFirst(samplesBuffer.count - 320)
            }
        }
        let snapshot = samplesBuffer
        let evalElapsed = now.timeIntervalSince(lastEvalTime)
        if evalElapsed < 0.35 {
            os_unfair_lock_unlock(&lock)
            return
        }
        lastEvalTime = now
        os_unfair_lock_unlock(&lock)

        estimateRealtimeBPM(nowSec: CFAbsoluteTimeGetCurrent())

        // Require ~1.8 seconds of contiguous audio (18 samples at 10 Hz) for fast sub-second lock
        guard snapshot.count >= 18 else {
            let pct = Int((Double(snapshot.count) / 18.0) * 100.0)
            statusDescription = "Kalibrasi vokal (\(pct)%)..."
            return
        }

        let sortedEnergies = snapshot.map { $0.energy }.sorted()
        let p20 = sortedEnergies[(sortedEnergies.count * 20) / 100]
        let p85 = sortedEnergies[(sortedEnergies.count * 85) / 100]
        os_unfair_lock_lock(&lock)
        adaptiveFloor = p20
        adaptivePeak = max(p85, p20 + 1e-5)
        os_unfair_lock_unlock(&lock)
        // Volume-independent dynamic floor (prevents guitar/drum intros from falsely triggering)
        guard p85 > 1e-6, p85 > p20 * 1.45 else {
            statusDescription = "Auto-Sync: Menunggu vokal jelas..."
            return
        }

        let minWindowT = snapshot.first?.mediaElapsed ?? 0
        let maxWindowT = snapshot.last?.mediaElapsed ?? 0
        // Do not lock a random large offset during pre-song instrumental intros before lyrics appear
        let hasActiveLyricRegion = lyrics.contains { $0.time >= (minWindowT - 6.0) && $0.time <= (maxWindowT + 6.0) }
        guard hasActiveLyricRegion else {
            statusDescription = "Auto-Sync: Menunggu masuk lirik..."
            return
        }

        let range = max(1e-6, p85 - p20)
        // Normalize vocal activity curve to [0, 1] per sample
        let normEnergy: [Double] = snapshot.map {
            let v = ($0.energy - p20) / range
            return min(1.0, max(0.0, Double(v)))
        }

        // Positive rising vocal flux (detects phrase/syllable entrances even inside dense choruses)
        var risingOnsets: [(idx: Int, strength: Double)] = []
        for i in 2..<normEnergy.count {
            let rise = normEnergy[i] - min(normEnergy[i - 1], normEnergy[i - 2])
            if rise >= 0.24 && normEnergy[i] >= 0.35 {
                risingOnsets.append((i, min(1.0, rise)))
            }
        }

        // Cap the correlation window at ~160 points (16s). Older audio no
        // longer helps once the current offset is settled, and this keeps the
        // per-evaluation work off the main thread's critical path.
        let sampleStride = max(1, snapshot.count / 160)
        var sampled: [VocalEnergySample] = []
        var sampledNorm: [Double] = []
        sampled.reserveCapacity(snapshot.count / sampleStride + 1)
        sampledNorm.reserveCapacity(snapshot.count / sampleStride + 1)
        for i in stride(from: 0, to: snapshot.count, by: sampleStride) {
            sampled.append(snapshot[i])
            sampledNorm.append(normEnergy[i])
        }

        // Expected singing envelope from LRC timestamps (strong at line start, tapering before next line, silent in breaks)
        func lineIndex(atOrBefore t: TimeInterval) -> Int? {
            var low = 0
            var high = lyrics.count - 1
            var found: Int?
            while low <= high {
                let mid = (low + high) / 2
                if lyrics[mid].time <= t {
                    found = mid
                    low = mid + 1
                } else {
                    high = mid - 1
                }
            }
            return found
        }

        func distanceToNearestLine(_ t: TimeInterval) -> TimeInterval {
            var low = 0
            var high = lyrics.count
            while low < high {
                let mid = (low + high) / 2
                if lyrics[mid].time < t {
                    low = mid + 1
                } else {
                    high = mid
                }
            }
            var best = TimeInterval.greatestFiniteMagnitude
            if low < lyrics.count { best = abs(lyrics[low].time - t) }
            if low > 0 { best = min(best, abs(lyrics[low - 1].time - t)) }
            return best
        }

        func expectedVocalScore(at t: TimeInterval) -> Double {
            guard let idx = lineIndex(atOrBefore: t) else {
                // Before first lyric line: likely intro instrumental
                if let first = lyrics.first, t < first.time - 0.5 { return -0.35 }
                return 0.0
            }
            let cur = lyrics[idx]
            let nextT = (idx + 1 < lyrics.count) ? lyrics[idx + 1].time : (cur.time + 5.0)
            let gap = nextT - cur.time
            let pos = t - cur.time

            if gap > 5.0 && pos > 3.5 {
                return -0.45
            }
            let knownPhraseEnd = cur.endTime ?? (cur.time + min(2.4, max(0.9, gap * 0.72)))
            if t <= knownPhraseEnd {
                return 1.0
            }
            return 0.20
        }

        func scoreOffset(_ delta: TimeInterval) -> Double {
            var corr = 0.0
            for (i, sample) in sampled.enumerated() {
                let exp = expectedVocalScore(at: sample.mediaElapsed + delta)
                // Centered around 0.42 vocal activity threshold
                corr += (sampledNorm[i] - 0.40) * exp
            }
            let normalizedCorr = (corr / Double(sampled.count)) * 12.0

            var onsetMatch = 0.0
            for onset in risingOnsets {
                let t = snapshot[onset.idx].mediaElapsed + delta
                let bestDist = distanceToNearestLine(t)
                if bestDist <= 0.45 {
                    let weight = 1.0 - (bestDist / 0.45)
                    onsetMatch += weight * onset.strength * 2.2
                }
            }
            let normalizedOnset = risingOnsets.isEmpty ? 0.0 : (onsetMatch / Double(max(4, risingOnsets.count))) * 6.0

            // Subtle regularization so genuine 0.3s-1.0s offsets are never suppressed
            let regZero = abs(delta) * 0.025
            let regPrev = abs(delta - lastAutoOffset) * 0.020
            return normalizedCorr + normalizedOnset - regZero - regPrev
        }

        let currentOffsetScore = scoreOffset(lastAutoOffset)
        let zeroScore = scoreOffset(0.0)
        var bestDelta = lastAutoOffset
        var bestScore = currentOffsetScore

        var candidate = -12.0
        while candidate <= 12.0 {
            let s = scoreOffset(candidate)
            if s > bestScore {
                bestScore = s
                bestDelta = candidate
            }
            candidate += 0.15
        }

        let quantized = (bestDelta * 10.0).rounded() / 10.0
        let baseline = max(zeroScore, currentOffsetScore)

        os_unfair_lock_lock(&lock)
        if bestScore - baseline >= 0.45 {
            candidateHistory.append(quantized)
        } else {
            candidateHistory.append(lastAutoOffset)
        }
        if candidateHistory.count > 4 {
            candidateHistory.removeFirst(candidateHistory.count - 4)
        }

        // Require consensus (at least 2 recent evaluations within ±0.45s) to eliminate flip-flopping
        let recent = candidateHistory
        os_unfair_lock_unlock(&lock)

        let targetDelta: Double
        if recent.count >= 2 {
            let close = recent.filter { abs($0 - quantized) <= 0.45 }
            if close.count >= 2 && bestScore - zeroScore >= 0.50 {
                targetDelta = close.reduce(0, +) / Double(close.count)
            } else {
                targetDelta = lastAutoOffset
            }
        } else {
            targetDelta = lastAutoOffset
        }

        let diff = targetDelta - lastAutoOffset
        var steppedDelta: Double
        if abs(diff) <= 0.04 {
            steppedDelta = lastAutoOffset
        } else if abs(diff) > 2.0 && recent.count >= 2 {
            steppedDelta = (targetDelta * 25.0).rounded() / 25.0
        } else {
            let clampStep = max(-0.8, min(0.8, diff))
            steppedDelta = ((lastAutoOffset + clampStep) * 25.0).rounded() / 25.0
        }

        // High-precision 40ms sub-second micro-phase refinement around settled offset
        if !risingOnsets.isEmpty {
            var bestFineDelta = steppedDelta
            var bestFineScore = -Double.greatestFiniteMagnitude
            var fine = steppedDelta - 0.56
            while fine <= steppedDelta + 0.56 {
                let s = scoreOffset(fine) - abs(fine - steppedDelta) * 0.04
                if s > bestFineScore {
                    bestFineScore = s
                    bestFineDelta = fine
                }
                fine += 0.04
            }
            let baseFineScore = scoreOffset(steppedDelta)
            if bestFineScore - baseFineScore >= 0.12 {
                // Smoothly pull toward exact 40ms micro-phase without jitter
                let pull = max(-0.12, min(0.12, bestFineDelta - steppedDelta))
                steppedDelta = ((steppedDelta + pull) * 25.0).rounded() / 25.0
            }
        }

        let clarityPct = Int(min(100, max(10, ((p85 - p20) / max(1e-5, p85)) * 100)))

        // Secondary alignment pass: stereo Side-channel (L-R) backing vocal offset per song
        var steppedBackingDelta = lastBackingOffset
        let backingSorted = snapshot.map { $0.backingEnergy }.sorted()
        let bgP20 = backingSorted[(backingSorted.count * 20) / 100]
        let bgP85 = backingSorted[(backingSorted.count * 85) / 100]
        os_unfair_lock_lock(&lock)
        backingFloor = bgP20
        backingPeak = max(bgP85, bgP20 + 1e-5)
        os_unfair_lock_unlock(&lock)

        let minT = snapshot.first?.mediaElapsed ?? 0
        let maxT = snapshot.last?.mediaElapsed ?? 0
        let activeBackingLines = lyrics.filter {
            !($0.backingText ?? "").isEmpty
                && $0.time >= (minT - 4.0)
                && $0.time <= (maxT + 4.0)
        }

        if bgP85 > 1e-6, bgP85 > bgP20 * 1.45, activeBackingLines.count >= 2 {
            let bgRange = max(1e-6, bgP85 - bgP20)
            let normBG: [Double] = sampled.map {
                min(1.0, max(0.0, Double(($0.backingEnergy - bgP20) / bgRange)))
            }

            func scoreBackingDelta(_ bgShift: TimeInterval) -> Double {
                var corr = 0.0
                for (i, sample) in sampled.enumerated() {
                    let t = sample.mediaElapsed + steppedDelta - bgShift
                    var expectedBG = -0.25
                    for line in activeBackingLines {
                        let start = line.backingTime ?? line.time
                        let end = line.backingEndTime ?? (start + 1.8)
                        if t >= start && t <= end {
                            expectedBG = 1.0
                            break
                        }
                    }
                    corr += (normBG[i] - 0.42) * expectedBG
                }
                return (corr / Double(max(1, sampled.count))) * 10.0 - abs(bgShift) * 0.10
            }

            let bgZero = scoreBackingDelta(0.0)
            let bgCur = scoreBackingDelta(lastBackingOffset)
            var bestBGDelta = lastBackingOffset
            var bestBGScore = bgCur

            var cand = -1.6
            while cand <= 1.6 {
                let s = scoreBackingDelta(cand)
                if s > bestBGScore {
                    bestBGScore = s
                    bestBGDelta = cand
                }
                cand += 0.15
            }

            let qBG = (bestBGDelta * 10.0).rounded() / 10.0
            os_unfair_lock_lock(&lock)
            if bestBGScore - max(bgZero, bgCur) >= 0.40 {
                backingCandidateHistory.append(qBG)
            } else {
                backingCandidateHistory.append(lastBackingOffset)
            }
            if backingCandidateHistory.count > 4 {
                backingCandidateHistory.removeFirst(backingCandidateHistory.count - 4)
            }
            let recentBG = backingCandidateHistory
            os_unfair_lock_unlock(&lock)

            if recentBG.count >= 2 {
                let close = recentBG.filter { abs($0 - qBG) <= 0.45 }
                if close.count >= 2 && bestBGScore - bgZero >= 0.45 {
                    let targetBG = close.reduce(0, +) / Double(close.count)
                    let diffBG = targetBG - lastBackingOffset
                    if abs(diffBG) > 0.10 {
                        let stepBG = max(-0.6, min(0.6, diffBG))
                        steppedBackingDelta = ((lastBackingOffset + stepBG) * 10.0).rounded() / 10.0
                    }
                }
            }
        }

        let leadChanged = abs(steppedDelta - lastAutoOffset) >= 0.05
        let bgChanged = abs(steppedBackingDelta - lastBackingOffset) >= 0.10
        if leadChanged || bgChanged || statusDescription.hasPrefix("Kalibrasi") || statusDescription.hasPrefix("Menganalisa") || statusDescription.hasPrefix("Menyelaraskan") {
            lastAutoOffset = steppedDelta
            lastBackingOffset = steppedBackingDelta
            let bpmNow = Int(currentBPM().rounded())
            let bpmTag = bpmNow >= 55 ? "BPM \(bpmNow) | " : ""
            let msg = (abs(steppedDelta) < 0.05 && abs(steppedBackingDelta) < 0.10)
                ? "\(bpmTag)Auto-Sync: 0.00s (Clarity \(clarityPct)%)"
                : String(format: "%@Sync: Lead %+.2fs | BG %+.2fs (%d%%)", bpmTag, steppedDelta, steppedBackingDelta, clarityPct)
            statusDescription = msg
            onAutoOffsetUpdated?(steppedDelta, steppedBackingDelta, msg)
        }
    }

    private func estimateRealtimeBPM(nowSec: Double) {
        os_unfair_lock_lock(&lock)
        let count = beatCount
        let writeIdx = beatWriteIdx
        guard count >= 120 else {
            os_unfair_lock_unlock(&lock)
            return
        }
        var points: [(t: Double, f: Float)] = []
        points.reserveCapacity(count)
        let cap = Self.beatRingCapacity
        let startIdx = (count == cap) ? writeIdx : 0
        for i in 0..<count {
            let idx = (startIdx + i) % cap
            let ts = beatTimestamps[idx]
            if nowSec - ts <= 5.5 {
                points.append((ts, beatFluxValues[idx]))
            }
        }
        os_unfair_lock_unlock(&lock)

        guard points.count >= 80, let firstT = points.first?.t else { return }
        let span = nowSec - firstT
        guard span >= 2.8 else { return }

        // Resample rhythmic onset flux onto uniform 50 Hz grid (20 ms per bin)
        let gridRate = 50.0
        let gridCount = Int(span * gridRate)
        guard gridCount >= 140 else { return }
        var grid = [Double](repeating: 0, count: gridCount)
        for p in points {
            let bin = Int((p.t - firstT) * gridRate)
            if bin >= 0 && bin < gridCount {
                grid[bin] = max(grid[bin], Double(p.f))
            }
        }

        let mean = grid.reduce(0, +) / Double(gridCount)
        let maxV = grid.max() ?? 0
        guard maxV > 1e-5 else { return }
        for i in 0..<gridCount { grid[i] -= mean }

        // Autocorrelation lag search across 62..176 BPM -> lag 17..48 bins at 50 Hz
        var bestLag = 26
        var bestScore = -Double.greatestFiniteMagnitude
        for lag in 17...48 {
            var corr = 0.0
            let limit = gridCount - lag
            if limit <= 10 { continue }
            for i in 0..<limit {
                corr += grid[i] * grid[i + lag]
            }
            let bpm = (60.0 * gridRate) / Double(lag)
            // Gentle perceptual prior centering ~116 BPM to avoid half/double octave flips
            let prior = 1.0 - min(0.32, abs(bpm - 116.0) / 220.0)
            let score = (corr / Double(limit)) * prior
            if score > bestScore {
                bestScore = score
                bestLag = lag
            }
        }

        let candidateBPM = (60.0 * gridRate) / Double(bestLag)
        os_unfair_lock_lock(&lock)
        bpmHistory.append(candidateBPM)
        if bpmHistory.count > 6 { bpmHistory.removeFirst(bpmHistory.count - 6) }
        let sortedBPM = bpmHistory.sorted()
        let medianBPM = sortedBPM[sortedBPM.count / 2]
        detectedBPM = detectedBPM == 0 ? medianBPM : (detectedBPM * 0.72 + medianBPM * 0.28)
        os_unfair_lock_unlock(&lock)
    }

    // MARK: - CoreAudio DSP Internals

    private func configureFilterAndFormat(for deviceID: AudioObjectID, tapID: AudioObjectID) {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var sz = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        if AudioObjectGetPropertyData(tapID, &addr, 0, nil, &sz, &asbd) == noErr {
            if asbd.mSampleRate > 8000 { sampleRate = asbd.mSampleRate }
            numChannels = max(1, Int(asbd.mChannelsPerFrame))
            isInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
            isFloat32 = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0 && asbd.mBitsPerChannel == 32
        } else {
            var srAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyNominalSampleRate,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var sr: Float64 = 48000.0
            var srSize = UInt32(MemoryLayout<Float64>.size)
            if AudioObjectGetPropertyData(deviceID, &srAddr, 0, nil, &srSize, &sr) == noErr, sr > 8000 {
                sampleRate = sr
            }
        }

        // Constant-skirt-gain biquad bandpass centered at ~1150 Hz (Q=0.65 -> ~300-3400 Hz human voice band)
        let f0 = 1150.0
        let q = 0.65
        let w0 = 2.0 * Double.pi * f0 / sampleRate
        let alpha = sin(w0) / (2.0 * q)
        let a0 = 1.0 + alpha
        b0 = Float(alpha / a0)
        b1 = 0
        b2 = Float(-alpha / a0)
        a1 = Float((-2.0 * cos(w0)) / a0)
        a2 = Float((1.0 - alpha) / a0)
        mx1 = 0; mx2 = 0; my1 = 0; my2 = 0
        sx1 = 0; sx2 = 0; sy1 = 0; sy2 = 0
    }

    private func processAudioBufferList(_ bufferListPtr: UnsafePointer<AudioBufferList>) {
        let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferListPtr))
        guard isFloat32, let firstBuf = abl.first, let rawL = firstBuf.mData else { return }

        let planarStereo = (abl.count >= 2 && firstBuf.mNumberChannels == 1)
        let frames: Int
        let ch: Int
        if planarStereo {
            frames = Int(firstBuf.mDataByteSize) / MemoryLayout<Float>.size
            ch = 2
        } else {
            ch = max(1, Int(firstBuf.mNumberChannels))
            frames = (Int(firstBuf.mDataByteSize) / MemoryLayout<Float>.size) / ch
        }
        guard frames > 0 else { return }

        let ptrL = rawL.assumingMemoryBound(to: Float.self)
        let ptrR = planarStereo ? abl[1].mData?.assumingMemoryBound(to: Float.self) : nil

        var midSq: Float = 0
        var sideSq: Float = 0
        var totalSq: Float = 0
        var zcrCount: Int = 0
        var prevYm: Float = my1

        for f in 0..<frames {
            let l: Float
            let r: Float
            if planarStereo {
                l = ptrL[f]
                r = ptrR?[f] ?? l
            } else if ch >= 2 {
                l = ptrL[f * ch]
                r = ptrL[f * ch + 1]
            } else {
                l = ptrL[f]
                r = l
            }

            let mid = 0.5 * (l + r)
            let side = 0.5 * (l - r)
            totalSq += mid * mid

            let ym = b0 * mid + b1 * mx1 + b2 * mx2 - a1 * my1 - a2 * my2
            mx2 = mx1; mx1 = mid; my2 = my1; my1 = ym
            if prevYm <= 0 && ym > 0 { zcrCount += 1 }
            prevYm = ym
            midSq += ym * ym

            let ys = b0 * side + b1 * sx1 + b2 * sx2 - a1 * sy1 - a2 * sy2
            sx2 = sx1; sx1 = side; sy2 = sy1; sy1 = ys
            sideSq += ys * ys
        }

        let invN = 1.0 / Float(frames)
        let midVocalRMS = sqrtf(midSq * invN)
        let sideVocalRMS = sqrtf(sideSq * invN)
        let totalRMS = sqrtf(totalSq * invN)

        // Isolate center-panned lead vocals and stereo-spread backing harmonies
        let centerRatio = min(1.0, max(0.18, midVocalRMS / (midVocalRMS + 0.65 * sideVocalRMS + 1e-6)))
        let bandRatio = min(1.0, max(0.18, midVocalRMS / (totalRMS + 1e-6)))
        let prominence = midVocalRMS * centerRatio * bandRatio

        let sideBandRatio = min(1.0, max(0.15, sideVocalRMS / (totalRMS + 1e-6)))
        let sideProminence = sideVocalRMS * sideBandRatio

        // Real-time vocal intonation / brightness proxy from bandpass zero-crossing frequency (240Hz..1640Hz)
        let zcrHz = (Float(zcrCount) * Float(sampleRate)) / max(1.0, Float(frames))
        let rawIntonation = min(1.0, max(0.0, (zcrHz - 240.0) / 1400.0))
        let nowTS = CFAbsoluteTimeGetCurrent()

        os_unfair_lock_lock(&lock)
        let prevProm = prevProminenceForOnset
        let onsetImpulse: Float = prominence > max(adaptiveFloor * 1.15, prevProm * 1.16)
            ? min(1.0, (prominence - prevProm) / max(1e-4, adaptivePeak * 0.65))
            : 0.0
        prevProminenceForOnset = prominence * 0.60 + prevProm * 0.40
        latestVocalProminence = latestVocalProminence * 0.62 + prominence * 0.38
        latestBackingProminence = latestBackingProminence * 0.60 + sideProminence * 0.40
        if prominence > adaptiveFloor * 1.1 {
            latestVocalIntonation = latestVocalIntonation * 0.72 + rawIntonation * 0.28
        }
        latestSyllableOnset = max(onsetImpulse, latestSyllableOnset * 0.84)

        let flux = max(0, totalRMS - prevFullRMS)
        prevFullRMS = prevFullRMS * 0.45 + totalRMS * 0.55
        beatTimestamps[beatWriteIdx] = nowTS
        beatFluxValues[beatWriteIdx] = flux
        beatWriteIdx = (beatWriteIdx + 1) % Self.beatRingCapacity
        if beatCount < Self.beatRingCapacity { beatCount += 1 }
        os_unfair_lock_unlock(&lock)
    }
}
