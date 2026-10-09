import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let ddc = DispatchQueue(label: "InputBar.ddc")  // DDC traffic is serialized here
    private var monitorName: String?
    private var currentInput: UInt16?
    private var refreshing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.register()
        setIcon(warning: false)
        menu.delegate = self
        statusItem.menu = menu

        // Launch at login by default; the menu toggle turns it off.
        if !UserDefaults.standard.bool(forKey: "didFirstLaunch") {
            UserDefaults.standard.set(true, forKey: "didFirstLaunch")
            try? SMAppService.mainApp.register()
        }

        let center = DistributedNotificationCenter.default()
        center.addObserver(self, selector: #selector(screenLocked), name: .init("com.apple.screenIsLocked"), object: nil)
        center.addObserver(self, selector: #selector(screenUnlocked), name: .init("com.apple.screenIsUnlocked"), object: nil)

        appLog("started")
        refresh()
    }

    // MARK: Lock / unlock

    @objc private func screenLocked() {
        if let m = Settings.machine(for: Settings.onLockKey) { switchTo(m, reason: "lock") }
    }

    @objc private func screenUnlocked() {
        if let m = Settings.machine(for: Settings.onUnlockKey) { switchTo(m, reason: "unlock") }
    }

    // MARK: DDC

    private func switchTo(_ machine: Machine, reason: String) {
        ddc.async {
            // Keep App Nap from stretching the waits between DDC writes and read-backs.
            let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "Switching monitor input")
            defer { ProcessInfo.processInfo.endActivity(activity) }

            guard let monitor = Monitor.configured() else {
                appLog("\(reason): no monitor matching '\(Config.monitorMatch)'")
                DispatchQueue.main.async { self.setIcon(warning: true) }
                return
            }
            let result = monitor.set(VCP.input, machine.input)
            appLog("\(reason): \(machine.id) (\(VCP.inputLabel(machine.input))) -> \(result)")
            DispatchQueue.main.async {
                if result != .rejected { self.currentInput = machine.input }
                self.setIcon(warning: result == .rejected)
                self.buildMenu()
            }
        }
    }

    /// Re-reads the monitor and its input in the background, then updates the menu.
    private func refresh() {
        guard !refreshing else { return }
        refreshing = true
        ddc.async {
            let monitor = Monitor.configured()
            let input = monitor?.currentInput()
            DispatchQueue.main.async {
                self.refreshing = false
                self.monitorName = monitor?.name
                // Some monitors stop answering while showing another input; keep the last known one.
                if monitor == nil { self.currentInput = nil } else if let input { self.currentInput = input }
                self.buildMenu()
            }
        }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        buildMenu()
        refresh()
    }

    private func buildMenu() {
        menu.removeAllItems()

        let header = NSMenuItem(title: monitorName ?? "No monitor matching “\(Config.monitorMatch)”", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        for (i, machine) in Config.machines.enumerated() {
            let item = NSMenuItem(title: "\(machine.label)  ·  \(VCP.inputLabel(machine.input))",
                                  action: #selector(pickMachine(_:)), keyEquivalent: "\(i + 1)")
            item.target = self
            item.representedObject = machine.id
            item.state = machine.input == currentInput ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(choiceMenu("When This Mac Locks", key: Settings.onLockKey))
        menu.addItem(choiceMenu("When This Mac Unlocks", key: Settings.onUnlockKey))

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit InputBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func choiceMenu(_ title: String, key: String) -> NSMenuItem {
        let selected = UserDefaults.standard.string(forKey: key) ?? ""
        let submenu = NSMenu()
        let choices = [("", "Do Nothing")] + Config.machines.map { ($0.id, "Switch to \($0.label)") }
        for (id, label) in choices {
            let item = NSMenuItem(title: label, action: #selector(pickChoice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = [key, id]
            item.state = id == selected ? .on : .off
            submenu.addItem(item)
        }
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.submenu = submenu
        return parent
    }

    @objc private func pickMachine(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String, let machine = Config.machine(id) {
            switchTo(machine, reason: "menu")
        }
    }

    @objc private func pickChoice(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String] else { return }
        UserDefaults.standard.set(pair[1], forKey: pair[0])
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            appLog("login item: \(error.localizedDescription)")
        }
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    private func setIcon(warning: Bool) {
        let symbol = warning ? "exclamationmark.triangle" : "display"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "InputBar")
    }
}
