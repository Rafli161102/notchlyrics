import Foundation
import CoreAudio
import Accelerate
import Darwin
import os.lock

struct VocalEnergySample {
    let mediaElapsed: TimeInterval
    let energy: Float
    let backingEnergy: Float
}

/// Real-time vocal detector & auto-aligner tapping CoreAudio output (macOS 14.2+)
/// with lock-free vDSP bandpass extraction and SPSC onset flux transfer.
final class VocalAutoSyncEngine {
    private static let chunkFrames = 4096
    private static let beatRingCapacity = 1024
    private static let beatRingMask: Int32 = 1023

    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var sampleRate: Double = 48000.0
    private var isInterleaved: Bool = true
    private var isFloat32: Bool = true
    private var bitsPerChannel: Int = 32
    private var numChannels: Int = 2

    // Dual vDSP biquad filters (300 Hz - 3400 Hz vocal band) for Mid (L+R) and Side (L-R)
    private var b0: Float = 0, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
    private var midBiquadSetup: vDSP_biquad_Setup?
    private var sideBiquadSetup: vDSP_biquad_Setup?
    private let midDelays = UnsafeMutablePointer<Float>.allocate(capacity: 4)
    private let sideDelays = UnsafeMutablePointer<Float>.allocate(capacity: 4)

    // Pre-allocated 4096-frame DSP scratch buffers (zero heap allocation in IOProc)
    private let scratchLeft = UnsafeMutablePointer<Float>.allocate(capacity: chunkFrames)
    private let scratchRight = UnsafeMutablePointer<Float>.allocate(capacity: chunkFrames)
    private let scratchMid = UnsafeMutablePointer<Float>.allocate(capacity: chunkFrames)
    private let scratchSide = UnsafeMutablePointer<Float>.allocate(capacity: chunkFrames)
    private let scratchFilteredMid = UnsafeMutablePointer<Float>.allocate(capacity: chunkFrames)
    private let scratchFilteredSide = UnsafeMutablePointer<Float>.allocate(capacity: chunkFrames)

    // Non-RT state lock (never acquired inside CoreAudio IOProc)
    private var lock = os_unfair_lock()

    // Lock-free IOProc -> Reader metrics published via SeqLock
    private let metricsSeqPtr = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
    private var ioPublishedVocalProminence: Float = 0
    private var ioPublishedBackingProminence: Float = 0
    private var ioPublishedVocalIntonation: Float = 0.45
    private var ioPublishedSyllableOnset: Float = 0

    // IOProc-exclusive filter & envelope smoothing state
    private var ioVocalProminence: Float = 0
    private var ioBackingProminence: Float = 0
    private var ioVocalIntonation: Float = 0.45
    private var ioSyllableOnset: Float = 0
    private var ioPrevProminenceForOnset: Float = 0
    private var ioPrevFullRMS: Float = 0
    private var ioLastFilteredMid: Float = 0
    private var ioLastSeenResetGen: Int32 = 0

    // Lock-free shared thresholds/reset signals (written on non-RT thread, read in IOProc)
    private let ioAdaptiveFloorPtr = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    private let ioAdaptivePeakPtr = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    private let needsFilterResetPtr = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
    private let resetGenPtr = UnsafeMutablePointer<Int32>.allocate(capacity: 1)

    // Lock-free SPSC ring buffer for BPM onset flux (IOProc producer -> analysis consumer)
    private let beatTimestamps = UnsafeMutablePointer<Double>.allocate(capacity: beatRingCapacity)
    private let beatFluxValues = UnsafeMutablePointer<Float>.allocate(capacity: beatRingCapacity)
    private let beatEpochs = UnsafeMutablePointer<Int32>.allocate(capacity: beatRingCapacity)
    private let beatWriteSeqPtr = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
    private let beatReadSeqPtr = UnsafeMutablePointer<Int32>.allocate(capacity: 1)

    // Non-RT analysis & offset smoothing state
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

    private var bpmPoints: [(t: Double, f: Float)] = []
    private var bpmHistory: [Double] = []
    private(set) var detectedBPM: Double = 0

    private(set) var isTapActive: Bool = false
    private(set) var statusDescription: String = L10n.tr("sync.standby")
    private var isWaitingForLock: Bool = true
    var syncMode: VocalSyncMode = .balanced
    var onAutoOffsetUpdated: ((TimeInterval, TimeInterval, String) -> Void)?

    init() {
        midDelays.initialize(repeating: 0, count: 4)
        sideDelays.initialize(repeating: 0, count: 4)
        scratchLeft.initialize(repeating: 0, count: Self.chunkFrames)
        scratchRight.initialize(repeating: 0, count: Self.chunkFrames)
        scratchMid.initialize(repeating: 0, count: Self.chunkFrames)
        scratchSide.initialize(repeating: 0, count: Self.chunkFrames)
        scratchFilteredMid.initialize(repeating: 0, count: Self.chunkFrames)
        scratchFilteredSide.initialize(repeating: 0, count: Self.chunkFrames)
        metricsSeqPtr.initialize(to: 0)
        ioAdaptiveFloorPtr.initialize(to: 0.0005)
        ioAdaptivePeakPtr.initialize(to: 0.01)
        needsFilterResetPtr.initialize(to: 0)
        resetGenPtr.initialize(to: 0)
        beatTimestamps.initialize(repeating: 0, count: Self.beatRingCapacity)
        beatFluxValues.initialize(repeating: 0, count: Self.beatRingCapacity)
        beatEpochs.initialize(repeating: 0, count: Self.beatRingCapacity)
        beatWriteSeqPtr.initialize(to: 0)
        beatReadSeqPtr.initialize(to: 0)
    }

    deinit {
        stop()
        destroyBiquadSetups()
        midDelays.deallocate()
        sideDelays.deallocate()
        scratchLeft.deallocate()
        scratchRight.deallocate()
        scratchMid.deallocate()
        scratchSide.deallocate()
        scratchFilteredMid.deallocate()
        scratchFilteredSide.deallocate()
        metricsSeqPtr.deallocate()
        ioAdaptiveFloorPtr.deallocate()
        ioAdaptivePeakPtr.deallocate()
        needsFilterResetPtr.deallocate()
        resetGenPtr.deallocate()
        beatTimestamps.deallocate()
        beatFluxValues.deallocate()
        beatEpochs.deallocate()
        beatWriteSeqPtr.deallocate()
        beatReadSeqPtr.deallocate()
    }

    func startIfNeeded() {
        guard !isTapActive else { return }
        let now = Date()
        guard now.timeIntervalSince(lastStartAttemptTime) >= 4.0 else { return }
        lastStartAttemptTime = now

        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.name = "TouchBarLyricsVocalTap"
        desc.muteBehavior = .unmuted

        var newTapID: AudioObjectID = kAudioObjectUnknown
        let tapStatus = AudioHardwareCreateProcessTap(desc, &newTapID)
        guard tapStatus == noErr, newTapID != kAudioObjectUnknown else {
            statusDescription = L10n.tr("sync.needPermission")
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
            statusDescription = L10n.tr("sync.tapFailed")
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
            statusDescription = L10n.tr("sync.monitorFailed")
            return
        }
        ioProcID = validProcID

        let startStatus = AudioDeviceStart(aggregateDeviceID, validProcID)
        guard startStatus == noErr else {
            NSLog("[TouchBarLyrics] audio device start failed status=%d", startStatus)
            stop()
            statusDescription = L10n.tr("sync.tapDenied")
            return
        }

        isTapActive = true
        statusDescription = L10n.tr("sync.listening")
        NSLog("[TouchBarLyrics] audio tap active sampleRate=%.0f channels=%d float=%d bits=%d",
              self.sampleRate, self.numChannels, self.isFloat32 ? 1 : 0, self.bitsPerChannel)
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
        lastStartAttemptTime = .distantPast
        lastEvalTime = .distantPast
    }

    func resetForNewTrack() {
        os_unfair_lock_lock(&lock)
        samplesBuffer.removeAll(keepingCapacity: true)
        bpmPoints.removeAll(keepingCapacity: true)
        lastSampleElapsed = -1
        candidateHistory.removeAll()
        backingCandidateHistory.removeAll()
        lastAutoOffset = 0
        lastBackingOffset = 0
        lastVocalClarity = 0
        adaptivePeak = 0.01
        adaptiveFloor = 0.0005
        backingPeak = 0.006
        backingFloor = 0.0002
        bpmHistory.removeAll()
        detectedBPM = 0
        os_unfair_lock_unlock(&lock)

        ioAdaptivePeakPtr.pointee = 0.01
        ioAdaptiveFloorPtr.pointee = 0.0005
        OSMemoryBarrier()
        resetGenPtr.pointee = resetGenPtr.pointee &+ 1
        needsFilterResetPtr.pointee = 1
        OSMemoryBarrier()

        // Publish cleared metrics cleanly for UI readers until next IO buffer arrives
        let seq = metricsSeqPtr.pointee
        metricsSeqPtr.pointee = seq &+ 1
        OSMemoryBarrier()
        ioPublishedVocalProminence = 0
        ioPublishedBackingProminence = 0
        ioPublishedVocalIntonation = 0.45
        ioPublishedSyllableOnset = 0
        OSMemoryBarrier()
        metricsSeqPtr.pointee = seq &+ 2

        isWaitingForLock = true
        if isTapActive {
            statusDescription = L10n.tr("sync.analyzing")
        }
    }

    private func readLatestMetricsLockFree() -> (vocal: Float, backing: Float, intonation: Float, onset: Float) {
        for _ in 0..<8 {
            let s1 = metricsSeqPtr.pointee
            OSMemoryBarrier()
            if (s1 & 1) != 0 { continue }
            let v = ioPublishedVocalProminence
            let b = ioPublishedBackingProminence
            let i = ioPublishedVocalIntonation
            let o = ioPublishedSyllableOnset
            OSMemoryBarrier()
            let s2 = metricsSeqPtr.pointee
            if s1 == s2 {
                return (v, b, i, o)
            }
        }
        return (ioPublishedVocalProminence, ioPublishedBackingProminence, ioPublishedVocalIntonation, ioPublishedSyllableOnset)
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
        let m = readLatestMetricsLockFree()
        let deliveryMod = min(1.16, max(0.86, 0.88 + e * 0.14 + Double(m.onset) * 0.12 + Double(m.intonation) * 0.04))
        return min(1.55, max(0.70, base * deliveryMod))
    }

    func currentVocalIntonation() -> Float {
        readLatestMetricsLockFree().intonation
    }

    func currentSyllableOnset() -> Float {
        readLatestMetricsLockFree().onset
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
        isWaitingForLock = true
        statusDescription = L10n.tr("sync.reset")
        onAutoOffsetUpdated?(0, 0, statusDescription)
    }

    func currentLiveEnergy() -> Float {
        readLatestMetricsLockFree().vocal
    }

    func currentLiveBackingEnergy() -> Float {
        readLatestMetricsLockFree().backing
    }

    /// Returns smooth normalized [0, 1] vocal activity relative to recent track dynamics.
    func currentNormalizedEnergy() -> Float {
        let e = readLatestMetricsLockFree().vocal
        os_unfair_lock_lock(&lock)
        let fl = adaptiveFloor
        let pk = max(fl + 1e-5, adaptivePeak)
        os_unfair_lock_unlock(&lock)
        let norm = (e - fl) / (pk - fl)
        return min(1.0, max(0.0, norm))
    }

    /// Returns normalized [0, 1] stereo-side backing vocal activity relative to track dynamics.
    func currentNormalizedBackingEnergy() -> Float {
        let e = readLatestMetricsLockFree().backing
        os_unfair_lock_lock(&lock)
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
        guard isTapActive, !isEstimated, !lyrics.isEmpty else { return }

        // Guarantee monotonic ascending order for binary-search helpers
        let sortedLyrics = zip(lyrics, lyrics.dropFirst()).allSatisfy({ $0.0.time <= $0.1.time })
            ? lyrics
            : lyrics.sorted { $0.time < $1.time }

        let metrics = readLatestMetricsLockFree()
        let energy = metrics.vocal
        let bgEnergy = metrics.backing
        let now = Date()

        os_unfair_lock_lock(&lock)
        // Detect manual seek / scrub / chapter jump and flush stale audio history
        if lastSampleElapsed >= 0 && (mediaElapsed < lastSampleElapsed - 0.35 || mediaElapsed - lastSampleElapsed > 1.8) {
            samplesBuffer.removeAll(keepingCapacity: true)
            candidateHistory.removeAll()
            backingCandidateHistory.removeAll()
            isWaitingForLock = true
            statusDescription = L10n.tr("sync.realigning")
        }
        lastSampleElapsed = mediaElapsed

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

        if syncMode == .manual {
            statusDescription = L10n.tr("sync.manualFixed")
            return
        }

        guard snapshot.count >= 18 else {
            let pct = Int((Double(snapshot.count) / 18.0) * 100.0)
            isWaitingForLock = true
            statusDescription = L10n.tr("sync.calibrating", pct)
            return
        }

        let sortedEnergies = snapshot.map { $0.energy }.sorted()
        let p20 = sortedEnergies[(sortedEnergies.count * 20) / 100]
        let p85 = sortedEnergies[(sortedEnergies.count * 85) / 100]
        let peakVal = max(p85, p20 + 1e-5)

        os_unfair_lock_lock(&lock)
        adaptiveFloor = p20
        adaptivePeak = peakVal
        os_unfair_lock_unlock(&lock)
        ioAdaptiveFloorPtr.pointee = p20
        ioAdaptivePeakPtr.pointee = peakVal
        OSMemoryBarrier()

        guard p85 > 1e-6, p85 > p20 * 1.45 else {
            statusDescription = L10n.tr("sync.waitingVocal")
            return
        }

        let minWindowT = snapshot.first?.mediaElapsed ?? 0
        let maxWindowT = snapshot.last?.mediaElapsed ?? 0
        let hasActiveLyricRegion = sortedLyrics.contains { $0.time >= (minWindowT - 6.0) && $0.time <= (maxWindowT + 6.0) }
        guard hasActiveLyricRegion else {
            statusDescription = L10n.tr("sync.waitingLyrics")
            return
        }

        let range = max(1e-6, p85 - p20)
        let normEnergy: [Double] = snapshot.map {
            let v = ($0.energy - p20) / range
            return min(1.0, max(0.0, Double(v)))
        }

        var risingOnsets: [(idx: Int, strength: Double)] = []
        for i in 2..<normEnergy.count {
            let rise = normEnergy[i] - min(normEnergy[i - 1], normEnergy[i - 2])
            if rise >= 0.24 && normEnergy[i] >= 0.35 {
                risingOnsets.append((i, min(1.0, rise)))
            }
        }

        let sampleStride = max(1, snapshot.count / 160)
        var sampled: [VocalEnergySample] = []
        var sampledNorm: [Double] = []
        sampled.reserveCapacity(snapshot.count / sampleStride + 1)
        sampledNorm.reserveCapacity(snapshot.count / sampleStride + 1)
        for i in stride(from: 0, to: snapshot.count, by: sampleStride) {
            sampled.append(snapshot[i])
            sampledNorm.append(normEnergy[i])
        }

        func lineIndex(atOrBefore t: TimeInterval) -> Int? {
            var low = 0
            var high = sortedLyrics.count - 1
            var found: Int?
            while low <= high {
                let mid = (low + high) / 2
                if sortedLyrics[mid].time <= t {
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
            var high = sortedLyrics.count
            while low < high {
                let mid = (low + high) / 2
                if sortedLyrics[mid].time < t {
                    low = mid + 1
                } else {
                    high = mid
                }
            }
            var best = TimeInterval.greatestFiniteMagnitude
            if low < sortedLyrics.count { best = abs(sortedLyrics[low].time - t) }
            if low > 0 { best = min(best, abs(sortedLyrics[low - 1].time - t)) }
            return best
        }

        func expectedVocalScore(at t: TimeInterval) -> Double {
            guard let idx = lineIndex(atOrBefore: t) else {
                if let first = sortedLyrics.first, t < first.time - 0.5 { return -0.35 }
                return 0.0
            }
            let cur = sortedLyrics[idx]
            let nextT = (idx + 1 < sortedLyrics.count) ? sortedLyrics[idx + 1].time : (cur.time + 5.0)
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

            let regZero = abs(delta) * 0.025
            let regPrev = abs(delta - lastAutoOffset) * 0.020
            return normalizedCorr + normalizedOnset - regZero - regPrev
        }

        let currentOffsetScore = scoreOffset(lastAutoOffset)
        let zeroScore = scoreOffset(0.0)
        var bestDelta = lastAutoOffset
        var bestScore = currentOffsetScore

        for step in -80...80 {
            let candidate = Double(step) * 0.15
            let s = scoreOffset(candidate)
            if s > bestScore {
                bestScore = s
                bestDelta = candidate
            }
        }

        let quantized = (bestDelta * 10.0).rounded() / 10.0
        let baseline = max(zeroScore, currentOffsetScore)
        let clarityRatio = Double((p85 - p20) / max(1e-5, p85))
        let isDenseChorus = clarityRatio < 0.36 || risingOnsets.count > 12

        let minImprovement: Double
        let maxStepCap: Double
        let requiredConsensus: Int
        switch syncMode {
        case .strictCrowded:
            minImprovement = 0.85
            maxStepCap = 0.25
            requiredConsensus = 3
        case .balanced:
            minImprovement = isDenseChorus ? 0.78 : 0.45
            maxStepCap = isDenseChorus ? 0.30 : 0.70
            requiredConsensus = isDenseChorus ? 3 : 2
        case .fastLock:
            minImprovement = 0.30
            maxStepCap = 1.20
            requiredConsensus = 2
        case .manual:
            minImprovement = 999.0
            maxStepCap = 0.0
            requiredConsensus = 99
        }

        os_unfair_lock_lock(&lock)
        if bestScore - baseline >= minImprovement {
            candidateHistory.append(quantized)
        } else {
            candidateHistory.append(lastAutoOffset)
        }
        if candidateHistory.count > 4 {
            candidateHistory.removeFirst(candidateHistory.count - 4)
        }
        let recent = candidateHistory
        os_unfair_lock_unlock(&lock)

        let targetDelta: Double
        if recent.count >= requiredConsensus {
            let close = recent.filter { abs($0 - quantized) <= 0.40 }
            if close.count >= requiredConsensus && bestScore - zeroScore >= minImprovement {
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
        } else if abs(diff) > 2.0 && recent.count >= requiredConsensus && !isDenseChorus && syncMode != .strictCrowded {
            steppedDelta = (targetDelta * 25.0).rounded() / 25.0
        } else {
            let clampStep = max(-maxStepCap, min(maxStepCap, diff))
            steppedDelta = ((lastAutoOffset + clampStep) * 25.0).rounded() / 25.0
        }

        // High-precision 40ms sub-second micro-phase refinement around settled offset
        if !risingOnsets.isEmpty {
            var bestFineDelta = steppedDelta
            var bestFineScore = -Double.greatestFiniteMagnitude
            for fineStep in -14...14 {
                let fine = steppedDelta + Double(fineStep) * 0.04
                let s = scoreOffset(fine) - abs(fine - steppedDelta) * 0.04
                if s > bestFineScore {
                    bestFineScore = s
                    bestFineDelta = fine
                }
            }
            let baseFineScore = scoreOffset(steppedDelta)
            if bestFineScore - baseFineScore >= 0.12 {
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
        let activeBackingLines = sortedLyrics.filter {
            !($0.backingText ?? "").isEmpty
                && $0.time >= (minT - 4.0)
                && $0.time <= (maxT + 4.0)
        }

        let bgClarity = Double((bgP85 - bgP20) / max(1e-5, bgP85))
        if bgP85 > 1e-6, bgP85 > bgP20 * 1.45, activeBackingLines.count >= 2, (bgClarity >= 0.30 || !isDenseChorus) {
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

            for bgStep in -11...11 {
                let cand = Double(bgStep) * 0.15
                let s = scoreBackingDelta(cand)
                if s > bestBGScore {
                    bestBGScore = s
                    bestBGDelta = cand
                }
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
        if leadChanged || bgChanged || isWaitingForLock {
            isWaitingForLock = false
            lastAutoOffset = steppedDelta
            lastBackingOffset = steppedBackingDelta
            let bpmNow = Int(currentBPM().rounded())
            let bpmTag = bpmNow >= 55 ? "BPM \(bpmNow) | " : ""
            let msg = (abs(steppedDelta) < 0.05 && abs(steppedBackingDelta) < 0.10)
                ? L10n.tr("sync.balancedZero", bpmTag, clarityPct)
                : String(format: "%@Sync: Lead %+.2fs | BG %+.2fs (%d%%)", bpmTag, steppedDelta, steppedBackingDelta, clarityPct)
            statusDescription = msg
            onAutoOffsetUpdated?(steppedDelta, steppedBackingDelta, msg)
        }
    }

    private func estimateRealtimeBPM(nowSec: Double) {
        // Drain SPSC lock-free ring buffer without blocking CoreAudio IOProc
        let w = beatWriteSeqPtr.pointee
        var r = beatReadSeqPtr.pointee
        OSMemoryBarrier()
        let curResetGen = resetGenPtr.pointee

        var drained: [(t: Double, f: Float)] = []
        while r != w {
            let idx = Int(r & Self.beatRingMask)
            if beatEpochs[idx] == curResetGen {
                drained.append((beatTimestamps[idx], beatFluxValues[idx]))
            }
            r = r &+ 1
        }
        OSMemoryBarrier()
        beatReadSeqPtr.pointee = r

        os_unfair_lock_lock(&lock)
        if !drained.isEmpty {
            bpmPoints.append(contentsOf: drained)
        }
        bpmPoints.removeAll { nowSec - $0.t > 5.5 }
        let points = bpmPoints
        os_unfair_lock_unlock(&lock)

        guard points.count >= 80, let firstT = points.first?.t else { return }
        let span = nowSec - firstT
        guard span >= 2.8 else { return }

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

    private func destroyBiquadSetups() {
        if let m = midBiquadSetup {
            vDSP_biquad_DestroySetup(m)
            midBiquadSetup = nil
        }
        if let s = sideBiquadSetup {
            vDSP_biquad_DestroySetup(s)
            sideBiquadSetup = nil
        }
    }

    private func rebuildBiquadSetups() {
        destroyBiquadSetups()
        let coeffs: [Double] = [Double(b0), Double(b1), Double(b2), Double(a1), Double(a2)]
        midBiquadSetup = coeffs.withUnsafeBufferPointer { ptr in
            vDSP_biquad_CreateSetup(ptr.baseAddress!, 1)
        }
        sideBiquadSetup = coeffs.withUnsafeBufferPointer { ptr in
            vDSP_biquad_CreateSetup(ptr.baseAddress!, 1)
        }
        for i in 0..<4 {
            midDelays[i] = 0
            sideDelays[i] = 0
        }
    }

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
            bitsPerChannel = max(8, Int(asbd.mBitsPerChannel))
            isFloat32 = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0 && bitsPerChannel == 32
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
        rebuildBiquadSetups()
        ioLastFilteredMid = 0
    }

    private func fillMidSideChunk(
        rawL: UnsafeMutableRawPointer,
        rawR: UnsafeMutableRawPointer?,
        planarStereo: Bool,
        frameOffset: Int,
        count: Int,
        channels: Int
    ) -> Bool {
        let n = vDSP_Length(count)
        var half: Float = 0.5

        if isFloat32 {
            let ptrL = rawL.assumingMemoryBound(to: Float.self)
            let ptrR = rawR?.assumingMemoryBound(to: Float.self)
            if planarStereo, let pR = ptrR {
                vDSP_vadd(ptrL + frameOffset, 1, pR + frameOffset, 1, scratchMid, 1, n)
                vDSP_vsub(pR + frameOffset, 1, ptrL + frameOffset, 1, scratchSide, 1, n)
                vDSP_vsmul(scratchMid, 1, &half, scratchMid, 1, n)
                vDSP_vsmul(scratchSide, 1, &half, scratchSide, 1, n)
            } else if channels >= 2 {
                let base = ptrL + (frameOffset * channels)
                let stride = vDSP_Stride(channels)
                vDSP_vadd(base, stride, base + 1, stride, scratchMid, 1, n)
                vDSP_vsub(base + 1, stride, base, stride, scratchSide, 1, n)
                vDSP_vsmul(scratchMid, 1, &half, scratchMid, 1, n)
                vDSP_vsmul(scratchSide, 1, &half, scratchSide, 1, n)
            } else {
                memcpy(scratchMid, ptrL + frameOffset, count * MemoryLayout<Float>.size)
                vDSP_vclr(scratchSide, 1, n)
            }
            return true
        }

        if bitsPerChannel == 16 {
            let ptrL = rawL.assumingMemoryBound(to: Int16.self)
            let ptrR = rawR?.assumingMemoryBound(to: Int16.self)
            var scale: Float = 1.0 / 32768.0
            if planarStereo, let pR = ptrR {
                vDSP_vflt16(ptrL + frameOffset, 1, scratchLeft, 1, n)
                vDSP_vflt16(pR + frameOffset, 1, scratchRight, 1, n)
            } else if channels >= 2 {
                let base = ptrL + (frameOffset * channels)
                let stride = vDSP_Stride(channels)
                vDSP_vflt16(base, stride, scratchLeft, 1, n)
                vDSP_vflt16(base + 1, stride, scratchRight, 1, n)
            } else {
                vDSP_vflt16(ptrL + frameOffset, 1, scratchMid, 1, n)
                vDSP_vsmul(scratchMid, 1, &scale, scratchMid, 1, n)
                vDSP_vclr(scratchSide, 1, n)
                return true
            }
            vDSP_vsmul(scratchLeft, 1, &scale, scratchLeft, 1, n)
            vDSP_vsmul(scratchRight, 1, &scale, scratchRight, 1, n)
            vDSP_vadd(scratchLeft, 1, scratchRight, 1, scratchMid, 1, n)
            vDSP_vsub(scratchRight, 1, scratchLeft, 1, scratchSide, 1, n)
            vDSP_vsmul(scratchMid, 1, &half, scratchMid, 1, n)
            vDSP_vsmul(scratchSide, 1, &half, scratchSide, 1, n)
            return true
        }

        if bitsPerChannel == 32 {
            let ptrL = rawL.assumingMemoryBound(to: Int32.self)
            let ptrR = rawR?.assumingMemoryBound(to: Int32.self)
            var scale: Float = 1.0 / 2147483648.0
            if planarStereo, let pR = ptrR {
                vDSP_vflt32(ptrL + frameOffset, 1, scratchLeft, 1, n)
                vDSP_vflt32(pR + frameOffset, 1, scratchRight, 1, n)
            } else if channels >= 2 {
                let base = ptrL + (frameOffset * channels)
                let stride = vDSP_Stride(channels)
                vDSP_vflt32(base, stride, scratchLeft, 1, n)
                vDSP_vflt32(base + 1, stride, scratchRight, 1, n)
            } else {
                vDSP_vflt32(ptrL + frameOffset, 1, scratchMid, 1, n)
                vDSP_vsmul(scratchMid, 1, &scale, scratchMid, 1, n)
                vDSP_vclr(scratchSide, 1, n)
                return true
            }
            vDSP_vsmul(scratchLeft, 1, &scale, scratchLeft, 1, n)
            vDSP_vsmul(scratchRight, 1, &scale, scratchRight, 1, n)
            vDSP_vadd(scratchLeft, 1, scratchRight, 1, scratchMid, 1, n)
            vDSP_vsub(scratchRight, 1, scratchLeft, 1, scratchSide, 1, n)
            vDSP_vsmul(scratchMid, 1, &half, scratchMid, 1, n)
            vDSP_vsmul(scratchSide, 1, &half, scratchSide, 1, n)
            return true
        }

        return false
    }

    private func processAudioBufferList(_ bufferListPtr: UnsafePointer<AudioBufferList>) {
        // Real-time CoreAudio IO thread: strictly zero allocations and zero mutex locks
        let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferListPtr))
        guard let firstBuf = abl.first,
              let rawL = firstBuf.mData,
              let midSetup = midBiquadSetup,
              let sideSetup = sideBiquadSetup else { return }

        let bytesPerSample = isFloat32 ? MemoryLayout<Float>.size : max(1, bitsPerChannel / 8)
        let planarStereo = (abl.count >= 2 && firstBuf.mNumberChannels == 1)
        let rawR = planarStereo ? abl[1].mData : nil
        let channels = planarStereo ? 2 : max(1, Int(firstBuf.mNumberChannels))
        let frames: Int = planarStereo
            ? Int(firstBuf.mDataByteSize) / bytesPerSample
            : (Int(firstBuf.mDataByteSize) / bytesPerSample) / channels
        guard frames > 0 else { return }

        if needsFilterResetPtr.pointee != 0 {
            OSMemoryBarrier()
            needsFilterResetPtr.pointee = 0
            for i in 0..<4 {
                midDelays[i] = 0
                sideDelays[i] = 0
            }
            ioLastFilteredMid = 0
            ioPrevFullRMS = 0
            ioPrevProminenceForOnset = 0
            ioVocalProminence = 0
            ioBackingProminence = 0
            ioVocalIntonation = 0.45
            ioSyllableOnset = 0
            ioLastSeenResetGen = resetGenPtr.pointee
        }

        var midSq: Float = 0
        var sideSq: Float = 0
        var totalSq: Float = 0
        var zcrCount: Int = 0
        var prevYm: Float = ioLastFilteredMid

        var offset = 0
        while offset < frames {
            let chunkCount = min(Self.chunkFrames, frames - offset)
            guard fillMidSideChunk(
                rawL: rawL,
                rawR: rawR,
                planarStereo: planarStereo,
                frameOffset: offset,
                count: chunkCount,
                channels: channels
            ) else { return }

            let n = vDSP_Length(chunkCount)
            var chunkTotalSq: Float = 0
            vDSP_svesq(scratchMid, 1, &chunkTotalSq, n)
            totalSq += chunkTotalSq

            vDSP_biquad(midSetup, midDelays, scratchMid, 1, scratchFilteredMid, 1, n)
            vDSP_biquad(sideSetup, sideDelays, scratchSide, 1, scratchFilteredSide, 1, n)

            var chunkMidSq: Float = 0
            var chunkSideSq: Float = 0
            vDSP_svesq(scratchFilteredMid, 1, &chunkMidSq, n)
            vDSP_svesq(scratchFilteredSide, 1, &chunkSideSq, n)
            midSq += chunkMidSq
            sideSq += chunkSideSq

            for i in 0..<chunkCount {
                let ym = scratchFilteredMid[i]
                if prevYm <= 0 && ym > 0 { zcrCount += 1 }
                prevYm = ym
            }

            offset += chunkCount
        }
        ioLastFilteredMid = prevYm

        let invN = 1.0 / Float(frames)
        let midVocalRMS = sqrtf(midSq * invN)
        let sideVocalRMS = sqrtf(sideSq * invN)
        let totalRMS = sqrtf(totalSq * invN)

        let centerRatio = min(1.0, max(0.18, midVocalRMS / (midVocalRMS + 0.65 * sideVocalRMS + 1e-6)))
        let bandRatio = min(1.0, max(0.18, midVocalRMS / (totalRMS + 1e-6)))
        let prominence = midVocalRMS * centerRatio * bandRatio

        let sideBandRatio = min(1.0, max(0.15, sideVocalRMS / (totalRMS + 1e-6)))
        let sideProminence = sideVocalRMS * sideBandRatio

        let zcrHz = (Float(zcrCount) * Float(sampleRate)) / max(1.0, Float(frames))
        let rawIntonation = min(1.0, max(0.0, (zcrHz - 240.0) / 1400.0))
        let nowTS = CFAbsoluteTimeGetCurrent()

        OSMemoryBarrier()
        let curFloor = ioAdaptiveFloorPtr.pointee
        let curPeak = ioAdaptivePeakPtr.pointee

        let prevProm = ioPrevProminenceForOnset
        let onsetImpulse: Float = prominence > max(curFloor * 1.15, prevProm * 1.16)
            ? min(1.0, (prominence - prevProm) / max(1e-4, curPeak * 0.65))
            : 0.0
        ioPrevProminenceForOnset = prominence * 0.60 + prevProm * 0.40
        ioVocalProminence = ioVocalProminence * 0.62 + prominence * 0.38
        ioBackingProminence = ioBackingProminence * 0.60 + sideProminence * 0.40
        if prominence > curFloor * 1.1 {
            ioVocalIntonation = ioVocalIntonation * 0.72 + rawIntonation * 0.28
        }
        ioSyllableOnset = max(onsetImpulse, ioSyllableOnset * 0.84)

        // Lock-free SeqLock metrics publish
        let seq = metricsSeqPtr.pointee
        metricsSeqPtr.pointee = seq &+ 1
        OSMemoryBarrier()
        ioPublishedVocalProminence = ioVocalProminence
        ioPublishedBackingProminence = ioBackingProminence
        ioPublishedVocalIntonation = ioVocalIntonation
        ioPublishedSyllableOnset = ioSyllableOnset
        OSMemoryBarrier()
        metricsSeqPtr.pointee = seq &+ 2

        // Lock-free SPSC ring push for BPM onset flux
        let flux = max(0, totalRMS - ioPrevFullRMS)
        ioPrevFullRMS = ioPrevFullRMS * 0.45 + totalRMS * 0.55

        let w = beatWriteSeqPtr.pointee
        let r = beatReadSeqPtr.pointee
        OSMemoryBarrier()
        if (w &- r) < Int32(Self.beatRingCapacity) {
            let slot = Int(w & Self.beatRingMask)
            beatTimestamps[slot] = nowTS
            beatFluxValues[slot] = flux
            beatEpochs[slot] = ioLastSeenResetGen
            OSMemoryBarrier()
            beatWriteSeqPtr.pointee = w &+ 1
        }
    }
}
