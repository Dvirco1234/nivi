import Foundation

public enum ModifierKey: String, Codable, CaseIterable {
    case rightCommand, leftCommand, rightOption, rightControl

    public var keyCode: UInt16 {
        switch self {
        case .rightCommand: return 54
        case .leftCommand: return 55
        case .rightOption: return 61
        case .rightControl: return 62
        }
    }

    public var symbol: String {
        switch self {
        case .rightCommand, .leftCommand: return "⌘"
        case .rightOption: return "⌥"
        case .rightControl: return "⌃"
        }
    }

    public var side: String {
        switch self {
        case .rightCommand, .rightOption, .rightControl: return "right"
        case .leftCommand: return "left"
        }
    }
}

public enum HotkeyBinding: Equatable, Codable {
    case modifierTap(ModifierKey, count: Int)
    case keyCombo(keyCode: UInt16, modifiers: UInt)

    public static let defaultDictate = HotkeyBinding.modifierTap(.rightCommand, count: 2)
    public static let defaultCancel = HotkeyBinding.keyCombo(keyCode: 53, modifiers: 0)

    public var displayString: String {
        switch self {
        case .modifierTap(let key, let count):
            return String(repeating: key.symbol, count: count) + " (\(key.side))"
        case .keyCombo(let keyCode, let modifiers):
            return Self.comboDisplay(keyCode: keyCode, modifiers: modifiers)
        }
    }

    public func encodedJSON() -> String {
        (try? String(data: JSONEncoder().encode(self), encoding: .utf8) ?? "") ?? ""
    }

    public static func from(json: String) -> HotkeyBinding? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(HotkeyBinding.self, from: data)
    }

    private static func comboDisplay(keyCode: UInt16, modifiers: UInt) -> String {
        var out = ""
        // NSEvent.ModifierFlags raw bits: control 0x40000, option 0x80000, shift 0x20000, command 0x100000
        if modifiers & 0x40000 != 0 { out += "⌃" }
        if modifiers & 0x80000 != 0 { out += "⌥" }
        if modifiers & 0x20000 != 0 { out += "⇧" }
        if modifiers & 0x100000 != 0 { out += "⌘" }
        out += keyName(keyCode)
        return out
    }

    private static func keyName(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 53: return "esc"
        case 49: return "space"
        case 36: return "return"
        default: return "key\(keyCode)"
        }
    }
}
