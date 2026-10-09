import Foundation

struct Machine: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var name: String   // shown in the menu; `hopddc to <name>` on the command line
    var input: UInt16  // MCCS input code (see VCP.swift)
}

/// The settings for one monitor.
struct Profile: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    /// The monitor's serial number, or part of its product name.
    var monitor: String
    var machines: [Machine] = []
    /// Inputs offered for this monitor, or nil for VCP.commonInputs.
    var inputs: [UInt16]?
    /// The machine id of the Mac running HopDDC, or "" if not set.
    var thisMac = ""
    /// Machine ids, or "" to do nothing.
    var onLock = ""
    var onUnlock = ""

    func matches(_ m: Monitor) -> Bool {
        matches(name: m.name, serial: m.serial)
    }

    func matches(name: String, serial: String) -> Bool {
        guard !monitor.isEmpty else { return false }
        return (!serial.isEmpty && monitor == serial) || name.localizedCaseInsensitiveContains(monitor)
    }

    func machine(id: String) -> Machine? {
        machines.first { $0.id == id }
    }

    func machine(named name: String) -> Machine? {
        machines.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}

/// All settings, persisted in the app's preferences (`defaults read com.hugolamarche.hopddc`).
final class Store: ObservableObject {
    static let shared = Store()
    static let domain = "com.hugolamarche.hopddc"

    @Published var profiles: [Profile] { didSet { save() } }

    private let defaults: UserDefaults

    private init() {
        // The CLI usually runs through a symlink, outside the app bundle, so name the domain
        // explicitly there. Inside the app, a suite named after the app's own id is not allowed.
        defaults = Bundle.main.bundleIdentifier == Self.domain ? .standard : UserDefaults(suiteName: Self.domain)!
        profiles = defaults.string(forKey: "profiles")
            .flatMap { try? JSONDecoder().decode([Profile].self, from: Data($0.utf8)) } ?? []
        if defaults.string(forKey: "profiles") == nil { migrateSingleMonitorSettings() }
    }

    /// The profile for a connected monitor.
    func profile(for monitor: Monitor) -> Profile? {
        profiles.first { $0.matches(monitor) }
    }

    /// Adds an empty profile for each connected monitor that has none.
    func addProfiles(for monitors: [(name: String, serial: String)]) {
        for m in monitors where !profiles.contains(where: { $0.matches(name: m.name, serial: m.serial) }) {
            profiles.append(Profile(monitor: m.serial.isEmpty ? m.name : m.serial))
        }
    }

    // Stored as a JSON string so it stays readable and editable with `defaults`.
    private func save() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        defaults.set(String(decoding: data, as: UTF8.self), forKey: "profiles")
    }

    /// Versions before multi-monitor support kept one monitor's settings in separate keys.
    private func migrateSingleMonitorSettings() {
        let old = ["monitor", "machines", "thisMac", "onLock", "onUnlock"]
        guard let json = defaults.string(forKey: "machines"),
              let machines = try? JSONDecoder().decode([Machine].self, from: Data(json.utf8)) else { return }
        // An empty monitor used to mean "the first external monitor".
        var monitor = defaults.string(forKey: "monitor") ?? ""
        if monitor.isEmpty, let first = Monitor.all().first { monitor = first.serial.isEmpty ? first.name : first.serial }
        profiles = [Profile(
            monitor: monitor,
            machines: machines,
            thisMac: defaults.string(forKey: "thisMac") ?? "",
            onLock: defaults.string(forKey: "onLock") ?? "",
            onUnlock: defaults.string(forKey: "onUnlock") ?? ""
        )]
        old.forEach(defaults.removeObject)
    }
}

/// Appends a line to ~/Library/Logs/HopDDC.log.
func appLog(_ message: String) {
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/HopDDC.log")
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        try? handle.close()
    } else {
        try? Data(line.utf8).write(to: url)
    }
}
