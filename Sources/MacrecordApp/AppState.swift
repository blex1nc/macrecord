import AppKit
import Capture
import Hotkeys
import MacroCore
import Observation
import Permissions
import Playback
import Scripting
import UniformTypeIdentifiers

enum SidebarItem: Hashable {
    case autoclicker
    case macro(UUID)
}

enum Activity: Equatable {
    case idle, recording, playing(id: UUID, name: String), clicking
    var isIdle: Bool { self == .idle }
}

@Observable
final class AppState {
    var macros: [Macro] = []
    var selection: SidebarItem? = .autoclicker
    private(set) var activity: Activity = .idle
    /// Events recorded or clicks performed so far in the current activity.
    private(set) var liveCount = 0
    var message: String?
    var scriptLog: [String] = []
    var permissionsGranted = Permissions.allGranted
    var settings = AppSettings.load() {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            if settings.hotkeys != oldValue.hotkeys { registerHotkeys() }
        }
    }

    private let store = MacroStore(directory: MacroStore.defaultDirectory)
    private let recorder = EventRecorder()
    private let player = MacroPlayer()
    private let clicker = AutoClicker()
    private let scriptRunner = ScriptRunner()
    private let watcher = InputWatcher()
    private let sampler = ScreenPixelSampler()
    private var ticker: Timer?
    private var undoStacks: [UUID: [[MacroEvent]]] = [:]

    init() {
        player.pixelSampler = sampler
        scriptRunner.pixelSampler = sampler
        player.onFinish = { [weak self] _ in DispatchQueue.main.async { self?.activityEnded() } }
        clicker.onFinish = { [weak self] in DispatchQueue.main.async { self?.activityEnded() } }
        scriptRunner.onFinish = { [weak self] error in
            DispatchQueue.main.async {
                if let error { self?.scriptLog.append("⚠︎ \(error)") }
                self?.activityEnded()
            }
        }
        scriptRunner.onLog = { [weak self] line in DispatchQueue.main.async { self?.scriptLog.append(line) } }
        scriptRunner.macroResolver = { [weak self] name in
            DispatchQueue.main.sync { self?.macros.first { $0.name == name && !$0.isScript } }
        }
        reload()
        if let first = macros.first { selection = .macro(first.id) }
        registerHotkeys()
    }

    var selectedMacro: Macro? {
        guard case let .macro(id) = selection else { return nil }
        return macros.first { $0.id == id }
    }

    func refreshPermissions() {
        permissionsGranted = Permissions.allGranted
    }

    // MARK: - Library

    func reload() {
        do { macros = try store.loadAll() } catch { message = error.localizedDescription }
    }

    func update(_ macro: Macro) {
        guard let index = macros.firstIndex(where: { $0.id == macro.id }) else { return }
        let hotkeyChanged = macros[index].hotkey != macro.hotkey
        macros[index] = macro
        persist(macro)
        if hotkeyChanged { registerHotkeys() }
    }

    func delete(_ id: UUID) {
        try? store.delete(id: id)
        macros.removeAll { $0.id == id }
        undoStacks[id] = nil
        if selection == .macro(id) { selection = .autoclicker }
        registerHotkeys()
    }

    func duplicate(_ id: UUID) {
        guard var copy = macros.first(where: { $0.id == id }) else { return }
        copy.id = UUID()
        copy.name += " copy"
        copy.createdAt = Date()
        copy.hotkey = nil
        add(copy)
    }

    func newScript() {
        add(Macro(name: "Script \(macros.filter(\.isScript).count + 1)", script: Self.scriptTemplate))
    }

    private func add(_ macro: Macro) {
        macros.insert(macro, at: 0)
        persist(macro)
        selection = .macro(macro.id)
    }

    private func persist(_ macro: Macro) {
        do { try store.save(macro) } catch { message = error.localizedDescription }
    }

    func importMacros() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: MacroStore.fileExtension) ?? .json, .json]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            do {
                let macro = try store.importMacro(from: url)
                macros.insert(macro, at: 0)
                selection = .macro(macro.id)
            } catch {
                message = "\(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
        registerHotkeys()
    }

    func export(_ id: UUID) {
        guard let macro = macros.first(where: { $0.id == id }) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(macro.name).\(MacroStore.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.export(macro, to: url) } catch { message = error.localizedDescription }
    }

    // MARK: - Editing with undo

    func edit(_ id: UUID, _ transform: ([MacroEvent]) -> [MacroEvent]) {
        guard var macro = macros.first(where: { $0.id == id }) else { return }
        let edited = transform(macro.events)
        guard edited != macro.events else { return }
        undoStacks[id, default: []].append(macro.events)
        if undoStacks[id]!.count > 50 { undoStacks[id]!.removeFirst() }
        macro.events = edited
        update(macro)
    }

    func canUndo(_ id: UUID) -> Bool { !(undoStacks[id]?.isEmpty ?? true) }

    func undo(_ id: UUID) {
        guard var macro = macros.first(where: { $0.id == id }), let previous = undoStacks[id]?.popLast() else { return }
        macro.events = previous
        update(macro)
    }

    // MARK: - Recording

    func toggleRecording(viaHotkey: Bool = false) {
        switch activity {
        case .recording: stopRecording(stopKeyCode: viaHotkey ? settings.recordHotkey.keyCode : nil)
        case .idle: startRecording()
        default: break
        }
    }

    func startRecording() {
        guard activity.isIdle else { return }
        refreshPermissions()
        guard permissionsGranted else { message = String(localized: "Grant the permissions first."); return }
        recorder.options.captureMouseMoves = settings.captureMouseMoves
        do {
            try recorder.start()
        } catch {
            message = String(localized: "Could not start recording. Check Input Monitoring permission.")
            return
        }
        if Permissions.secureInputActive {
            message = String(localized: "Secure input is active (a password field is focused); keystrokes may not be recorded.")
        }
        setActivity(.recording)
    }

    /// `stopKeyCode` is the key of the shortcut that ended recording, or nil when stopped from the UI
    /// (then the clicks that reached the Stop control are trimmed instead).
    func stopRecording(stopKeyCode: UInt16? = nil) {
        guard activity == .recording else { return }
        var events = RecordingSanitizer.sanitize(recorder.stop(), stopKeyCode: stopKeyCode)
        if stopKeyCode == nil {
            let ownUI = Self.ownUIRects()
            events = RecordingSanitizer.trimTrailingUIClicks(events) { x, y in
                ownUI.contains { $0.contains(CGPoint(x: x, y: y)) }
            }
        }
        setActivity(.idle)
        guard !events.isEmpty else { message = String(localized: "Nothing was recorded."); return }
        let count = macros.filter { !$0.isScript }.count + 1
        add(Macro(name: String(localized: "Recording \(count)"), events: events))
    }

    /// Frames of macrecord's visible windows (main window, settings, menu bar icon) in global display coordinates
    /// (top-left origin), matching recorded event positions.
    static func ownUIRects() -> [CGRect] {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return [] }
        return NSApp.windows.filter(\.isVisible).map { window in
            let f = window.frame
            return CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)
        }
    }

    // MARK: - Playback

    func playSelected() {
        if let macro = selectedMacro ?? macros.first { play(macro.id) }
    }

    func play(_ id: UUID) {
        guard activity.isIdle, let macro = macros.first(where: { $0.id == id }) else { return }
        refreshPermissions()
        guard Permissions.accessibilityGranted else { message = String(localized: "Grant the permissions first."); return }
        if let script = macro.script {
            scriptLog = []
            scriptRunner.run(script)
        } else {
            guard !macro.events.isEmpty else { return }
            player.play(macro)
        }
        setActivity(.playing(id: macro.id, name: macro.name))
        if settings.stopOnUserInput { watcher.start { [weak self] in self?.stopAll() } }
    }

    func togglePlay(_ id: UUID) {
        if case .playing = activity { stopAll() } else { play(id) }
    }

    // MARK: - Autoclicker

    func toggleAutoclick() {
        if activity == .clicking { stopAll() } else { startAutoclick() }
    }

    func startAutoclick() {
        guard activity.isIdle else { return }
        refreshPermissions()
        guard Permissions.accessibilityGranted else { message = String(localized: "Grant the permissions first."); return }
        clicker.start(settings.autoclick)
        setActivity(.clicking)
    }

    // MARK: - Stop

    func stopAll(viaHotkey: Bool = false) {
        switch activity {
        case .recording: stopRecording(stopKeyCode: viaHotkey ? settings.stopHotkey.keyCode : nil)
        case .playing:
            player.stop()
            scriptRunner.stop()
            watcher.stop()
        case .clicking: clicker.stop()
        case .idle: break
        }
    }

    private func activityEnded() {
        watcher.stop()
        if activity != .recording { setActivity(.idle) }
    }

    private func setActivity(_ new: Activity) {
        activity = new
        ticker?.invalidate()
        ticker = nil
        liveCount = 0
        guard new != .idle else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            switch activity {
            case .recording: liveCount = recorder.capturedCount
            case .clicking: liveCount = clicker.clickCount
            case .playing: liveCount = player.currentLoop + 1
            case .idle: break
            }
        }
    }

    // MARK: - Hotkeys

    func registerHotkeys() {
        let center = HotkeyCenter.shared
        center.unregisterAll()
        var failed: [String] = []
        func register(_ combo: KeyCombo, _ name: String, press: @escaping () -> Void, release: (() -> Void)? = nil) {
            if !center.register(combo, name: name, onPress: press, onRelease: release) {
                failed.append(KeyNames.describe(combo))
            }
        }
        register(settings.recordHotkey, "record") { [weak self] in self?.toggleRecording(viaHotkey: true) }
        register(settings.playHotkey, "play") { [weak self] in
            guard let self else { return }
            if case .playing = activity { stopAll(viaHotkey: true) } else { playSelected() }
        }
        register(settings.stopHotkey, "stop") { [weak self] in self?.stopAll(viaHotkey: true) }
        register(settings.autoclickHotkey, "autoclick", press: { [weak self] in
            guard let self else { return }
            if settings.autoclick.mode == .hold { startAutoclick() } else { toggleAutoclick() }
        }, release: { [weak self] in
            guard let self, settings.autoclick.mode == .hold, activity == .clicking else { return }
            stopAll()
        })
        for macro in macros {
            guard let combo = macro.hotkey else { continue }
            register(combo, "macro.\(macro.id)") { [weak self] in self?.togglePlay(macro.id) }
        }
        if !failed.isEmpty {
            message = String(localized: "These shortcuts are unavailable: \(failed.joined(separator: ", "))")
        }
    }

    static let scriptTemplate = """
    // macrecord script — runs locally with JavaScriptCore.
    // API: move(x,y) click(x,y,'left'|'right'|'middle',count) mouseDown() mouseUp() scroll(dx,dy)
    //      key('a','cmd+shift') keyDown(name) keyUp(name) type('text') sleep(ms)
    //      cursor() pixel(x,y) waitForPixel(x,y,0xRRGGBB,tolerance,timeoutMs)
    //      activate('com.apple.Safari') play('Recording 1') log(value) running()

    for (let i = 0; i < 3 && running(); i++) {
      const p = cursor()
      click(p.x, p.y)
      sleep(500)
    }
    """
}
