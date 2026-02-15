import AppKit
import Carbon.HIToolbox

/// Manages the global ⌥⌘G hotkey using Carbon API (no external dependency).
final class HotkeyManager {
    static let shared = HotkeyManager()

    private var hotkeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var callback: (() -> Void)?

    private init() {}

    // MARK: - Register

    func register(callback: @escaping () -> Void) {
        self.callback = callback

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handler: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let userData = userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.callback?()
            return noErr
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            selfPtr,
            &eventHandler
        )

        // ⌥⌘G = keyCode 5 (G), modifiers: optionKey + cmdKey
        let hotkeyID = EventHotKeyID(signature: OSType(0x4743_4C50), id: 1) // "GCLP"
        let modifiers = UInt32(optionKey | cmdKey)

        RegisterEventHotKey(
            UInt32(kVK_ANSI_G),
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
    }

    // MARK: - Unregister

    func unregister() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
        callback = nil
    }

    deinit {
        unregister()
    }
}
