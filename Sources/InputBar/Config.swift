// The monitor and the machines plugged into it. Edit to match your setup,
// then re-run ./inputbar.sh install.

struct Machine {
    let id: String     // used on the command line: `inputbar to <id>`
    let label: String  // shown in the menu
    let input: UInt16  // MCCS input code (see VCP.swift)
}

enum Config {
    /// Part of the monitor's product name.
    static let monitorMatch = "G8"

    static let machines = [
        Machine(id: "studio", label: "Studio (this Mac)", input: 0x12),  // HDMI 2
        Machine(id: "mini", label: "Mini", input: 0x11),                 // HDMI 1
        Machine(id: "pc", label: "PC", input: 0x0F),                     // DisplayPort 1
    ]

    static func machine(_ id: String) -> Machine? {
        machines.first { $0.id == id.lowercased() }
    }
}
