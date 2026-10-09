import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: Store
    @State private var detected: [String] = []
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var reading: String?  // id of the machine whose input is being read

    var body: some View {
        Form {
            Section("Monitor") {
                Picker("Monitor", selection: $store.monitor) {
                    Text("First external monitor").tag("")
                    ForEach(monitorChoices, id: \.self) { Text($0).tag($0) }
                }
            }

            Section {
                ForEach($store.machines) { $machine in
                    HStack {
                        TextField("Name", text: $machine.name, prompt: Text("Name"))
                            .labelsHidden()
                        Picker("Input", selection: $machine.input) {
                            ForEach(inputChoices(including: machine.input), id: \.self) { Text(VCP.inputLabel($0)).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                        Button(reading == machine.id ? "Reading…" : "Use Current") { useCurrentInput(for: machine.id) }
                            .disabled(reading != nil)
                            .help("Set this to the input the monitor is showing now")
                        Button { remove(machine.id) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .help("Remove")
                    }
                }
                Button("Add Machine") {
                    store.machines.append(Machine(name: "Machine \(store.machines.count + 1)", input: 0x11))
                }
            } header: {
                Text("Machines")
            } footer: {
                Text("Names work on the command line too: hopddc to <name>")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Picker("This Mac is", selection: $store.thisMac) {
                    Text("Not set").tag("")
                    ForEach(store.machines) { Text($0.name).tag($0.id) }
                }
                Picker("When this Mac locks", selection: $store.onLock) { actionChoices }
                Picker("When this Mac unlocks", selection: $store.onUnlock) { actionChoices }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { setLaunchAtLogin($0) }
            } header: {
                Text("This Mac")
            } footer: {
                Text(store.thisMac.isEmpty
                     ? "Set which machine this Mac is to switch on lock only while the monitor is showing it."
                     : "On lock, the monitor is switched only while it is showing this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 420)
        .onAppear(perform: detectMonitors)
    }

    @ViewBuilder private var actionChoices: some View {
        Text("Do nothing").tag("")
        ForEach(store.machines) { Text("Switch to \($0.name)").tag($0.id) }
    }

    private var monitorChoices: [String] {
        detected.contains(store.monitor) || store.monitor.isEmpty ? detected : detected + [store.monitor]
    }

    private func inputChoices(including current: UInt16) -> [UInt16] {
        VCP.commonInputs.contains(current) ? VCP.commonInputs : VCP.commonInputs + [current]
    }

    private func remove(_ id: String) {
        store.machines.removeAll { $0.id == id }
        if store.thisMac == id { store.thisMac = "" }
        if store.onLock == id { store.onLock = "" }
        if store.onUnlock == id { store.onUnlock = "" }
    }

    private func detectMonitors() {
        DispatchQueue.global().async {
            let names = Monitor.all().map(\.name)
            DispatchQueue.main.async { detected = names }
        }
    }

    private func useCurrentInput(for id: String) {
        reading = id
        let match = store.monitor
        DispatchQueue.global().async {
            let input = Monitor.find(match)?.currentInput()
            DispatchQueue.main.async {
                reading = nil
                guard let input, let i = store.machines.firstIndex(where: { $0.id == id }) else { NSSound.beep(); return }
                store.machines[i].input = input
            }
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        let service = SMAppService.mainApp
        do {
            if on { try service.register() } else { try service.unregister() }
        } catch {
            appLog("login item: \(error.localizedDescription)")
        }
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        launchAtLogin = service.status == .enabled
    }
}
