import SwiftUI

/// Live Activity configuration: master switch, per-kind toggles,
/// Dynamic Island priority ordering, and start/stop controls.
struct LiveActivitiesSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(
                    get: { appState.settings.settings.liveActivitiesMasterEnabled },
                    set: { enabled in
                        appState.settings.update { $0.liveActivitiesMasterEnabled = enabled }
                        if !enabled {
                            appState.liveActivityManager.stopAll()
                        }
                    }
                )) {
                    Label("Live Activities", systemImage: "rectangle.inset.filled.and.person.filled")
                }
                HStack {
                    Text("System authorization")
                    Spacer()
                    Text(appState.liveActivityManager.activitiesEnabled ? "Granted" : "Denied")
                        .foregroundStyle(appState.liveActivityManager.activitiesEnabled ? .green : .red)
                }
            } footer: {
                Text("Live Activities appear on the Lock Screen and Dynamic Island. The system decides Dynamic Island presentation; relevance scores influence which of DeviceLab's activities shows there.")
            }

            Section("Activities") {
                ForEach(DeviceLabActivityKind.allCases) { kind in
                    Toggle(isOn: toggleBinding(kind)) {
                        Label(kind.displayName, systemImage: kind.symbolName)
                    }
                }
            }

            Section {
                if appState.liveActivityManager.activeKinds.isEmpty {
                    Text("No Live Activities are running.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appState.liveActivityManager.activeKinds, id: \.self) { kind in
                        HStack {
                            Label(kind.displayName, systemImage: "bolt.circle.fill")
                                .foregroundStyle(.green)
                            Spacer()
                            Button("End") {
                                appState.liveActivityManager.stop(kind: kind)
                            }
                            .font(.caption)
                        }
                    }
                }
            } header: {
                Text("Running")
            } footer: {
                if let reason = appState.liveActivityManager.lastUpdateReason {
                    Text(reason)
                }
            }

            Section {
                ForEach(appState.settings.settings.liveActivityPriority) { kind in
                    HStack {
                        Image(systemName: kind.symbolName)
                            .foregroundStyle(.tint)
                        Text(kind.displayName)
                        Spacer()
                        Button {
                            move(kind, by: -1)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .disabled(!canMove(kind, by: -1))
                        Button {
                            move(kind, by: 1)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .disabled(!canMove(kind, by: 1))
                    }
                }
            } header: {
                Text("Dynamic Island priority")
            } footer: {
                Text("Higher priority → higher relevance score → the system is more likely to show that activity in the Dynamic Island when multiple are active.")
            }

            Section {
                Button("Start selected activities") {
                    appState.liveActivityManager.startAll(values: appState.systemMonitor.deviceData.liveValues)
                }
                Button("End all activities", role: .destructive) {
                    appState.liveActivityManager.stopAll()
                }
            }
        }
        .navigationTitle("Live Activities")
    }

    private func toggleBinding(_ kind: DeviceLabActivityKind) -> Binding<Bool> {
        Binding(
            get: { appState.settings.settings.liveActivityKinds[kind.metricKind] ?? false },
            set: { enabled in
                appState.settings.update { $0.liveActivityKinds[kind.metricKind] = enabled }
                if enabled {
                    appState.liveActivityManager.start(kind: kind, values: appState.systemMonitor.deviceData.liveValues)
                } else {
                    appState.liveActivityManager.stop(kind: kind)
                }
            }
        )
    }

    private func canMove(_ kind: MetricKind, by offset: Int) -> Bool {
        let priority = appState.settings.settings.liveActivityPriority
        guard let index = priority.firstIndex(of: kind) else { return false }
        let target = index + offset
        return target >= 0 && target < priority.count
    }

    private func move(_ kind: MetricKind, by offset: Int) {
        appState.settings.update { settings in
            guard let index = settings.liveActivityPriority.firstIndex(of: kind) else { return }
            let target = index + offset
            guard target >= 0 && target < settings.liveActivityPriority.count else { return }
            settings.liveActivityPriority.swapAt(index, target)
        }
    }
}