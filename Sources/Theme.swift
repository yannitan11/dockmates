import AppKit

extension NSColor {
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

enum Theme {
    // Surfaces & text
    static let paper = NSColor(hex: 0xFFF9F0)
    static let ink = NSColor(hex: 0x26221C)
    static let inkSoft = NSColor(hex: 0x8A8074)
    static let hairline = NSColor(hex: 0x26221C).withAlphaComponent(0.08)

    // The one accent
    static let accent = NSColor(hex: 0xFF6B2C)

    // Character palette
    static let skinWarm = NSColor(hex: 0xF3C9A6)
    static let skinTan = NSColor(hex: 0xC98D5E)
    static let offBlack = NSColor(hex: 0x2E2A26)
    static let cream = NSColor(hex: 0xF5F1E8)
    static let sage = NSColor(hex: 0x9DBE8D)
    static let lilac = NSColor(hex: 0xC9B8F0)
    static let mustard = NSColor(hex: 0xF2C14E)
    static let sky = NSColor(hex: 0xBFD8F5)
    static let blush = NSColor(hex: 0xF09A8B)

    // Dressing-room palettes
    static let skinTones: [UInt32] = [
        0xF5D9C0, 0xF3C9A6, 0xC98D5E, 0x8D5A3B, 0x5C3A22,
    ]
    static let hairShades: [UInt32] = [
        0x2E2A26, 0x5C4330, 0x9C6B3C, 0xE8C97A, 0xB8552F, 0xC9C2B8, 0xC9B8F0,
    ]
    static let clothing: [UInt32] = [
        0xFF6B2C, 0xF2C14E, 0x9DBE8D, 0x4E6E52, 0xBFD8F5,
        0x3B5BDB, 0xC9B8F0, 0xF09A8B, 0xF5F1E8, 0x2E2A26,
    ]
    // Pet fur tones: white, cream, ginger, tan, grey, brown, near-black.
    static let furTones: [UInt32] = [
        0xF5F1E8, 0xE8D9C0, 0xE7A867, 0xC99A63, 0xA9A29B, 0x8D6E5C, 0x3A332C,
    ]

    static func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let descriptor = base.fontDescriptor.withDesign(.rounded),
           let font = NSFont(descriptor: descriptor, size: size) {
            return font
        }
        return base
    }
}
