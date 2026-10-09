import ServiceManagement
import SwiftUI

/// A monitor seen on the last scan.
struct DetectedMonitor: Hashable {
    let name: String
    let serial: String
}

struct SettingsView: View {
    @ObservedObject var store: Store
    @State private var detected: [DetectedMonitor] = []
    @State private var scanned = false

    var body: some View {
        TabView {
            ForEach($store.profiles) { $profile in
                ProfileView(profile: $profile, connected: connected(profile), onForget: { forget(profile.id) })
                    .tabItem { Text(title(for: profile)) }
            }
            GeneralView()
                .tabItem { Text("General") }
        }
        .padding(.top, 8)
        .frame(minWidth: 560, minHeight: 460)
        .overlay {
            if scanned && store.profiles.isEmpty {
                Text("No external monitors found. Check that DDC/CI is on in the monitor's menu.")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: detectMonitors)
    }

    private func connected(_ profile: Profile) -> DetectedMonitor? {
        detected.first { profile.matches(name: $0.name, serial: $0.serial) }
    }

    /// The monitor's name, with its serial when several connected monitors share that name.
    private func title(for profile: Profile) -> String {
        guard let m = connected(profile) else { return "\(profile.monitor) (not connected)" }
        let twins = detected.filter { $0.name == m.name }.count > 1
        return twins && !m.serial.isEmpty ? "\(m.name) · \(m.serial.suffix(4))" : m.name
    }

    private func forget(_ id: String) {
        store.profiles.removeAll { $0.id == id }
    }

    private func detectMonitors() {
        Monitor.queue.async {
            let found = Monitor.all().map { DetectedMonitor(name: $0.name, serial: $0.serial) }
            DispatchQueue.main.async {
                detected = found
                store.addProfiles(for: found.map { ($0.name, $0.serial) })
                scanned = true
            }
        }
    }
}

/// Machines and lock/unlock actions for one monitor.
private struct ProfileView: View {
    @Binding var profile: Profile
    let connected: DetectedMonitor?
    let onForget: () -> Void
    @State private var reading: String?  // id of the machine whose input is being read
    @State private var current: UInt16?      // the input the monitor is showing
    @State private var reported: [UInt16]?   // the inputs the monitor says it has
    @State private var detecting = false

    var body: some View {
        Form {
            if connected == nil {
                Section {
                    HStack {
                        Text("This monitor is not connected. Its settings apply when it is.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Forget Monitor", role: .destructive, action: onForget)
                    }
                }
            }

            Section {
                ForEach(allInputs, id: \.self) { input in
                    Toggle(isOn: offered(input)) {
                        HStack {
                            Text(VCP.inputLabel(input))
                            if input == current {
                                Text("showing now").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            } header: {
                HStack {
                    Text("Inputs")
                    Spacer()
                    Button(detecting ? "Detecting…" : "Detect") { detect(replacing: true) }
                        .disabled(detecting || connected == nil)
                }
            } footer: {
                Text(reported == nil
                     ? "This monitor does not list its inputs. Uncheck the ones it doesn't have; only checked inputs are offered for machines."
                     : "Detected from the monitor. Only checked inputs are offered for machines.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                ForEach($profile.machines) { $machine in
                    HStack {
                        TextField("Name", text: $machine.name, prompt: Text("Name"))
                            .labelsHidden()
                        Picker("Input", selection: $machine.input) {
                            ForEach(inputChoices(including: machine.input), id: \.self) { Text(VCP.inputLabel($0)).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                        Button(reading == machine.id ? "Reading…" : "Use Current") { useCurrentInput(for: machine.id) }
                            .disabled(reading != nil || connected == nil)
                            .help("Set this to the input the monitor is showing now")
                        Button { remove(machine.id) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .help("Remove")
                    }
                }
                Button("Add Machine") {
                    profile.machines.append(Machine(name: "Machine \(profile.machines.count + 1)", input: 0x11))
                }
            } header: {
                Text("Machines")
            } footer: {
                Text("Leave empty to keep this monitor out of the menu. Names work on the command line too: hopddc to <name>")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Picker("This Mac is", selection: $profile.thisMac) {
                    Text("Not set").tag("")
                    ForEach(profile.machines) { Text($0.name).tag($0.id) }
                }
                Picker("When this Mac locks", selection: $profile.onLock) { actionChoices }
                Picker("When this Mac unlocks", selection: $profile.onUnlock) { actionChoices }
            } header: {
                Text("This Mac")
            } footer: {
                Text(profile.thisMac.isEmpty
                     ? "Set which machine this Mac is to switch on lock only while this monitor is showing it."
                     : "On lock, this monitor is switched only while it is showing this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { if connected != nil { detect(replacing: false) } }
    }

    /// Common inputs, plus any others this monitor uses, in a stable order.
    private var allInputs: [UInt16] {
        let extra = (profile.inputs ?? []) + (reported ?? []) + profile.machines.map(\.input)
        var seen = Set(VCP.commonInputs)
        return VCP.commonInputs + extra.filter { seen.insert($0).inserted }
    }

    private func offered(_ input: UInt16) -> Binding<Bool> {
        Binding(
            get: { (profile.inputs ?? VCP.commonInputs).contains(input) },
            set: { on in
                var list = profile.inputs ?? VCP.commonInputs
                if on { list.append(input) } else { list.removeAll { $0 == input } }
                profile.inputs = allInputs.filter(list.contains)
            })
    }

    /// Reads the current input and the monitor's input list. Fills in the offered inputs
    /// the first time, or always when `replacing`.
    private func detect(replacing: Bool) {
        detecting = true
        let snapshot = profile
        Monitor.queue.async {
            let monitor = Monitor.all().first(where: snapshot.matches)
            let showing = monitor?.currentInput()
            let list = monitor?.supportedInputs()
            DispatchQueue.main.async {
                detecting = false
                current = showing
                reported = list
                if let list, replacing || profile.inputs == nil { profile.inputs = list }
            }
        }
    }

    @ViewBuilder private var actionChoices: some View {
        Text("Do nothing").tag("")
        ForEach(profile.machines) { Text("Switch to \($0.name)").tag($0.id) }
    }

    private func inputChoices(including selected: UInt16) -> [UInt16] {
        let offered = profile.inputs ?? VCP.commonInputs
        return offered.contains(selected) ? offered : offered + [selected]
    }

    private func remove(_ id: String) {
        profile.machines.removeAll { $0.id == id }
        if profile.thisMac == id { profile.thisMac = "" }
        if profile.onLock == id { profile.onLock = "" }
        if profile.onUnlock == id { profile.onUnlock = "" }
    }

    private func useCurrentInput(for id: String) {
        reading = id
        let snapshot = profile
        Monitor.queue.async {
            let input = Monitor.all().first(where: snapshot.matches)?.currentInput()
            DispatchQueue.main.async {
                reading = nil
                guard let input, let i = profile.machines.firstIndex(where: { $0.id == id }) else { NSSound.beep(); return }
                profile.machines[i].input = input
            }
        }
    }
}

private struct GeneralView: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { setLaunchAtLogin($0) }
        }
        .formStyle(.grouped)
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
