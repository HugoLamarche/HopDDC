import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = Store.shared
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let ddc = DispatchQueue(label: "HopDDC.ddc")  // DDC traffic is serialized here
    private var monitorName: String?
    private var currentInput: UInt16?
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
        if store.machines.isEmpty { openSettings() }
    }

    // MARK: Lock / unlock

    @objc private func screenLocked() {
        guard let m = store.machine(id: store.onLock) else { return }
        // With this Mac identified, leave the monitor alone unless it is showing this Mac.
        switchTo(m, reason: "lock", onlyIfShowing: store.machine(id: store.thisMac))
    }

    @objc private func screenUnlocked() {
        if let m = store.machine(id: store.onUnlock) { switchTo(m, reason: "unlock") }
    }

    // MARK: DDC

    private func switchTo(_ machine: Machine, reason: String, onlyIfShowing required: Machine? = nil) {
        let match = store.monitor
        ddc.async {
            // Keep App Nap from stretching the waits between DDC writes and read-backs.
            let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "Switching monitor input")
            defer { ProcessInfo.processInfo.endActivity(activity) }

            guard let monitor = Monitor.find(match) else {
                appLog("\(reason): no monitor matching '\(match)'")
                DispatchQueue.main.async { self.setIcon(warning: true) }
                return
            }
            if let required {
                // A monitor showing another input may not answer at all; that also means "not this Mac".
                let current = monitor.currentInput()
                guard current == required.input else {
                    let showing = current.map(VCP.inputLabel) ?? "unknown"
                    appLog("\(reason): skipped, monitor is showing \(showing), not \(required.name)")
                    return
                }
            }
            let result = monitor.set(VCP.input, machine.input)
            appLog("\(reason): \(machine.name) (\(VCP.inputLabel(machine.input))) -> \(result)")
            DispatchQueue.main.async {
                if result != .rejected { self.currentInput = machine.input }
                self.setIcon(warning: result == .rejected)
                self.updateMenu()
            }
        }
    }

    /// Re-reads the monitor and its input in the background, then updates the menu.
    private func refresh() {
        guard !refreshing else { return }
        refreshing = true
        let match = store.monitor
        ddc.async {
            let monitor = Monitor.find(match)
            let input = monitor?.currentInput()
            DispatchQueue.main.async {
                self.refreshing = false
                self.monitorName = monitor?.name
                // Some monitors stop answering while showing another input; keep the last known one.
                if monitor == nil { self.currentInput = nil } else if let input { self.currentInput = input }
                self.updateMenu()
            }
        }
    }

    // MARK: Menu

    /// Builds the items when the menu opens. While it is open only updateMenu() touches
    /// it, because replacing items in an open menu leaves gaps.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if store.machines.isEmpty {
            let hint = NSMenuItem(title: "Add machines in Settings", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
        }
        for (i, machine) in store.machines.enumerated() {
            let name = machine.id == store.thisMac ? "\(machine.name) (this Mac)" : machine.name
            let item = NSMenuItem(title: "\(name)  ·  \(VCP.inputLabel(machine.input))",
                                  action: #selector(pickMachine(_:)), keyEquivalent: i < 9 ? "\(i + 1)" : "")
            item.target = self
            item.representedObject = machine.id
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(NSMenuItem(title: "Quit HopDDC", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        updateMenu()
        refresh()
    }

    private func updateMenu() {
        guard let header = menu.items.first else { return }
        header.title = monitorName ?? (store.monitor.isEmpty ? "No external monitor" : "No monitor matching “\(store.monitor)”")
        for item in menu.items {
            guard let id = item.representedObject as? String, let machine = store.machine(id: id) else { continue }
            item.state = machine.input == currentInput ? .on : .off
        }
    }

    @objc private func pickMachine(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String, let machine = store.machine(id: id) {
            switchTo(machine, reason: "menu")
        }
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
            window.setContentSize(NSSize(width: 560, height: 560))
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
