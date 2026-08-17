import SwiftUI

struct MonitoringView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Monitoring profile", selection: profileBinding) {
                        ForEach(MonitoringProfile.allCases) { profile in
                            Text(profile.displayName).tag(profile)
                        }
                    }
                    .pickerStyle(.segmented)

                    LabeledContent("Polling interval", value: appState.settings.settings.effectiveInterval.displayName + " · " + appState.settings.settings.effectiveInterval.detail)
                } header: {
                    Text("Monitoring engine")
                } footer: {
                    Text("Battery Saver lowers polling, reduces animations and minimizes Live Activity updates. Fast polling is only used when selected.")
                }

                Section("Monitors") {
                    ForEach(appState.systemMonitor.allMonitors, id: \.kind) { monitor in
                        NavigationLink(value: monitor.kind) {
                            HStack {
                                Image(systemName: monitor.kind.symbolName)
                                    .foregroundStyle(.tint)
                                Text(monitor.kind.displayName)
                                Spacer()
                                Text(appState.systemMonitor.snapshot(for: monitor.kind).valueText)
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Button {
                        if appState.systemMonitor.isRunning {
                            appState.systemMonitor.stopMonitoring()
                        } else {
                            appState.systemMonitor.startMonitoring()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Label(
                                appState.systemMonitor.isRunning ? "Stop monitoring" : "Start monitoring",
                                systemImage: appState.systemMonitor.isRunning ? "stop.circle.fill" : "play.circle.fill"
                            )
                            Spacer()
                        }
                    }
                    .foregroundStyle(appState.systemMonitor.isRunning ? .red : .green)
                } footer: {
                    if let updated = appState.systemMonitor.lastUpdated {
                        Text("Last update: \(Formatters.time(updated)) · Samples: \(appState.systemMonitor.sampleCount)")
                    } else {
                        Text("Monitoring not started yet.")
                    }
                }
            }
            .navigationTitle("Monitor")
            .navigationDestination(for: MetricKind.self) { kind in
                MonitorDetailView(kind: kind)
            }
        }
        .onChange(of: appState.settings.settings.monitoringProfile) {
            appState.systemMonitor.restartIfNeeded()
        }
        .onChange(of: appState.settings.settings.updateInterval) {
            appState.systemMonitor.restartIfNeeded()
        }
    }

    private var profileBinding: Binding<MonitoringProfile> {
        Binding(
            get: { appState.settings.settings.monitoringProfile },
            set: { newValue in
                appState.settings.update { $0.monitoringProfile = newValue }
            }
        )
    }
}