import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = Store.shared
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private var connectedNames: [String: String] = [:]  // profile id -> connected monitor name
    private var currentInputs: [String: UInt16] = [:]   // profile id -> last known input
    private var refreshing = false
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setIcon(warning: false)
        menu.delegate = self
        statusItem.menu = menu

        // Launch at login by default; Settings turns it off.
        if !UserDefaults.standard.bool(forKey: "didFirstLaunch") {
            UserDefaults.standard.set(true, forKey: "didFirstLaunch")
            try? SMAppService.mainApp.register()
        }

        let center = DistributedNotificationCenter.default()
        center.addObserver(self, selector: #selector(screenLocked), name: .init("com.apple.screenIsLocked"), object: nil)
        center.addObserver(self, selector: #selector(screenUnlocked), name: .init("com.apple.screenIsUnlocked"), object: nil)

        appLog("started")
        refresh()
        if store.profiles.allSatisfy({ $0.machines.isEmpty }) { openSettings() }
    }

    // MARK: Lock / unlock

    @objc private func screenLocked() {
        for profile in store.profiles {
            guard let m = profile.machine(id: profile.onLock) else { continue }
            // With this Mac identified, leave the monitor alone unless it is showing this Mac.
            switchTo(m, on: profile, reason: "lock", onlyIfShowing: profile.machine(id: profile.thisMac))
        }
    }

    @objc private func screenUnlocked() {
        for profile in store.profiles {
            if let m = profile.machine(id: profile.onUnlock) { switchTo(m, on: profile, reason: "unlock") }
        }
    }

    // MARK: DDC

    private func switchTo(_ machine: Machine, on profile: Profile, reason: String, onlyIfShowing required: Machine? = nil) {
        Monitor.queue.async {
            // Keep App Nap from stretching the waits between DDC writes and read-backs.
            let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "Switching monitor input")
            defer { ProcessInfo.processInfo.endActivity(activity) }

            guard let monitor = Monitor.all().first(where: profile.matches) else {
                appLog("\(reason): monitor '\(profile.monitor)' not connected")
                DispatchQueue.main.async { self.setIcon(warning: true) }
                return
            }
            if let required {
                // A monitor showing another input may not answer at all; that also means "not this Mac".
                let current = monitor.currentInput()
                guard current == required.input else {
                    let showing = current.map(VCP.inputLabel) ?? "unknown"
                    appLog("\(reason): \(monitor.name): skipped, showing \(showing), not \(required.name)")
                    return
                }
            }
            let result = monitor.set(VCP.input, machine.input)
            appLog("\(reason): \(monitor.name): \(machine.name) (\(VCP.inputLabel(machine.input))) -> \(result)")
            DispatchQueue.main.async {
                if result != .rejected { self.currentInputs[profile.id] = machine.input }
                self.setIcon(warning: result == .rejected)
                self.updateMenu()
            }
        }
    }

    /// Re-reads the monitors and their inputs in the background, then updates the menu.
    private func refresh() {
        guard !refreshing else { return }
        refreshing = true
        let profiles = store.profiles.filter { !$0.machines.isEmpty }
        Monitor.queue.async {
            let monitors = Monitor.all()
            var names: [String: String] = [:], inputs: [String: UInt16] = [:]
            for profile in profiles {
                guard let m = monitors.first(where: profile.matches) else { continue }
                names[profile.id] = m.name
                inputs[profile.id] = m.currentInput()
            }
            DispatchQueue.main.async {
                self.refreshing = false
                self.connectedNames = names
                // Some monitors stop answering while showing another input; keep the last known one.
                self.currentInputs = self.currentInputs.filter { names[$0.key] != nil }.merging(inputs) { $1 }
                self.updateMenu()
            }
        }
    }

    // MARK: Menu

    /// Builds the items when the menu opens. While it is open only updateMenu() touches
    /// it, because replacing items in an open menu leaves gaps.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let profiles = store.profiles.filter { !$0.machines.isEmpty }
        if profiles.isEmpty {
            let hint = NSMenuItem(title: "Add machines in Settings", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
        }
        var shortcut = 1
        for (i, profile) in profiles.enumerated() {
            if i > 0 { menu.addItem(.separator()) }
            let header = NSMenuItem(title: profile.monitor, action: nil, keyEquivalent: "")
            header.isEnabled = false
            header.representedObject = profile.id
            menu.addItem(header)

            for machine in profile.machines {
                let name = machine.id == profile.thisMac ? "\(machine.name) (this Mac)" : machine.name
                let item = NSMenuItem(title: "\(name)  ·  \(VCP.inputLabel(machine.input))",
                                      action: #selector(pickMachine(_:)), keyEquivalent: shortcut <= 9 ? "\(shortcut)" : "")
                shortcut += 1
                item.target = self
                item.representedObject = [profile.id, machine.id]
                item.indentationLevel = 1
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        updateMenu()
        refresh()
    }

    private func updateMenu() {
        for item in menu.items {
            if let profileID = item.representedObject as? String, let profile = store.profiles.first(where: { $0.id == profileID }) {
                item.title = connectedNames[profileID] ?? "\(profile.monitor) (not connected)"
            } else if let ids = item.representedObject as? [String],
                      let profile = store.profiles.first(where: { $0.id == ids[0] }), let machine = profile.machine(id: ids[1]) {
                item.state = machine.input == currentInputs[profile.id] ? .on : .off
                item.isEnabled = connectedNames[profile.id] != nil
            }
        }
    }

    @objc private func pickMachine(_ sender: NSMenuItem) {
        guard let ids = sender.representedObject as? [String],
              let profile = store.profiles.first(where: { $0.id == ids[0] }), let machine = profile.machine(id: ids[1]) else { return }
        switchTo(machine, on: profile, reason: "menu")
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            // A grouped Form scrolls and has no height of its own, so size the window explicitly
            // and let the hosting controller enforce only the view's minimum size.
            let hosting = NSHostingController(rootView: SettingsView(store: store))
            hosting.sizingOptions = [.minSize]
            let window = NSWindow(contentViewController: hosting)
            window.title = "HopDDC Settings"
            window.styleMask = [.titled, .closable, .resizable]
            window.setContentSize(NSSize(width: 600, height: 600))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func setIcon(warning: Bool) {
        let symbol = warning ? "exclamationmark.triangle" : "display"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "HopDDC")
    }
}
