// MCCS (DDC/CI) setting codes and named values.

enum VCP {
    static let input: UInt8 = 0x60

    static let aliases: [String: UInt8] = [
        "brightness": 0x10, "contrast": 0x12, "preset": 0x14, "red": 0x16, "green": 0x18, "blue": 0x1A,
        "input": 0x60, "volume": 0x62, "sharpness": 0x87, "mute": 0x8D, "power": 0xD6,
    ]

    // Ordered: the first name for a value is the one shown.
    private static let values: [UInt8: [(name: String, value: UInt16)]] = [
        0x60: [
            ("vga1", 0x01), ("vga2", 0x02), ("dvi1", 0x03), ("dvi2", 0x04), ("composite1", 0x05),
            ("composite2", 0x06), ("svideo1", 0x07), ("svideo2", 0x08), ("tuner1", 0x09), ("tuner2", 0x0A),
            ("tuner3", 0x0B), ("component1", 0x0C), ("component2", 0x0D), ("component3", 0x0E),
            ("dp1", 0x0F), ("dp2", 0x10), ("hdmi1", 0x11), ("hdmi2", 0x12), ("hdmi3", 0x13), ("usbc", 0x1B),
            ("dp", 0x0F), ("hdmi", 0x11),
        ],
        0x14: [
            ("srgb", 0x01), ("native", 0x02), ("4000k", 0x03), ("5000k", 0x04), ("6500k", 0x05),
            ("7500k", 0x06), ("8200k", 0x07), ("9300k", 0x08), ("10000k", 0x09), ("11500k", 0x0A),
            ("user1", 0x0B), ("user2", 0x0C), ("user3", 0x0D),
        ],
        0xD6: [("on", 0x01), ("standby", 0x02), ("suspend", 0x03), ("off", 0x04), ("off-button", 0x05)],
        0x8D: [("mute", 0x01), ("unmute", 0x02)],
    ]

    /// A setting alias ("brightness") or a code ("0x10", "16").
    static func code(_ s: String) -> UInt8? {
        if let c = aliases[s.lowercased()] { return c }
        return parseNumber(s).flatMap { UInt8(exactly: $0) }
    }

    /// A value name ("hdmi2") or a number.
    static func value(_ s: String, for code: UInt8) -> UInt16? {
        if let v = values[code]?.first(where: { $0.name == s.lowercased() }) { return v.value }
        return parseNumber(s).flatMap { UInt16(exactly: $0) }
    }

    static func name(of value: UInt16, for code: UInt8) -> String? {
        values[code]?.first { $0.value == value }?.name
    }

    /// "hdmi2" -> "HDMI 2", "dp1" -> "DP 1".
    static func inputLabel(_ value: UInt16) -> String {
        guard let name = name(of: value, for: input) else { return String(format: "0x%02X", value) }
        let letters = name.prefix { $0.isLetter }.uppercased()
        let digits = name.drop { $0.isLetter }
        return digits.isEmpty ? letters : "\(letters) \(digits)"
    }

    private static func parseNumber(_ s: String) -> Int? {
        let lower = s.lowercased()
        return lower.hasPrefix("0x") ? Int(lower.dropFirst(2), radix: 16) : Int(lower)
    }
}
