import Foundation
import ServiceManagement

enum CLI {
    static func run(_ args: [String]) -> Int32 {
        switch (args[0], args.count) {
        case ("list", 1):
            return list()
        case ("to", 2):
            guard let machine = Config.machine(args[1]) else { return fail("unknown machine '\(args[1])' (\(machineIds))") }
            return set(VCP.input, machine.input, label: machine.label)
        case ("input", 1):
            return withMonitor { m in
                guard let input = m.currentInput() else { return fail("could not read the input") }
                let machine = Config.machines.first { $0.input == input }
                print("\(VCP.name(of: input, for: VCP.input) ?? String(format: "0x%02X", input))\(machine.map { " (\($0.id))" } ?? "")")
                return 0
            }
        case ("input", 2):
            guard let v = VCP.value(args[1], for: VCP.input) else { return fail("bad input '\(args[1])'") }
            return set(VCP.input, v, label: VCP.inputLabel(v))
        case ("get", 2):
            guard let code = VCP.code(args[1]) else { return fail("unknown setting '\(args[1])'") }
            return withMonitor { m in
                switch m.read(code) {
                case let .value(current, max):
                    let name = VCP.name(of: current, for: code)
                    print(name.map { "\(current) (\($0))" } ?? "\(current) / max \(max)")
                    return 0
                case .unsupported: return fail(String(format: "0x%02X not supported by this monitor", code))
                case .failed: return fail("DDC read failed")
                }
            }
        case ("set", 3):
            guard let code = VCP.code(args[1]) else { return fail("unknown setting '\(args[1])'") }
            guard let v = VCP.value(args[2], for: code) else { return fail("bad value '\(args[2])'") }
            return set(code, v, label: "\(args[1]) \(args[2])")
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

    private static var machineIds: String { Config.machines.map(\.id).joined(separator: "|") }

    private static func set(_ code: UInt8, _ value: UInt16, label: String) -> Int32 {
        withMonitor { m in
            switch m.set(code, value) {
            case .confirmed: print("\(m.name): \(label)")
            case .unconfirmed: print("\(m.name): \(label) (sent, could not confirm)")
            case .rejected: return fail("\(m.name): monitor did not accept \(label)")
            }
            return 0
        }
    }

    private static func list() -> Int32 {
        for (i, m) in Monitor.all().enumerated() {
            let input = m.currentInput().map(VCP.inputLabel) ?? "input unreadable"
            print("\(i + 1): \(m.name)  serial \(m.serial)  (\(input))")
        }
        return 0
    }

    private static func withMonitor(_ body: (Monitor) -> Int32) -> Int32 {
        guard let m = Monitor.configured() else { return fail("no monitor matching '\(Config.monitorMatch)' (see: inputbar list)") }
        return body(m)
    }

    @discardableResult
    private static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
        return 1
    }

    private static func usage() -> Int32 {
        fail("""
        inputbar - switch the monitor between machines over DDC/CI
        With no arguments it runs as a menu bar app.

          inputbar to <machine>          switch to a machine (\(machineIds))
          inputbar input [name|value]    read or switch the input (hdmi1, hdmi2, dp1, ...)
          inputbar get <setting>         read a setting (brightness, volume, 0x10, ...)
          inputbar set <setting> <value> change a setting
          inputbar list                  external monitors and their inputs
          inputbar login on|off          launch the menu bar app at login
        """)
        return 2
    }
}
