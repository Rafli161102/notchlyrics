import Cocoa

// MARK: - Private Touch Bar / DFRFoundation Bridge

private typealias DFRElementSetPresenceFn = @convention(c) (CFString, Bool) -> Void
private typealias DFRShowsCloseBoxFn = @convention(c) (Bool) -> Void

private enum DFRBridge {
    private static let handle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation",
        RTLD_NOW
    )

    static func setControlStripPresence(_ identifier: String, visible: Bool) {
        guard let h = handle,
              let sym = dlsym(h, "DFRElementSetControlStripPresenceForIdentifier") else { return }
        let fn = unsafeBitCast(sym, to: DFRElementSetPresenceFn.self)
        fn(identifier as CFString, visible)
    }

    static func setShowsCloseBoxWhenFrontMost(_ show: Bool) {
        guard let h = handle,
              let sym = dlsym(h, "DFRSystemModalShowsCloseBoxWhenFrontMost") else { return }
        let fn = unsafeBitCast(sym, to: DFRShowsCloseBoxFn.self)
        fn(show)
    }

    static func addSystemTrayItem(_ item: NSTouchBarItem) {
        let sel = NSSelectorFromString("addSystemTrayItem:")
        if NSTouchBarItem.responds(to: sel) {
            NSTouchBarItem.perform(sel, with: item)
        }
    }

    static func presentSystemModalTouchBar(_ touchBar: NSTouchBar, trayID: String) {
        let sel = NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:")
        if NSTouchBar.responds(to: sel) {
            NSTouchBar.perform(sel, with: touchBar, with: trayID as NSString)
        }
    }

    static func dismissSystemModalTouchBar(_ touchBar: NSTouchBar) {
        let sel = NSSelectorFromString("dismissSystemModalTouchBar:")
        if NSTouchBar.responds(to: sel) {
            NSTouchBar.perform(sel, with: touchBar)
        }
    }
}

struct NowPlayingState: Equatable {
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var duration: TimeInterval = 0
    var baseElapsed: TimeInterval = 0
    var timestamp: Date = Date()
    var playbackRate: Double = 1.0
    var playing: Bool = false
    var parentBundleID: String = ""
    var bundleID: String = ""
    var artworkData: String = ""

    var trackKey: String {
        "\(title.lowercased())|\(artist.lowercased())|\(Int(duration.rounded()))"
    }

    var isSafari: Bool {
        parentBundleID == "com.apple.Safari" || bundleID == "com.apple.Safari"
    }

    func currentElapsed(at now: Date = Date()) -> TimeInterval {
        guard playing else { return max(0, baseElapsed) }
        let rate = playbackRate > 0 ? playbackRate : 1.0
        let delta = max(0, now.timeIntervalSince(timestamp))
        let computed = baseElapsed + delta * rate
        return duration > 0 ? min(max(0, computed), duration) : max(0, computed)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSTouchBarDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var mainMenu = NSMenu()
    private var sigSources: [DispatchSourceSignal] = []

    private let trayID = "com.user.TouchBarLyrics.tray"
    private let lyricsItemID = NSTouchBarItem.Identifier("com.user.TouchBarLyrics.lyrics")
    private var trayItem: NSCustomTouchBarItem!
    private var lyricsTouchBar: NSTouchBar!
    private var lyricsView: TouchBarLyricsView!
    private var notchWindowController: NotchLyricsWindowController?
    private var themeWindowController: ThemeEditorWindowController?

    private var adapterProcess: Process?
    private var adapterPipe: Pipe?
    private var appleEventsPollTimer: Timer?
    private var isUsingNativePoller = false
    private let streamQueue = DispatchQueue(label: "com.user.TouchBarLyrics.stream", qos: .utility)
    private var lineBuffer = Data()

    private let fetcher = LyricsParserAndFetcher()
    private let vocalSync = VocalAutoSyncEngine()

    private var currentState = NowPlayingState()
    private var currentTrackKey = ""
    private var activeRawLyrics: [LyricLine] = []
    private var activeRomanizedLyrics: [LyricLine] = []
    private var activeLyrics: [LyricLine] = []
    private var lyricsSourceName = ""
    private var isEstimatedLyrics = false
    private var hasExactWordTimings = false
    private var isFetchingLyrics = false
    private var lyricsStatusText = "Putar lagu di Safari"
    private var autoVocalOffset: TimeInterval = 0
    private var autoBackingOffset: TimeInterval = 0
    private var artworkPalette: SongColorPalette?
    private var artworkIdentity = ""

    private var renderTimer: Timer?
    private var isModalPresented = false

    private let defaults = UserDefaults.standard
    private let keyAutoShow = "autoShowTouchBar"
    private let keySafariOnly = "safariOnly"
    private let keyAutoVocalSync = "autoVocalSyncEnabled"
    private let keyRomanizeLyrics = "romanizeLyrics"
    private let keyArtworkColors = "artworkColorsEnabled"
    private let keyCharacterAnimation = "characterAnimationEnabled"
    private let keyDisplayMode = "displayMode"

    private var autoShowEnabled: Bool {
        get { defaults.object(forKey: keyAutoShow) == nil ? true : defaults.bool(forKey: keyAutoShow) }
        set { defaults.set(newValue, forKey: keyAutoShow) }
    }

    private var safariOnlyEnabled: Bool {
        get { defaults.object(forKey: keySafariOnly) == nil ? true : defaults.bool(forKey: keySafariOnly) }
        set { defaults.set(newValue, forKey: keySafariOnly) }
    }

    private var autoVocalSyncEnabled: Bool {
        get { defaults.object(forKey: keyAutoVocalSync) == nil ? true : defaults.bool(forKey: keyAutoVocalSync) }
        set { defaults.set(newValue, forKey: keyAutoVocalSync) }
    }

    private var romanizeEnabled: Bool {
        get { defaults.object(forKey: keyRomanizeLyrics) == nil ? true : defaults.bool(forKey: keyRomanizeLyrics) }
        set { defaults.set(newValue, forKey: keyRomanizeLyrics) }
    }

    private var artworkColorsEnabled: Bool {
        get { defaults.object(forKey: keyArtworkColors) == nil ? true : defaults.bool(forKey: keyArtworkColors) }
        set { defaults.set(newValue, forKey: keyArtworkColors) }
    }

    private var characterAnimationEnabled: Bool {
        get { defaults.object(forKey: keyCharacterAnimation) == nil ? true : defaults.bool(forKey: keyCharacterAnimation) }
        set { defaults.set(newValue, forKey: keyCharacterAnimation) }
    }

    private var displayMode: DisplayMode {
        get {
            if let raw = defaults.string(forKey: keyDisplayMode),
               let mode = DisplayMode(rawValue: raw) {
                return mode
            }
            // Auto-select Notch on MacBooks with a physical camera housing (no Touch Bar)
            if let screen = NSScreen.main ?? NSScreen.screens.first, screen.safeAreaInsets.top > 0 {
                return .notch
            }
            return .defaultMode
        }
        set { defaults.set(newValue.rawValue, forKey: keyDisplayMode) }
    }

    private lazy var resolvedAdapterPaths: (script: String, framework: String)? = {
        let fm = FileManager.default
        var candidates: [(String, String)] = []
        if let resPath = Bundle.main.resourcePath {
            candidates.append((
                (resPath as NSString).appendingPathComponent("mediaremote-adapter.pl"),
                (resPath as NSString).appendingPathComponent("MediaRemoteAdapter.framework")
            ))
        }
        let appSup = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Application Support/TouchBarLyrics/MediaRemoteAdapter")
        candidates.append((
            (appSup as NSString).appendingPathComponent("mediaremote-adapter.pl"),
            (appSup as NSString).appendingPathComponent("MediaRemoteAdapter.framework")
        ))
        candidates.append((
            "/Applications/Atoll.app/Contents/Resources/mediaremote-adapter.pl",
            "/Applications/Atoll.app/Contents/Resources/MediaRemoteAdapter.framework"
        ))
        return candidates.first { fm.isExecutableFile(atPath: $0.0) && fm.fileExists(atPath: $0.1) }
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let bundleID = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if !others.isEmpty {
                NSApp.terminate(nil)
                return
            }
        }

        setupTerminationHandlers()
        setupStatusBar()
        setupTouchBar()

        ThemeStore.shared.onThemeChanged = { [weak self] theme in
            self?.lyricsView.applyTheme(theme)
            self?.notchWindowController?.applyTheme(theme)
            self?.refreshDisplay()
        }

        vocalSync.onAutoOffsetUpdated = { [weak self] leadOffset, backingOffset, message in
            guard let self = self else { return }
            self.autoVocalOffset = leadOffset
            self.autoBackingOffset = backingOffset
            if !self.currentTrackKey.isEmpty && !self.activeLyrics.isEmpty && !self.isEstimatedLyrics {
                self.fetcher.updateCalibration(
                    forKey: self.currentTrackKey,
                    rawTitle: self.currentState.title,
                    rawArtist: self.currentState.artist,
                    leadOffset: leadOffset,
                    backingOffset: backingOffset,
                    bpm: self.vocalSync.currentBPM()
                )
            }
            NSLog("[TouchBarLyrics] vocal lead=%.2f backing=%.2f status=%@", leadOffset, backingOffset, message)
            self.refreshDisplay()
        }

        startMediaStream()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopRenderTimer()
        vocalSync.stop()
        stopMediaStream()
        DFRBridge.dismissSystemModalTouchBar(lyricsTouchBar)
        DFRBridge.setControlStripPresence(trayID, visible: false)
    }

    private func setupTerminationHandlers() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { [weak self] in
                self?.vocalSync.stop()
                self?.stopMediaStream()
                NSApp.terminate(nil)
            }
            src.resume()
            sigSources.append(src)
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handlePowerOff),
            name: NSWorkspace.willPowerOffNotification,
            object: nil
        )
    }

    @objc private func handlePowerOff() {
        vocalSync.stop()
        stopMediaStream()
        NSApp.terminate(nil)
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "music.note.list", accessibilityDescription: "TouchBarLyrics") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "Lyrics"
            }
            button.toolTip = "TouchBarLyrics"
        }
        mainMenu.delegate = self
        statusItem.menu = mainMenu
    }

    private func setupTouchBar() {
        DFRBridge.setShowsCloseBoxWhenFrontMost(true)

        let id = NSTouchBarItem.Identifier(trayID)
        trayItem = NSCustomTouchBarItem(identifier: id)
        let trayBtn = NSButton(title: "♫", target: self, action: #selector(presentModal))
        if let img = NSImage(systemSymbolName: "music.quarternote.3", accessibilityDescription: "Lyrics") {
            img.isTemplate = true
            trayBtn.image = img
            trayBtn.title = ""
        }
        trayItem.view = trayBtn
        DFRBridge.addSystemTrayItem(trayItem)
        DFRBridge.setControlStripPresence(trayID, visible: true)

        lyricsView = TouchBarLyricsView { [weak self] in
            self?.sendPlayPauseCommand()
        }
        lyricsView.characterAnimationEnabled = characterAnimationEnabled

        lyricsTouchBar = NSTouchBar()
        lyricsTouchBar.delegate = self
        lyricsTouchBar.defaultItemIdentifiers = [lyricsItemID]

        setupNotch()
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == lyricsItemID else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.view = lyricsView
        return item
    }

    private func setupNotch() {
        let controller = NotchLyricsWindowController(
            onTogglePlayPause: { [weak self] in self?.sendPlayPauseCommand() },
            onSendCommand: { [weak self] command in self?.sendMediaRemoteCommand(command) }
        )
        controller.setCharacterAnimationEnabled(characterAnimationEnabled)
        notchWindowController = controller
        applyDisplayMode()
    }

    @objc private func toggleTouchBarModal() {
        if isModalPresented {
            dismissModal()
        } else {
            presentModal()
        }
    }

    @objc private func presentModal() {
        guard displayMode.showsTouchBar else { return }
        DFRBridge.presentSystemModalTouchBar(lyricsTouchBar, trayID: trayID)
        isModalPresented = true
        if currentState.playing {
            startRenderTimer()
        }
        refreshDisplay()
    }

    private func dismissModal() {
        DFRBridge.dismissSystemModalTouchBar(lyricsTouchBar)
        isModalPresented = false
        if currentState.playing {
            startRenderTimer()
        }
    }

    private func applyDisplayMode() {
        notchWindowController?.setVisible(displayMode.showsNotch)
        if !displayMode.showsTouchBar {
            dismissModal()
        }
        if currentState.playing {
            startRenderTimer()
        }
        refreshDisplay()
    }

    @objc private func selectDisplayMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = DisplayMode(rawValue: raw) else { return }
        displayMode = mode
        applyDisplayMode()
    }

    // MARK: - MediaRemote Stream & Zero-Dependency Native macOS Fallback

    private func startMediaStream() {
        guard let paths = resolvedAdapterPaths else {
            isUsingNativePoller = true
            startNativeAppleScriptPoller()
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        proc.arguments = [paths.script, paths.framework, "stream", "--debounce=10"]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            self?.streamQueue.async {
                self?.processIncomingData(data)
            }
        }

        do {
            try proc.run()
            adapterProcess = proc
            adapterPipe = pipe
        } catch {
            isUsingNativePoller = true
            startNativeAppleScriptPoller()
        }
    }

    private func stopMediaStream() {
        appleEventsPollTimer?.invalidate()
        appleEventsPollTimer = nil
        adapterPipe?.fileHandleForReading.readabilityHandler = nil
        if let proc = adapterProcess, proc.isRunning {
            let pid = proc.processIdentifier
            proc.terminate()
            for _ in 0..<5 {
                if !proc.isRunning { break }
                usleep(40_000)
            }
            if proc.isRunning {
                kill(pid, SIGKILL)
            }
        }
        adapterProcess = nil
        adapterPipe = nil
    }

    private func startNativeAppleScriptPoller() {
        lyricsStatusText = "Menunggu pemutar media (Music/Spotify/Safari)..."
        appleEventsPollTimer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            self?.pollNativePlayersOnce()
        }
        RunLoop.main.add(t, forMode: .common)
        appleEventsPollTimer = t
        pollNativePlayersOnce()
    }

    private func pollNativePlayersOnce() {
        let safariOnly = safariOnlyEnabled
        streamQueue.async { [weak self] in
            let script = """
            on run
              set sep to "|||"
              if not \(safariOnly ? "true" : "false") then
                if application "Spotify" is running then
                  tell application "Spotify"
                    set ps to player state as string
                    if ps is "playing" then
                      return "com.spotify.client" & sep & "playing" & sep & (name of current track) & sep & (artist of current track) & sep & (album of current track) & sep & ((duration of current track) / 1000.0) & sep & (player position)
                    end if
                  end tell
                end if
                if application "Music" is running then
                  tell application "Music"
                    set ps to player state as string
                    if ps is "playing" then
                      return "com.apple.Music" & sep & "playing" & sep & (name of current track) & sep & (artist of current track) & sep & (album of current track) & sep & (duration of current track) & sep & (player position)
                    end if
                  end tell
                end if
              end if
              if application "Safari" is running then
                tell application "Safari"
                  if (count of windows) > 0 then
                    try
                      set t to current tab of front window
                      set jsRes to do JavaScript "(function(){var m=Array.from(document.querySelectorAll('video,audio')).find(function(x){return !x.paused && x.duration>0;})||document.querySelector('video,audio');var md=(navigator.mediaSession&&navigator.mediaSession.metadata)||{};if(!m)return '';return [m.paused?'paused':'playing', md.title||document.title||'', md.artist||'', md.album||'', m.duration||0, m.currentTime||0].join('|||');})()" in t
                      if jsRes is not "" then return "com.apple.Safari" & sep & jsRes
                    end try
                  end if
                end tell
              end if
              return ""
            end run
            """
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            proc.arguments = ["-e", script]
            let outPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = FileHandle.nullDevice
            do {
                try proc.run()
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                proc.waitUntilExit()
                guard let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !raw.isEmpty else {
                    return
                }
                let parts = raw.components(separatedBy: "|||")
                guard parts.count >= 7 else { return }
                let payload: [String: Any] = [
                    "bundleIdentifier": parts[0],
                    "parentApplicationBundleIdentifier": parts[0],
                    "playing": parts[1] == "playing",
                    "title": parts[2],
                    "artist": parts[3],
                    "album": parts[4],
                    "duration": Double(parts[5]) ?? 0,
                    "elapsedTime": Double(parts[6]) ?? 0,
                    "playbackRate": 1.0
                ]
                DispatchQueue.main.async {
                    self?.applyPayload(payload, isDiff: false)
                }
            } catch {
                return
            }
        }
    }

    private func sendPlayPauseCommand() {
        sendMediaRemoteCommand(2)
    }

    private func sendMediaRemoteCommand(_ command: Int) {
        if let paths = resolvedAdapterPaths {
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
                proc.arguments = [paths.script, paths.framework, "send", "\(command)"]
                proc.standardOutput = FileHandle.nullDevice
                proc.standardError = FileHandle.nullDevice
                try? proc.run()
                proc.waitUntilExit()
            }
            return
        }

        let bundle = currentState.parentBundleID.isEmpty ? currentState.bundleID : currentState.parentBundleID
        DispatchQueue.global(qos: .userInitiated).async {
            let script: String
            if bundle == "com.spotify.client" {
                let verb = (command == 4) ? "next track" : (command == 5 ? "previous track" : "playpause")
                script = "tell application \"Spotify\" to \(verb)"
            } else if bundle == "com.apple.Music" {
                let verb = (command == 4) ? "next track" : (command == 5 ? "previous track" : "playpause")
                script = "tell application \"Music\" to \(verb)"
            } else {
                let jsCmd = (command == 2) ? "(function(){var m=document.querySelector('video,audio');if(m){if(m.paused)m.play();else m.pause();}})()" : ""
                guard !jsCmd.isEmpty else { return }
                script = "tell application \"Safari\" to do JavaScript \"\(jsCmd)\" in current tab of front window"
            }
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            proc.arguments = ["-e", script]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try? proc.run()
            proc.waitUntilExit()
        }
    }

    private func processIncomingData(_ chunk: Data) {
        var searchStart = lineBuffer.count
        lineBuffer.append(chunk)
        while searchStart < lineBuffer.count,
              let newlineIndex = lineBuffer[searchStart...].firstIndex(of: 0x0A) {
            let lineData = lineBuffer.subdata(in: 0..<newlineIndex)
            lineBuffer.removeSubrange(0...newlineIndex)
            searchStart = 0
            if !lineData.isEmpty {
                handleJSONLine(lineData)
            }
        }
    }

    private func handleJSONLine(_ data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = obj["payload"] as? [String: Any] else {
            return
        }
        let isDiff = (obj["diff"] as? Bool) ?? false

        DispatchQueue.main.async { [weak self] in
            self?.applyPayload(payload, isDiff: isDiff)
        }
    }

    private func applyPayload(_ payload: [String: Any], isDiff: Bool) {
        if !isDiff && payload.isEmpty {
            currentState = NowPlayingState()
            activeLyrics = []
            activeRawLyrics = []
            activeRomanizedLyrics = []
            currentTrackKey = ""
            autoVocalOffset = 0
            autoBackingOffset = 0
            resetArtworkPalette()
            lyricsStatusText = "Putar lagu di Safari"
            stopRenderTimer()
            vocalSync.stop()
            refreshDisplay()
            return
        }

        let wasPlaying = currentState.playing
        var next = isDiff ? currentState : NowPlayingState()
        if let v = payload["title"] as? String { next.title = v }
        if let v = payload["artist"] as? String { next.artist = v }
        if let v = payload["album"] as? String { next.album = v }
        if let v = payload["duration"] as? Double { next.duration = v }
        if let v = payload["elapsedTime"] as? Double { next.baseElapsed = v }
        if let v = payload["playbackRate"] as? Double { next.playbackRate = v }
        if let v = payload["playing"] as? Bool { next.playing = v }
        if let v = payload["parentApplicationBundleIdentifier"] as? String { next.parentBundleID = v }
        if let v = payload["bundleIdentifier"] as? String { next.bundleID = v }
        if let v = payload["artworkData"] as? String { next.artworkData = v }

        if !wasPlaying && next.playing && payload["elapsedTime"] == nil {
            next.timestamp = Date()
        } else if let tsStr = payload["timestamp"] as? String, let parsed = parseISO8601(tsStr) {
            next.timestamp = parsed
        } else if !isDiff || payload["elapsedTime"] != nil {
            next.timestamp = Date()
        }

        if safariOnlyEnabled && !next.isSafari {
            currentState = next
            currentState.playing = false
            currentTrackKey = ""
            activeLyrics = []
            activeRawLyrics = []
            activeRomanizedLyrics = []
            autoVocalOffset = 0
            autoBackingOffset = 0
            isFetchingLyrics = false
            resetArtworkPalette()
            stopRenderTimer()
            vocalSync.stop()
            lyricsStatusText = "Menunggu audio dari Safari..."
            refreshDisplay()
            return
        }

        let trackChanged = (next.trackKey != currentTrackKey && !next.title.isEmpty)
        if trackChanged && isDiff && payload["elapsedTime"] == nil {
            next.baseElapsed = 0
            next.timestamp = Date()
        }
        currentState = next

        if trackChanged {
            currentTrackKey = next.trackKey
            activeLyrics = []
            activeRawLyrics = []
            activeRomanizedLyrics = []
            autoVocalOffset = 0
            autoBackingOffset = 0
            lyricsSourceName = ""
            isEstimatedLyrics = false
            isFetchingLyrics = true
            lyricsStatusText = "Mencari lirik: \(fetcher.cleanTitle(next.title))..."
            resetArtworkPalette()
            vocalSync.resetForNewTrack()
            loadLyrics(for: next)
        }

        updateArtworkPaletteIfNeeded(from: next, force: trackChanged)

        if next.playing {
            if autoVocalSyncEnabled {
                vocalSync.startIfNeeded()
            }
            startRenderTimer()
            if autoShowEnabled && !isModalPresented && !next.title.isEmpty {
                presentModal()
            }
        } else {
            stopRenderTimer()
            vocalSync.stop()
        }

        refreshDisplay()
    }

    private func loadLyrics(for state: NowPlayingState, forceRefresh: Bool = false) {
        let key = state.trackKey
        fetcher.fetchLyrics(
            cacheKey: key,
            rawTitle: state.title,
            rawArtist: state.artist,
            album: state.album,
            duration: state.duration,
            forceRefresh: forceRefresh
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, self.currentTrackKey == key else { return }
                let isUpgradeForSameTrack = !self.activeRawLyrics.isEmpty
                self.isFetchingLyrics = false
                self.activeRawLyrics = result.lines
                self.activeRomanizedLyrics = result.romanizedLines
                self.applyLyricsPreference()
                self.lyricsSourceName = result.sourceName
                self.isEstimatedLyrics = result.isEstimated
                self.hasExactWordTimings = result.hasWordTimings
                // Immediately restore persisted audio sync calibration for previously played songs (< 1ms!)
                if !isUpgradeForSameTrack && !forceRefresh && (result.calibratedLeadOffset != 0 || result.calibratedBackingOffset != 0) {
                    self.autoVocalOffset = result.calibratedLeadOffset
                    self.autoBackingOffset = result.calibratedBackingOffset
                }
                if result.lines.isEmpty && !self.currentState.title.isEmpty {
                    let cleanT = self.fetcher.cleanTitle(self.currentState.title)
                    let cleanA = self.fetcher.cleanArtist(self.currentState.artist)
                    self.lyricsStatusText = cleanA.isEmpty ? cleanT : "\(cleanT) - \(cleanA)"
                }
                self.refreshDisplay()
            }
        }
    }

    private func applyLyricsPreference() {
        activeLyrics = romanizeEnabled ? activeRomanizedLyrics : activeRawLyrics
    }

    // MARK: - Artwork Color Palette

    private func resetArtworkPalette() {
        artworkIdentity = ""
        guard artworkPalette != nil else { return }
        artworkPalette = nil
        lyricsView.applyArtworkPalette(nil)
        notchWindowController?.applyArtworkPalette(nil)
    }

    private func updateArtworkPaletteIfNeeded(from state: NowPlayingState, force: Bool) {
        guard artworkColorsEnabled else { return }
        let encoded = state.artworkData
        guard !encoded.isEmpty else { return }

        // Artwork payloads are megabytes; a cheap identity check avoids
        // re-decoding the same cover on every MediaRemote diff tick.
        // NSString.length and substringing are O(1)-ish, unlike String.count
        // which walks the whole base64 blob.
        let ns = encoded as NSString
        let head = ns.substring(to: min(24, ns.length))
        let tail = ns.substring(from: max(0, ns.length - 24))
        let identity = "\(ns.length)|\(head)|\(tail)"
        guard force || identity != artworkIdentity else { return }
        artworkIdentity = identity

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let bytes = Data(base64Encoded: encoded) else { return }
            let palette = ArtworkPaletteExtractor.extract(from: bytes)
            DispatchQueue.main.async {
                guard let self = self,
                      self.artworkIdentity == identity,
                      self.artworkColorsEnabled else { return }
                self.artworkPalette = palette
                self.lyricsView.applyArtworkPalette(palette)
                self.notchWindowController?.applyArtworkPalette(palette)
            }
        }
    }

    private func parseISO8601(_ str: String) -> Date? {
        let fmt1 = ISO8601DateFormatter()
        fmt1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fmt1.date(from: str) { return d }
        let fmt2 = ISO8601DateFormatter()
        fmt2.formatOptions = [.withInternetDateTime]
        return fmt2.date(from: str)
    }

    // MARK: - Render Loop

    private var renderTimerInterval: TimeInterval = 0

    private func startRenderTimer() {
        let desiredInterval: TimeInterval = (displayMode == .hidden) ? 0.12 : 0.0167
        if renderTimer != nil && abs(renderTimerInterval - desiredInterval) < 0.005 {
            return
        }
        stopRenderTimer()
        renderTimerInterval = desiredInterval
        let t = Timer.scheduledTimer(withTimeInterval: desiredInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        renderTimer = t
    }

    private func stopRenderTimer() {
        renderTimer?.invalidate()
        renderTimer = nil
        renderTimerInterval = 0
    }

    private func tick() {
        if autoVocalSyncEnabled && currentState.playing && !activeLyrics.isEmpty {
            vocalSync.recordAndAlign(
                mediaElapsed: currentState.currentElapsed(),
                lyrics: activeLyrics,
                isEstimated: isEstimatedLyrics
            )
        }
        refreshDisplay()
    }

    private func refreshDisplay() {
        let activeTheme = ThemeStore.shared.activeTheme
        let rawElapsed = currentState.currentElapsed()
        // Subtle 25ms VSync compensation avoids early line jumps while preserving instant response
        let displayLead: TimeInterval = currentState.playing ? 0.025 : 0.0
        let elapsed = rawElapsed + autoVocalOffset + activeTheme.karaokeOffsetSeconds + displayLead
        // Keep karaoke pace steady using track line/word intervals + user speed multiplier (avoids BPM jitter)
        let wordScale = Double(activeTheme.wordSpeedScale)
        let songProg: CGFloat = currentState.duration > 0
            ? CGFloat(min(max(0, rawElapsed / currentState.duration), 1))
            : 0

        var mainText = lyricsStatusText
        var backingText: String? = nil
        var lineProg: CGFloat = 1.0
        var backProg: CGFloat = 1.0

        if !activeLyrics.isEmpty {
            if let idx = activeLyrics.lastIndex(where: { $0.time <= elapsed }) {
                let cur = activeLyrics[idx]
                mainText = cur.mainText
                if isEstimatedLyrics && !mainText.isEmpty {
                    mainText = "~ \(mainText)"
                }
                let nextT = (idx + 1 < activeLyrics.count)
                    ? activeLyrics[idx + 1].time
                    : (currentState.duration > cur.time ? currentState.duration : cur.time + 5.0)
                lineProg = cur.singingProgress(at: elapsed, nextLineTime: nextT, wordSpeedScale: wordScale)

                if let rawBg = cur.backingText, !rawBg.isEmpty {
                    let effBackStart = (cur.backingTime ?? cur.time) + autoBackingOffset + activeTheme.karaokeOffsetSeconds
                    if elapsed >= effBackStart - 0.06 || cur.mainText.isEmpty {
                        backingText = rawBg
                        backProg = cur.backingProgress(at: elapsed - autoBackingOffset, nextLineTime: nextT, wordSpeedScale: wordScale)
                    }
                }
            } else {
                mainText = fetcher.cleanTitle(currentState.title)
                backingText = nil
                lineProg = 0.0
                backProg = 0.0
            }
        } else if !currentState.title.isEmpty {
            let cleanT = fetcher.cleanTitle(currentState.title)
            mainText = isFetchingLyrics ? "Mencari lirik: \(cleanT)..." : cleanT
            let cleanA = fetcher.cleanArtist(currentState.artist)
            backingText = cleanA.isEmpty ? nil : cleanA
        }

        let liveVocalEnergy: CGFloat = (currentState.playing && autoVocalSyncEnabled && vocalSync.isTapActive)
            ? CGFloat(vocalSync.currentNormalizedEnergy())
            : (currentState.playing ? 0.35 : 0.0)
        let liveBackingEnergy: CGFloat = (currentState.playing && autoVocalSyncEnabled && vocalSync.isTapActive)
            ? CGFloat(vocalSync.currentNormalizedBackingEnergy())
            : liveVocalEnergy
        let liveVocalIntonation: CGFloat = (currentState.playing && autoVocalSyncEnabled && vocalSync.isTapActive)
            ? CGFloat(vocalSync.currentVocalIntonation())
            : 0.45
        let liveVocalOnset: CGFloat = (currentState.playing && autoVocalSyncEnabled && vocalSync.isTapActive)
            ? CGFloat(vocalSync.currentSyllableOnset())
            : 0.0

        let songPalette = artworkColorsEnabled ? artworkPalette : nil

        lyricsView.update(
            trackTitle: fetcher.cleanTitle(currentState.title),
            mainText: mainText,
            backingText: backingText,
            songProgress: songProg,
            lineProgress: lineProg,
            backingLineProgress: backProg,
            vocalEnergy: liveVocalEnergy,
            backingVocalEnergy: liveBackingEnergy,
            vocalIntonation: liveVocalIntonation,
            vocalOnset: liveVocalOnset,
            isPlaying: currentState.playing,
            isVocalSynced: autoVocalSyncEnabled && vocalSync.isTapActive,
            songPalette: songPalette
        )

        if displayMode.showsNotch {
            notchWindowController?.update(
                trackTitle: fetcher.cleanTitle(currentState.title),
                mainText: mainText,
                backingText: backingText,
                songProgress: songProg,
                lineProgress: lineProg,
                backingLineProgress: backProg,
                vocalEnergy: liveVocalEnergy,
                backingVocalEnergy: liveBackingEnergy,
                vocalIntonation: liveVocalIntonation,
                vocalOnset: liveVocalOnset,
                isPlaying: currentState.playing,
                isVocalSynced: autoVocalSyncEnabled && vocalSync.isTapActive,
                songPalette: songPalette,
                artist: fetcher.cleanArtist(currentState.artist),
                album: currentState.album,
                artworkData: currentState.artworkData.isEmpty ? nil : currentState.artworkData,
                elapsedTime: rawElapsed,
                duration: currentState.duration
            )
        }
    }

    // MARK: - Menu Bar

    func menuWillOpen(_ menu: NSMenu) {
        mainMenu.removeAllItems()

        let trackInfo = currentState.title.isEmpty
            ? "Tidak ada lagu aktif"
            : "\(fetcher.cleanTitle(currentState.title)) - \(fetcher.cleanArtist(currentState.artist))"
        let infoItem = NSMenuItem(title: trackInfo, action: nil, keyEquivalent: "")
        infoItem.isEnabled = false
        mainMenu.addItem(infoItem)

        let srcStr = lyricsSourceName.isEmpty ? "Sumber lirik: -" : "Sumber lirik: \(lyricsSourceName)"
        let srcItem = NSMenuItem(title: srcStr, action: nil, keyEquivalent: "")
        srcItem.isEnabled = false
        mainMenu.addItem(srcItem)

        let durMins = Int(currentState.duration) / 60
        let durSecs = Int(currentState.duration) % 60
        let bpmVal = Int(vocalSync.currentBPM().rounded())
        let tempoStr = String(
            format: "Tempo: %@ | Panjang: %02d:%02d | Word Speed: %.2fx",
            bpmVal >= 55 ? "\(bpmVal) BPM" : "Membaca BPM...",
            durMins, durSecs,
            ThemeStore.shared.activeTheme.wordSpeedScale
        )
        let tempoItem = NSMenuItem(title: tempoStr, action: nil, keyEquivalent: "")
        tempoItem.isEnabled = false
        mainMenu.addItem(tempoItem)

        let syncLabel = autoVocalSyncEnabled ? vocalSync.statusDescription : "Auto-Sync Vokal: Nonaktif"
        let syncInfo = NSMenuItem(title: syncLabel, action: nil, keyEquivalent: "")
        syncInfo.isEnabled = false
        mainMenu.addItem(syncInfo)

        mainMenu.addItem(NSMenuItem.separator())

        let showTitle = isModalPresented ? "Sembunyikan Touch Bar Lirik" : "Tampilkan Lirik di Touch Bar"
        let showItem = NSMenuItem(title: showTitle, action: #selector(toggleTouchBarModal), keyEquivalent: "t")
        showItem.target = self
        mainMenu.addItem(showItem)

        let displayMenu = NSMenu()
        for mode in DisplayMode.allCases {
            let item = NSMenuItem(title: mode.displayName, action: #selector(selectDisplayMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = displayMode == mode ? .on : .off
            displayMenu.addItem(item)
        }
        let displayParent = NSMenuItem(title: "Tampilkan Lirik di: \(displayMode.displayName)", action: nil, keyEquivalent: "")
        displayParent.submenu = displayMenu
        mainMenu.addItem(displayParent)

        let notchStyleMenu = NSMenu()
        for ns in ThemeNotchStyle.allCases {
            let item = NSMenuItem(title: ns.displayName, action: #selector(selectNotchStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ns.rawValue
            item.state = (ThemeStore.shared.activeTheme.notchStyle == ns) ? .on : .off
            notchStyleMenu.addItem(item)
        }
        let notchParent = NSMenuItem(title: "Gaya Notch: \(ThemeStore.shared.activeTheme.notchStyle.displayName)", action: nil, keyEquivalent: "")
        notchParent.submenu = notchStyleMenu
        mainMenu.addItem(notchParent)

        let autoItem = NSMenuItem(title: "Otomatis Muncul Saat Memutar", action: #selector(toggleAutoShow), keyEquivalent: "a")
        autoItem.target = self
        autoItem.state = autoShowEnabled ? .on : .off
        mainMenu.addItem(autoItem)

        let safariItem = NSMenuItem(title: "Sumber: Hanya Safari", action: #selector(toggleSafariOnly), keyEquivalent: "s")
        safariItem.target = self
        safariItem.state = safariOnlyEnabled ? .on : .off
        mainMenu.addItem(safariItem)

        let vocalItem = NSMenuItem(title: "Auto-Sync dari Audio Vokal", action: #selector(toggleAutoVocalSync), keyEquivalent: "v")
        vocalItem.target = self
        vocalItem.state = autoVocalSyncEnabled ? .on : .off
        mainMenu.addItem(vocalItem)

        let resetSyncItem = NSMenuItem(title: "Reset Offset Auto-Sync Vokal", action: #selector(resetAutoSyncOffset), keyEquivalent: "")
        resetSyncItem.target = self
        mainMenu.addItem(resetSyncItem)

        let refreshLyricsItem = NSMenuItem(title: "Cari Ulang Lirik Online (Lewati Cache)", action: #selector(forceRefreshLyrics), keyEquivalent: "r")
        refreshLyricsItem.target = self
        refreshLyricsItem.isEnabled = !currentState.title.isEmpty
        mainMenu.addItem(refreshLyricsItem)

        let nudgeAheadItem = NSMenuItem(title: "Majukan Timing Lirik (+0.25s)", action: #selector(nudgeLyricsAhead), keyEquivalent: "]")
        nudgeAheadItem.target = self
        mainMenu.addItem(nudgeAheadItem)

        let nudgeBackItem = NSMenuItem(title: "Mundurkan Timing Lirik (-0.25s)", action: #selector(nudgeLyricsBack), keyEquivalent: "[")
        nudgeBackItem.target = self
        mainMenu.addItem(nudgeBackItem)

        let romanizeItem = NSMenuItem(title: "Romanisasi Lirik (Romaji/Pinyin)", action: #selector(toggleRomanizeLyrics), keyEquivalent: "l")
        romanizeItem.target = self
        romanizeItem.state = romanizeEnabled ? .on : .off
        mainMenu.addItem(romanizeItem)

        let charAnimItem = NSMenuItem(title: "Animasi Per Huruf", action: #selector(toggleCharacterAnimation), keyEquivalent: "h")
        charAnimItem.target = self
        charAnimItem.state = characterAnimationEnabled ? .on : .off
        mainMenu.addItem(charAnimItem)

        let artworkColorItem = NSMenuItem(title: "Warna Mengikuti Artwork Lagu", action: #selector(toggleArtworkColors), keyEquivalent: "w")
        artworkColorItem.target = self
        artworkColorItem.state = artworkColorsEnabled ? .on : .off
        mainMenu.addItem(artworkColorItem)

        mainMenu.addItem(NSMenuItem.separator())

        // Quick Theme Switcher submenu
        let themeMenu = NSMenu()
        for t in ThemeStore.shared.themes {
            let item = NSMenuItem(title: t.name, action: #selector(selectQuickTheme(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = t.id
            item.state = (t.id == ThemeStore.shared.activeTheme.id) ? .on : .off
            themeMenu.addItem(item)
        }
        themeMenu.addItem(NSMenuItem.separator())
        let customizeItem = NSMenuItem(title: "Kustomisasi Tema, Tata Letak & Animasi...", action: #selector(openThemeEditor), keyEquivalent: ",")
        customizeItem.target = self
        themeMenu.addItem(customizeItem)

        let themeParent = NSMenuItem(title: "Tema: \(ThemeStore.shared.activeTheme.name)", action: nil, keyEquivalent: "")
        themeParent.submenu = themeMenu
        mainMenu.addItem(themeParent)

        mainMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Keluar TouchBarLyrics", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        mainMenu.addItem(quitItem)
    }

    @objc private func toggleAutoShow() {
        autoShowEnabled.toggle()
    }

    @objc private func toggleSafariOnly() {
        safariOnlyEnabled.toggle()
    }

    @objc private func toggleAutoVocalSync() {
        autoVocalSyncEnabled.toggle()
        if autoVocalSyncEnabled && currentState.playing {
            vocalSync.startIfNeeded()
        } else {
            vocalSync.stop()
            autoVocalOffset = 0
            autoBackingOffset = 0
        }
        refreshDisplay()
    }

    @objc private func toggleRomanizeLyrics() {
        romanizeEnabled.toggle()
        applyLyricsPreference()
        refreshDisplay()
    }

    @objc private func toggleCharacterAnimation() {
        characterAnimationEnabled.toggle()
        lyricsView.characterAnimationEnabled = characterAnimationEnabled
        notchWindowController?.setCharacterAnimationEnabled(characterAnimationEnabled)
        if currentState.playing {
            startRenderTimer()
        }
        refreshDisplay()
    }

    @objc private func toggleArtworkColors() {
        artworkColorsEnabled.toggle()
        if artworkColorsEnabled {
            artworkIdentity = ""
            updateArtworkPaletteIfNeeded(from: currentState, force: true)
        } else {
            resetArtworkPalette()
        }
        refreshDisplay()
    }

    @objc private func resetAutoSyncOffset() {
        vocalSync.resetOffsetManual()
        autoVocalOffset = 0
        autoBackingOffset = 0
        var t = ThemeStore.shared.activeTheme
        if t.karaokeOffsetSeconds != 0 {
            if t.isBuiltIn {
                t = ThemeStore.shared.duplicateTheme(t, newName: "\(t.name) Custom")
            }
            t.karaokeOffsetSeconds = 0
            ThemeStore.shared.upsertTheme(t, makeActive: true)
        }
        refreshDisplay()
    }

    @objc private func forceRefreshLyrics() {
        guard !currentState.title.isEmpty else { return }
        fetcher.clearCacheEntry(forKey: currentTrackKey, rawTitle: currentState.title, rawArtist: currentState.artist)
        isFetchingLyrics = true
        lyricsSourceName = "Mencari online..."
        refreshDisplay()
        loadLyrics(for: currentState, forceRefresh: true)
    }

    @objc private func nudgeLyricsAhead() {
        adjustUserKaraokeOffset(by: 0.25)
    }

    @objc private func nudgeLyricsBack() {
        adjustUserKaraokeOffset(by: -0.25)
    }

    private func adjustUserKaraokeOffset(by delta: TimeInterval) {
        var t = ThemeStore.shared.activeTheme
        if t.isBuiltIn {
            t = ThemeStore.shared.duplicateTheme(t, newName: "\(t.name) Custom")
        }
        t.karaokeOffsetSeconds = max(-2.0, min(2.0, t.karaokeOffsetSeconds + delta))
        ThemeStore.shared.upsertTheme(t, makeActive: true)
        refreshDisplay()
    }

    @objc private func selectQuickTheme(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        ThemeStore.shared.selectTheme(id: id)
    }

    @objc private func selectNotchStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let ns = ThemeNotchStyle(rawValue: raw) else { return }
        var t = ThemeStore.shared.activeTheme
        if t.isBuiltIn {
            t = ThemeStore.shared.duplicateTheme(t, newName: "\(t.name) Custom")
        }
        t.notchStyle = ns
        ThemeStore.shared.upsertTheme(t, makeActive: true)
    }

    @objc private func openThemeEditor() {
        if themeWindowController == nil {
            themeWindowController = ThemeEditorWindowController()
        }
        themeWindowController?.reloadFromStore()
        NSApp.activate(ignoringOtherApps: true)
        themeWindowController?.showWindow(nil)
        themeWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
