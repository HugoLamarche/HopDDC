import AppKit

// With arguments: command-line tool. Without: menu bar app.
let arguments = Array(CommandLine.arguments.dropFirst())
// Flags macOS itself may pass to an app (-psn_..., -NSDocumentRevisionsDebugMode, ...) don't count.
if let first = arguments.first, !["-psn", "-NS", "-Apple"].contains(where: first.hasPrefix) {
    exit(CLI.run(arguments))
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
