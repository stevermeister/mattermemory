import AppKit
import Carbon.HIToolbox

/// Keyboard shortcuts are defined in Latin letters, but `charactersIgnoringModifiers`
/// reports what the *current* layout produces: on a Russian layout ⌘K arrives as
/// "л". AppKit remaps menu key equivalents for us; our own event monitors have to
/// do it themselves, by translating the key code through the ASCII-capable layout.
enum KeyLayout {
    private static var cached: Data?
    private static var observing = false

    /// The Latin character printed on the key that produced `event`, lowercased.
    static func latinCharacter(for event: NSEvent) -> String {
        if let s = event.charactersIgnoringModifiers?.lowercased(), let u = s.unicodeScalars.first,
           u.isASCII, u.value > 32 { return s }
        return character(forKeyCode: event.keyCode) ?? event.charactersIgnoringModifiers?.lowercased() ?? ""
    }

    static func character(forKeyCode keyCode: UInt16) -> String? {
        guard let data = layoutData() else { return nil }
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status: OSStatus = data.withUnsafeBytes { raw in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return OSStatus(paramErr) }
            return UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState,
                                  chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length).lowercased()
    }

    private static func layoutData() -> Data? {
        startObserving()
        if let cached { return cached }
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        cached = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        return cached
    }

    private static func startObserving() {
        guard !observing else { return }
        observing = true
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main) { _ in cached = nil }
    }
}

extension NSEvent {
    /// Layout-independent character for shortcut matching ("k" for ⌘K on any layout).
    var shortcutCharacter: String { KeyLayout.latinCharacter(for: self) }
}
