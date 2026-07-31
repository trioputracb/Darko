import AppKit
import Carbon.HIToolbox
import Foundation

private let hotkeySignature: OSType = 0x4441524B // 'DARK'
private let noShortcutKeyCode = -1

/// Registers and records the global dark-mode toggle shortcut.
///
/// The registered hotkey uses the Carbon `RegisterEventHotKey` API, which works
/// system-wide without accessibility permission. Recording captures the next
/// key combination through local + global event monitors.
@MainActor
final class HotkeyManager {

    static let shared = HotkeyManager()

    private(set) var shortcutText = "None"
    private(set) var hasShortcut = false
    private(set) var isRecording = false
    private(set) var needsModifierHint = false

    private let defaults = UserDefaults.standard
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var localMonitor: Any?
    private var globalMonitor: Any?

    private enum Key {
        static let keyCode = "shortcutKeyCode"
        static let modifiers = "shortcutModifiers"
    }

    private init() {
        let code = self.keyCode
        let mods = self.modifiers
        hasShortcut = code != noShortcutKeyCode
        shortcutText = hasShortcut
            ? Self.modifierString(UInt32(mods)) + Self.keyString(for: UInt32(code))
            : "None"
    }

    var keyCode: Int {
        get { defaults.object(forKey: Key.keyCode) as? Int ?? noShortcutKeyCode }
        set { defaults.set(newValue, forKey: Key.keyCode) }
    }

    var modifiers: Int {
        get { defaults.object(forKey: Key.modifiers) as? Int ?? 0 }
        set { defaults.set(newValue, forKey: Key.modifiers) }
    }

    // MARK: - Lifecycle

    func start() {
        installEventHandler()
        if hasShortcut {
            _ = register()
        }
    }

    func stop() {
        unregister()
        stopRecording()
    }

    // MARK: - Registration

    @discardableResult
    func register() -> Bool {
        unregister()
        let code = keyCode
        let mods = modifiers
        guard code != noShortcutKeyCode else { return true }

        let hotKeyID = EventHotKeyID(signature: hotkeySignature, id: 1)
        let status = RegisterEventHotKey(
            UInt32(code),
            UInt32(mods),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        return status == noErr
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    // MARK: - Shortcut editing

    func save(keyCode: Int, modifiers: Int) {
        self.keyCode = keyCode
        self.modifiers = modifiers

        if keyCode == noShortcutKeyCode {
            unregister()
            shortcutText = "None"
            hasShortcut = false
        } else {
            _ = register()
            shortcutText = Self.modifierString(UInt32(modifiers)) + Self.keyString(for: UInt32(keyCode))
            hasShortcut = true
        }
        NotificationCenter.default.post(name: .darkoShortcutChanged, object: nil)
    }

    func clearShortcut() {
        save(keyCode: noShortcutKeyCode, modifiers: 0)
    }

    // MARK: - Recording

    func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        needsModifierHint = false
        unregister()
        NSApp.activate(ignoringOtherApps: true)
        installMonitors()
        NotificationCenter.default.post(name: .darkoShortcutChanged, object: nil)
    }

    func cancelRecording() {
        stopRecording()
        isRecording = false
        needsModifierHint = false
        if hasShortcut {
            _ = register()
        }
        NotificationCenter.default.post(name: .darkoShortcutChanged, object: nil)
    }

    private func stopRecording() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    private func installMonitors() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags
            Task { @MainActor in
                HotkeyManager.shared.handleRecordingEvent(keyCode: keyCode, flags: flags)
            }
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags
            Task { @MainActor in
                HotkeyManager.shared.handleRecordingEvent(keyCode: keyCode, flags: flags)
            }
        }
    }

    private func handleRecordingEvent(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        guard isRecording else { return }

        if keyCode == UInt16(kVK_Escape) {
            cancelRecording()
            return
        }

        guard let captured = carbonValues(keyCode: keyCode, flags: flags) else {
            needsModifierHint = true
            return
        }

        stopRecording()
        isRecording = false
        needsModifierHint = false
        save(keyCode: Int(captured.keyCode), modifiers: Int(captured.modifiers))
    }

    private func carbonValues(keyCode: UInt16,
                              flags: NSEvent.ModifierFlags) -> (keyCode: UInt32, modifiers: UInt32)? {
        let present = flags.intersection([.control, .option, .shift, .command])
        guard !present.isEmpty else { return nil }

        var mask: UInt32 = 0
        if present.contains(.control) { mask |= UInt32(controlKey) }
        if present.contains(.option) { mask |= UInt32(optionKey) }
        if present.contains(.shift) { mask |= UInt32(shiftKey) }
        if present.contains(.command) { mask |= UInt32(cmdKey) }
        return (UInt32(keyCode), mask)
    }

    // MARK: - Hotkey event

    private func installEventHandler() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
        assert(status == noErr, "InstallEventHandler failed: \(status)")
    }

    /// Called by the Carbon callback. The callback fires on the main thread,
    /// so hopping to the main actor is safe.
    nonisolated static func handleHotKeyPressed() {
        Task { @MainActor in
            AppearanceController.shared.toggleFromHotkey()
        }
    }

    // MARK: - Display helpers

    static func modifierString(_ mask: UInt32) -> String {
        var parts: [String] = []
        if mask & UInt32(controlKey) != 0 { parts.append("⌃") }
        if mask & UInt32(optionKey) != 0 { parts.append("⌥") }
        if mask & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if mask & UInt32(cmdKey) != 0 { parts.append("⌘") }
        return parts.joined()
    }

    static func keyString(for keyCode: UInt32) -> String {
        if let special = specialKeyNames[UInt16(keyCode)] {
            return special
        }
        return translatedKeyString(keyCode: keyCode)
    }

    private static func translatedKeyString(keyCode: UInt32) -> String {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue() else {
            return "key\(keyCode)"
        }
        guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "key\(keyCode)"
        }

        let data = unsafeBitCast(layoutData, to: CFData.self) as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)

        let status = data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> OSStatus in
            guard let base = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return noErr }
            return UCKeyTranslate(
                base,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
        }

        guard status == noErr, length > 0 else { return "key\(keyCode)" }
        return String(utf16CodeUnits: &chars, count: length).uppercased()
    }

    private static let specialKeyNames: [UInt16: String] = [
        UInt16(kVK_Space): "Space",
        UInt16(kVK_Return): "Return",
        UInt16(kVK_Tab): "Tab",
        UInt16(kVK_Delete): "Delete",
        UInt16(kVK_ForwardDelete): "Del",
        UInt16(kVK_Escape): "Esc",
        UInt16(kVK_UpArrow): "↑",
        UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_LeftArrow): "←",
        UInt16(kVK_RightArrow): "→",
        UInt16(kVK_Home): "Home",
        UInt16(kVK_End): "End",
        UInt16(kVK_PageUp): "PgUp",
        UInt16(kVK_PageDown): "PgDn",
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2",
        UInt16(kVK_F3): "F3", UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6",
        UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9", UInt16(kVK_F10): "F10",
        UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12"
    ]
}

private let hotKeyEventHandler: EventHandlerUPP = { _, _, _ in
    HotkeyManager.handleHotKeyPressed()
    return noErr
}
