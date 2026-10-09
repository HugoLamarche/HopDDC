import Foundation
import ServiceManagement

enum CLI {
    static func run(_ arguments: [String]) -> Int32 {
        // -m <monitor> picks one monitor: a number from `hopddc list`, a serial, or part of the name.
        var args = arguments
        var selector: String?
        if let i = args.firstIndex(where: { $0 == "-m" || $0 == "--monitor" }) {
            guard i + 1 < args.count else { return usage() }
            selector = args[i + 1]
            args.removeSubrange(i...i + 1)
        }
        guard let command = args.first else { return usage() }

        switch (command, args.count) {
        case ("list", 1):
            return list()
        case ("to", 2):
            return switchTo(args[1], selector: selector)
        case ("input", 1):
            return withMonitor(selector) { m in
                guard let input = m.currentInput() else { return fail("\(m.name): could not read the input") }
                let machine = Store.shared.profile(for: m)?.machines.first { $0.input == input }
                print("\(VCP.name(of: input, for: VCP.input) ?? String(format: "0x%02X", input))\(machine.map { " (\($0.name))" } ?? "")")
                return 0
            }
        case ("inputs", 1):
            return withMonitor(selector) { m in
                guard let inputs = m.supportedInputs() else { return fail("\(m.name): the monitor did not report its inputs") }
                let current = m.currentInput()
                let machines = Store.shared.profile(for: m)?.machines ?? []
                print("\(m.name):")
                for input in inputs {
                    let name = VCP.name(of: input, for: VCP.input) ?? String(format: "0x%02X", input)
                    let users = machines.filter { $0.input == input }.map(\.name).joined(separator: ", ")
                    print("\(input == current ? "*" : " ") \(name.padding(toLength: 8, withPad: " ", startingAt: 0))\(users)")
                }
                return 0
            }
        case ("caps", 1):
            return withMonitor(selector) { m in
                guard let caps = m.capabilities() else { return fail("\(m.name): the monitor did not return its capabilities") }
                print(caps)
                return 0
            }
        case ("input", 2):
            guard let v = VCP.value(args[1], for: VCP.input) else { return fail("bad input '\(args[1])'") }
            return withMonitor(selector) { set($0, VCP.input, v, label: VCP.inputLabel(v)) }
        case ("get", 2):
            guard let code = VCP.code(args[1]) else { return fail("unknown setting '\(args[1])'") }
            return withMonitor(selector) { m in
                switch m.read(code) {
                case let .value(current, max):
                    let name = VCP.name(of: current, for: code)
                    print(name.map { "\(current) (\($0))" } ?? "\(current) / max \(max)")
                    return 0
                case .unsupported: return fail(String(format: "\(m.name): 0x%02X not supported", code))
                case .failed: return fail("\(m.name): DDC read failed")
                }
            }
        case ("set", 3):
            guard let code = VCP.code(args[1]) else { return fail("unknown setting '\(args[1])'") }
            guard let v = VCP.value(args[2], for: code) else { return fail("bad value '\(args[2])'") }
            return withMonitor(selector) { set($0, code, v, label: "\(args[1]) \(args[2])") }
        case ("login", 2) where ["on", "off"].contains(args[1]):
            do {
                if args[1] == "on" { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                return 0
            } catch {
                return fail("login item: \(error.localizedDescription)")
            }
        default:
            return usage()
        }
    }

    /// Switches every monitor that has a machine with this name (or just the -m one).
    private static func switchTo(_ name: String, selector: String?) -> Int32 {
        let monitors = Monitor.all()
        var only: Monitor?
        if let selector {
            guard let m = pick(selector, from: monitors) else { return fail("no monitor matching '\(selector)' (see: hopddc list)") }
            only = m
        }

        let targets = Store.shared.profiles.compactMap { p in p.machine(named: name).map { (p, $0) } }
        guard !targets.isEmpty else { return fail("unknown machine '\(name)' (\(machineNames))") }

        var status: Int32 = 0
        var switched = 0
        for (profile, machine) in targets {
            guard let m = monitors.first(where: profile.matches) else {
                if only == nil { FileHandle.standardError.write(Data("\(profile.monitor): not connected\n".utf8)) }
                continue
            }
            if let only, only.serial != m.serial || only.name != m.name { continue }
            if set(m, VCP.input, machine.input, label: machine.name) != 0 { status = 1 }
            switched += 1
        }
        return switched == 0 ? fail("no connected monitor has a machine named '\(name)'") : status
    }

    private static var machineNames: String {
        var seen = Set<String>()
        return Store.shared.profiles.flatMap(\.machines).map(\.name)
            .filter { seen.insert($0.lowercased()).inserted }.joined(separator: "|")
    }

    private static func set(_ m: Monitor, _ code: UInt8, _ value: UInt16, label: String) -> Int32 {
        switch m.set(code, value) {
        case .confirmed: print("\(m.name): \(label)")
        case .unconfirmed: print("\(m.name): \(label) (sent, could not confirm)")
        case .rejected: return fail("\(m.name): monitor did not accept \(label)")
        }
        return 0
    }

    private static func list() -> Int32 {
        for (i, m) in Monitor.all().enumerated() {
            let input = m.currentInput().map(VCP.inputLabel) ?? "input unreadable"
            print("\(i + 1): \(m.name)  serial \(m.serial)  (\(input))")
        }
        return 0
    }

    /// The -m monitor, or else the first one with machines set up, or else the first one.
    private static func withMonitor(_ selector: String?, _ body: (Monitor) -> Int32) -> Int32 {
        let monitors = Monitor.all()
        let m: Monitor?
        if let selector {
            m = pick(selector, from: monitors)
        } else {
            m = monitors.first { Store.shared.profile(for: $0)?.machines.isEmpty == false } ?? monitors.first
        }
        guard let m else {
            return fail(selector.map { "no monitor matching '\($0)' (see: hopddc list)" } ?? "no external monitor")
        }
        return body(m)
    }

    private static func pick(_ selector: String, from monitors: [Monitor]) -> Monitor? {
        if let i = Int(selector) { return monitors.indices.contains(i - 1) ? monitors[i - 1] : nil }
        return monitors.first { $0.serial.caseInsensitiveCompare(selector) == .orderedSame }
            ?? monitors.first { $0.name.localizedCaseInsensitiveContains(selector) }
    }

    @discardableResult
    private static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
        return 1
    }

    private static func usage() -> Int32 {
        fail("""
        hopddc - switch monitors between machines over DDC/CI
        With no arguments it runs as a menu bar app.

          hopddc to <machine>          switch every monitor that has this machine (\(machineNames))
          hopddc input [name|value]    read or switch the input (hdmi1, hdmi2, dp1, ...)
          hopddc inputs                the inputs the monitor has (* = current)
          hopddc caps                  the monitor's raw capabilities string
          hopddc get <setting>         read a setting (brightness, volume, 0x10, ...)
          hopddc set <setting> <value> change a setting
          hopddc list                  external monitors and their inputs
          hopddc login on|off          launch the menu bar app at login

        Add -m <monitor> to act on one monitor: a number from `hopddc list`, a serial
        number, or part of the name. Without it, input/get/set use the first monitor
        that has machines set up.
        """)
        return 2
    }
}
