// Parsing of MCCS capabilities strings, e.g.
// (prot(monitor)type(LCD)model(M27Q)vcp(02 10 12 60(0F 11 12) 62 D6(01 04))mccs_ver(2.2))

enum Capabilities {
    /// The contents of `key(...)` at the top level, e.g. section("model") -> "M27Q".
    static func section(_ key: String, in caps: String) -> String? {
        let chars = Array(caps.lowercased())
        let original = Array(caps)
        let key = Array(key.lowercased())
        var depth = 0
        var i = 0
        while i < chars.count {
            switch chars[i] {
            case "(": depth += 1
            case ")": depth -= 1
            default:
                let end = i + key.count
                if depth == 1, end < chars.count, Array(chars[i..<end]) == key, chars[end] == "(",
                   i == 0 || !chars[i - 1].isLetter {
                    guard let close = matchingParen(original, from: end) else { return nil }
                    return String(original[(end + 1)..<close])
                }
            }
            i += 1
        }
        return nil
    }

    /// The values listed for a VCP code, e.g. 60(0F 11 12) -> [0x0F, 0x11, 0x12].
    static func values(of code: UInt8, in caps: String) -> [UInt16]? {
        guard let vcp = section("vcp", in: caps) else { return nil }
        let chars = Array(vcp)
        var i = 0
        while i < chars.count {
            guard let (token, next) = hexToken(chars, from: i) else { i += 1; continue }
            i = next
            guard i < chars.count, chars[i] == "(", let close = matchingParen(chars, from: i) else { continue }
            if token == Int(code) {
                var values: [UInt16] = []
                var j = i + 1
                while j < close {
                    if let (v, n) = hexToken(chars, from: j) { values.append(UInt16(v)); j = n } else { j += 1 }
                }
                return values
            }
            i = close + 1
        }
        return nil
    }

    /// A run of hex digits starting at `i`, and the index after it.
    private static func hexToken(_ chars: [Character], from i: Int) -> (Int, Int)? {
        var j = i
        while j < chars.count, chars[j].isHexDigit { j += 1 }
        guard j > i, let v = Int(String(chars[i..<j]), radix: 16) else { return nil }
        return (v, j)
    }

    private static func matchingParen(_ chars: [Character], from open: Int) -> Int? {
        var depth = 0
        for k in open..<chars.count {
            if chars[k] == "(" { depth += 1 }
            if chars[k] == ")" { depth -= 1; if depth == 0 { return k } }
        }
        return nil
    }
}
