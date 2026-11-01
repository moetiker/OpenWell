import AppKit
import ApplicationServices
import os

/// Messages are public: NSLog text shows as `<private>` in `log show`, which hid every
/// placement during the first local test.
enum Log {
    private static let logger = Logger(subsystem: "ch.oetiker.OpenWell", category: "placement")

    static func info(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }
}

extension AXUIElement {
    func attribute(_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success ? value : nil
    }

    func element(_ name: String) -> AXUIElement? {
        guard let value = attribute(name), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    func elements(_ name: String) -> [AXUIElement] {
        attribute(name) as? [AXUIElement] ?? []
    }

    func string(_ name: String) -> String? { attribute(name) as? String }
    func number(_ name: String) -> Int? { (attribute(name) as? NSNumber)?.intValue }
    func bool(_ name: String) -> Bool? { (attribute(name) as? NSNumber)?.boolValue }

    var role: String? { string(kAXRoleAttribute) }
    var subrole: String? { string(kAXSubroleAttribute) }
    var windowID: CGWindowID? { PrivateAPI.windowID(of: self) }

    var position: CGPoint? {
        get {
            var point = CGPoint.zero
            guard let value = attribute(kAXPositionAttribute), CFGetTypeID(value) == AXValueGetTypeID(),
                AXValueGetValue((value as! AXValue), .cgPoint, &point) else { return nil }
            return point
        }
        set {
            guard var point = newValue, let value = AXValueCreate(.cgPoint, &point) else { return }
            AXUIElementSetAttributeValue(self, kAXPositionAttribute as CFString, value)
        }
    }

    var size: CGSize? {
        get {
            var size = CGSize.zero
            guard let value = attribute(kAXSizeAttribute), CFGetTypeID(value) == AXValueGetTypeID(),
                AXValueGetValue((value as! AXValue), .cgSize, &size) else { return nil }
            return size
        }
        set {
            guard var size = newValue, let value = AXValueCreate(.cgSize, &size) else { return }
            AXUIElementSetAttributeValue(self, kAXSizeAttribute as CFString, value)
        }
    }

    /// In accessibility coordinates: from the top left of the main screen, y down.
    var frame: CGRect? {
        guard let position, let size else { return nil }
        return CGRect(origin: position, size: size)
    }

    var isStandardWindow: Bool {
        role == kAXWindowRole && subrole == kAXStandardWindowSubrole
    }

    var isFullScreen: Bool { bool("AXFullScreen") ?? false }

    @discardableResult
    func press() -> Bool {
        AXUIElementPerformAction(self, kAXPressAction as CFString) == .success
    }
}

enum AXTrust {
    static func isTrusted(prompt: Bool = false) -> Bool {
        // the value of kAXTrustedCheckOptionPrompt, a C global that Swift 6 refuses to read
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": prompt] as CFDictionary)
    }

    static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
}

/// Undocumented system calls, looked up at run time so that a macOS version without
/// one leaves it nil instead of failing to start.
enum PrivateAPI {
    private typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    // ApplicationServices is loaded already, RTLD_DEFAULT finds it
    private static let getWindow: GetWindow? = {
        guard let pointer = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else {
            return nil
        }
        return unsafeBitCast(pointer, to: GetWindow.self)
    }()

    static func windowID(of element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return getWindow?(element, &id) == .success ? id : nil
    }
}
