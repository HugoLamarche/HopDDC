import Foundation

struct Machine: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var name: String   // shown in the menu; `inputbar to <name>` on the command line
    var input: UInt16  // MCCS input code (see VCP.swift)
}

/// All settings, persisted in the app's preferences (`defaults read com.hugolamarche.inputbar`).
final class Store: ObservableObject {
    static let shared = Store()
    static let domain = "com.hugolamarche.inputbar"

    /// Part of the monitor's product name. Empty means the first external monitor.
    @Published var monitor: String { didSet { defaults.set(monitor, forKey: "monitor") } }
    @Published var machines: [Machine] { didSet { saveMachines() } }
    /// Machine ids, or "" to do nothing.
    @Published var onLock: String { didSet { defaults.set(onLock, forKey: "onLock") } }
    @Published var onUnlock: String { didSet { defaults.set(onUnlock, forKey: "onUnlock") } }

    private let defaults: UserDefaults

    private init() {
        // The CLI usually runs through a symlink, outside the app bundle, so name the domain
        // explicitly there. Inside the app, a suite named after the app's own id is not allowed.
        defaults = Bundle.main.bundleIdentifier == Self.domain ? .standard : UserDefaults(suiteName: Self.domain)!
        monitor = defaults.string(forKey: "monitor") ?? ""
        machines = defaults.string(forKey: "machines")
            .flatMap { try? JSONDecoder().decode([Machine].self, from: Data($0.utf8)) } ?? []
        onLock = defaults.string(forKey: "onLock") ?? ""
        onUnlock = defaults.string(forKey: "onUnlock") ?? ""
    }

    func machine(id: String) -> Machine? {
        machines.first { $0.id == id }
    }

    func machine(named name: String) -> Machine? {
        machines.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    // Stored as a JSON string so it stays readable and editable with `defaults`.
    private func saveMachines() {
        guard let data = try? JSONEncoder().encode(machines) else { return }
        defaults.set(String(decoding: data, as: UTF8.self), forKey: "machines")
    }
}

/// Appends a line to ~/Library/Logs/InputBar.log.
func appLog(_ message: String) {
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/InputBar.log")
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        try? handle.close()
    } else {
        try? Data(line.utf8).write(to: url)
    }
}
