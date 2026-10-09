import Foundation

/// Menu choices, persisted in UserDefaults. A value is a Machine id, or "" for nothing.
enum Settings {
    static let onLockKey = "onLock"
    static let onUnlockKey = "onUnlock"

    static func register() {
        UserDefaults.standard.register(defaults: [onLockKey: "pc", onUnlockKey: ""])
    }

    static func machine(for key: String) -> Machine? {
        Config.machine(UserDefaults.standard.string(forKey: key) ?? "")
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
