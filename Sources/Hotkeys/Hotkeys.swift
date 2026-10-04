import Carbon.HIToolbox
import MacroCore

/// System-wide shortcuts via Carbon hot keys: they are consumed (not leaked to the front app)
/// and need no extra permission. Callbacks arrive on the main thread.
public final class HotkeyCenter {
    public static let shared = HotkeyCenter()

    private struct Entry {
        var ref: EventHotKeyRef
        var onPress: () -> Void
        var onRelease: (() -> Void)?
    }

    private var entries: [UInt32: Entry] = [:]
    private var ids: [String: UInt32] = [:]
    private var nextID: UInt32 = 1
    private var handler: EventHandlerRef?
    private static let signature: OSType = 0x6D72_6563 // 'mrec'

    private init() {}

    /// Registers `combo` under `name`, replacing any previous registration with that name.
    /// Returns false if the system refused (e.g. the shortcut is taken or not allowed).
    @discardableResult
    public func register(_ combo: KeyCombo, name: String, onPress: @escaping () -> Void,
                         onRelease: (() -> Void)? = nil) -> Bool {
        installHandlerIfNeeded()
        unregister(name: name)
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(combo.keyCode), Self.carbonModifiers(combo.modifiers),
                                         EventHotKeyID(signature: Self.signature, id: id),
                                         GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        entries[id] = Entry(ref: ref, onPress: onPress, onRelease: onRelease)
        ids[name] = id
        return true
    }

    public func unregister(name: String) {
        guard let id = ids.removeValue(forKey: name), let entry = entries.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(entry.ref)
    }

    public func unregisterAll(prefix: String = "") {
        for name in ids.keys where name.hasPrefix(prefix) { unregister(name: name) }
    }

    static func carbonModifiers(_ flags: UInt64) -> UInt32 {
        let m = ModifierFlags(rawValue: flags)
        var result: UInt32 = 0
        if m.contains(.command) { result |= UInt32(cmdKey) }
        if m.contains(.shift) { result |= UInt32(shiftKey) }
        if m.contains(.option) { result |= UInt32(optionKey) }
        if m.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetEventDispatcherTarget(), hotkeyEventHandler, types.count, &types,
                            Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    fileprivate func dispatch(id: UInt32, pressed: Bool) {
        guard let entry = entries[id] else { return }
        if pressed { entry.onPress() } else { entry.onRelease?() }
    }
}

private func hotkeyEventHandler(_: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                   nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard status == noErr else { return status }
    let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
    center.dispatch(id: hotKeyID.id, pressed: GetEventKind(event) == UInt32(kEventHotKeyPressed))
    return noErr
}
