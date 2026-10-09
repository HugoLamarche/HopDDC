// DDC/CI control of external monitors on Apple Silicon through IOAVService.

import CIOAVService
import Foundation
import IOKit

struct Monitor {
    let name: String
    let serial: String
    private let service: IOAVService

    enum Read { case value(current: UInt16, max: UInt16), unsupported, failed }
    enum WriteResult { case confirmed, unconfirmed, rejected }

    private static let chip: UInt32 = 0x37
    private static let host: UInt32 = 0x51

    /// Wait between a DDC request and reading its reply. Slow monitors need more;
    /// override with DDC_DELAY_MS.
    private static let replyDelay: useconds_t = {
        let ms = ProcessInfo.processInfo.environment["DDC_DELAY_MS"].flatMap { UInt32($0) } ?? 50
        return ms * 1000
    }()

    // MARK: Discovery

    /// Walks the IOService plane in order: each framebuffer (carrying DisplayAttributes)
    /// is followed by the DCPAVServiceProxy that drives the same port.
    static func all() -> [Monitor] {
        var iterator: io_iterator_t = 0
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard IORegistryEntryCreateIterator(root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iterator) }

        var found: [Monitor] = []
        var pending: (name: String, serial: String)?
        while true {
            let entry = IOIteratorNext(iterator)
            if entry == 0 { break }
            defer { IOObjectRelease(entry) }

            switch className(entry) {
            case "AppleCLCD2", "IOMobileFramebufferShim":
                if let name = productAttribute(entry, "ProductName"), !name.isEmpty {
                    pending = (name, productAttribute(entry, "AlphanumericSerialNumber") ?? "")
                }
            case "DCPAVServiceProxy":
                guard property(entry, "Location") as? String == "External", let p = pending else { continue }
                if let av = IOAVServiceCreateWithService(kCFAllocatorDefault, entry) {
                    found.append(Monitor(name: p.name, serial: p.serial, service: av))
                }
                pending = nil
            default:
                break
            }
        }
        return found
    }

    /// The monitor named in Config, or the only external monitor if there is just one.
    static func configured() -> Monitor? {
        let all = all()
        return all.first { $0.name.localizedCaseInsensitiveContains(Config.monitorMatch) } ?? (all.count == 1 ? all[0] : nil)
    }

    // MARK: VCP

    /// Read-only "Get VCP Feature" request. Never changes monitor state.
    func read(_ code: UInt8, attempts: Int = 5) -> Read {
        for _ in 0..<attempts {
            guard write([0x82, 0x01, code]) else { continue }
            usleep(Self.replyDelay)
            var r = [UInt8](repeating: 0, count: 12)
            guard IOAVServiceReadI2C(service, Self.chip, Self.host, &r, UInt32(r.count)) == kIOReturnSuccess else { continue }
            // r: 6E 88 02 <result> <vcp> <type> <maxH> <maxL> <curH> <curL> <chk>
            let checksum = r[0..<10].reduce(UInt8(0x50), ^)
            guard r[2] == 0x02, r[4] == code, checksum == r[10] else { continue }
            if r[3] != 0 { return .unsupported }
            return .value(current: UInt16(r[8]) << 8 | UInt16(r[9]), max: UInt16(r[6]) << 8 | UInt16(r[7]))
        }
        return .failed
    }

    /// Single write, no read-back.
    func writeOnce(_ code: UInt8, _ value: UInt16) -> Bool {
        write([0x84, 0x03, code, UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    /// Some monitors silently drop writes. Read back after each write and resend only
    /// while the monitor clearly reports the old value. Switching can take ~1s and some
    /// monitors stop answering once they show another input, so silence means
    /// "probably switched".
    func set(_ code: UInt8, _ value: UInt16) -> WriteResult {
        let before = readNormalized(code, attempts: 2)
        if before == value { return .confirmed }
        for _ in 0..<4 {
            guard writeOnce(code, value) else { continue }
            usleep(1_500_000)
            guard let now = readNormalized(code, attempts: 2) else {
                if before != nil { return .unconfirmed }  // was answering, now silent: switched away
                continue                                  // silent before and after: resend
            }
            if now == value || (before != nil && now != before) { return .confirmed }
        }
        return before != nil ? .rejected : .unconfirmed
    }

    /// The active input as a standard MCCS code, or nil if unreadable or unknown.
    func currentInput() -> UInt16? {
        guard case let .value(raw, _) = read(VCP.input) else { return nil }
        let quirks = inputQuirks
        if quirks.isEmpty { return raw }
        return quirks.first { $0.reported == raw }?.standard
    }

    // MARK: Private

    /// Some monitors accept standard MCCS codes for switching but report the active
    /// input in their own numbering. Keyed by a substring of the product name.
    private static let inputReadQuirks: [(model: String, reported: UInt16, standard: UInt16)] = [
        ("Odyssey G8", 0x01, 0x11),  // hdmi1
        ("Odyssey G8", 0x03, 0x12),  // hdmi2
        ("Odyssey G8", 0x04, 0x0F),  // dp1
    ]

    private var inputQuirks: [(model: String, reported: UInt16, standard: UInt16)] {
        Self.inputReadQuirks.filter { name.localizedCaseInsensitiveContains($0.model) }
    }

    /// A value read back from the monitor, mapped to the code used to set it.
    private func readNormalized(_ code: UInt8, attempts: Int) -> UInt16? {
        guard case let .value(raw, _) = read(code, attempts: attempts) else { return nil }
        guard code == VCP.input else { return raw }
        return inputQuirks.first { $0.reported == raw }?.standard ?? raw
    }

    private func write(_ payload: [UInt8]) -> Bool {
        var buf = payload + [payload.reduce(UInt8(0x6E ^ 0x51), ^)]
        for _ in 0..<3 {
            usleep(10_000)
            if IOAVServiceWriteI2C(service, Self.chip, Self.host, &buf, UInt32(buf.count)) == kIOReturnSuccess { return true }
        }
        return false
    }
}

private func className(_ entry: io_registry_entry_t) -> String {
    (IOObjectCopyClass(entry)?.takeRetainedValue() as String?) ?? ""
}

private func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
    IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
}

private func productAttribute(_ entry: io_registry_entry_t, _ key: String) -> String? {
    let attributes = property(entry, "DisplayAttributes") as? [String: Any]
    return (attributes?["ProductAttributes"] as? [String: Any])?[key] as? String
}
