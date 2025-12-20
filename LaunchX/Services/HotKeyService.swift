import Carbon
import Cocoa
import Combine

// C-convention callback function for the event handler
private func globalHotKeyHandler(
    nextHandler: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?
) -> OSStatus {
    return HotKeyService.shared.handleEvent(event)
}

class HotKeyService: ObservableObject {
    static let shared = HotKeyService()

    // Callback to be executed when hotkey is pressed
    var onHotKeyPressed: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private let hotKeySignature: OSType
    private let hotKeyId: UInt32 = 1
    private var eventHandlerRef: EventHandlerRef?

    // Published properties to allow UI binding/observation
    @Published var currentKeyCode: UInt32 = UInt32(kVK_Space)
    @Published var currentModifiers: UInt32 = UInt32(optionKey)
    @Published var isEnabled: Bool = true

    private init() {
        // Create signature "LnHX"
        let c1 = UInt32(byteAt("L", 0))
        let c2 = UInt32(byteAt("n", 0))
        let c3 = UInt32(byteAt("H", 0))
        let c4 = UInt32(byteAt("X", 0))

        self.hotKeySignature = OSType((c1 << 24) | (c2 << 16) | (c3 << 8) | c4)
    }

    func setupGlobalHotKey() {
        // Install event handler only once
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            globalHotKeyHandler,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        if status != noErr {
            print("HotKeyService: Failed to install event handler. Status: \(status)")
            return
        }

        // Load saved key or use default (Option + Space)
        let savedKeyCode = UserDefaults.standard.object(forKey: "hotKeyKeyCode") as? Int
        let savedModifiers = UserDefaults.standard.object(forKey: "hotKeyModifiers") as? Int

        if let key = savedKeyCode, let mods = savedModifiers {
            registerHotKey(keyCode: UInt32(key), modifiers: UInt32(mods))
        } else {
            registerHotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))
        }
    }

    func registerHotKey(keyCode: UInt32, modifiers: UInt32) {
        // Unregister existing if any
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        self.currentKeyCode = keyCode
        self.currentModifiers = modifiers

        // Save persistence
        UserDefaults.standard.set(Int(keyCode), forKey: "hotKeyKeyCode")
        UserDefaults.standard.set(Int(modifiers), forKey: "hotKeyModifiers")

        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: hotKeyId)

        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registerStatus != noErr {
            print("HotKeyService: Failed to register hotkey. Status: \(registerStatus)")
        } else {
            print("HotKeyService: Registered Global HotKey (Code: \(keyCode), Mods: \(modifiers))")
        }
    }

    // Internal handler called by the C function
    fileprivate func handleEvent(_ event: EventRef?) -> OSStatus {
        guard let event = event else { return OSStatus(eventNotHandledErr) }

        var hotKeyID = EventHotKeyID()
        let error = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        if error == noErr {
            // Verify signature and ID to ensure it's our hotkey
            if hotKeyID.signature == hotKeySignature && hotKeyID.id == hotKeyId {
                DispatchQueue.main.async { [weak self] in
                    self?.onHotKeyPressed?()
                }
                return noErr
            }
        }

        return OSStatus(eventNotHandledErr)
    }

    deinit {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef = eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }
}

// MARK: - Helpers

private func byteAt(_ string: String, _ index: Int) -> UInt8 {
    let array = Array(string.utf8)
    guard index < array.count else { return 0 }
    return array[index]
}

extension HotKeyService {
    // Helper to convert NSEvent.ModifierFlags to Carbon modifiers
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbonFlags: UInt32 = 0
        if flags.contains(.command) { carbonFlags |= UInt32(cmdKey) }
        if flags.contains(.option) { carbonFlags |= UInt32(optionKey) }
        if flags.contains(.control) { carbonFlags |= UInt32(controlKey) }
        if flags.contains(.shift) { carbonFlags |= UInt32(shiftKey) }
        return carbonFlags
    }

    // Helper to convert Carbon modifiers to string for display
    static func displayString(for modifiers: UInt32, keyCode: UInt32) -> String {
        var string = ""
        if modifiers & UInt32(controlKey) != 0 { string += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { string += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { string += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { string += "⌘" }

        string += keyString(for: keyCode)
        return string
    }

    private static func keyString(for keyCode: UInt32) -> String {
        // TISInputSource would be more accurate for localized keyboards,
        // but this manual mapping covers standard US ANSI layout.
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "Esc"

        // ANSI Letters
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"

        // ANSI Numbers
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"

        // Common Symbols
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Grave: return "`"

        // Function Keys
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"

        default: return "?"
        }
    }
}
