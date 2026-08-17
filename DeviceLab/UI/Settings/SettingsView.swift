import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            List {
                monitoringSection
                backgroundSection
                liveActivitiesLink
                benchmarkSection
                appearanceSection
                hapticsSection
                notificationsSection
                batteryAndReports
                privacySection
                aboutSection
            }
            .navigationTitle("Settings")
        }
        .onAppear {
            Task {
                _ = await appState.notificationService.requestAuthorization()
            }
        }
    }

    private var monitoringSection: some View {
        Section("Monitoring") {
            ForEach(appState.systemMonitor.allMonitors, id: \.kind) { monitor in
                Toggle(isOn: Binding(
                    get: { appState.settings.isMonitoringEnabled(monitor.kind) },
                    set: { newValue in
                        appState.settings.update { $0.monitoringEnabled[monitor.kind] = newValue }
                        appState.systemMonitor.restartIfNeeded()
                    }
                )) {
                    Label(monitor.kind.displayName, systemImage: monitor.kind.symbolName)
                }
            }
        }
    }

    private var backgroundSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { appState.settings.settings.backgroundRefreshEnabled },
                set: { newValue in
                    appState.settings.update { $0.backgroundRefreshEnabled = newValue }
                    if newValue {
                        appState.backgroundScheduler.scheduleAppRefresh()
                    } else {
                        appState.backgroundScheduler.cancelScheduledRefresh()
                    }
                }
            )) {
                Label("Background refresh", systemImage: "arrow.clockwise.icloud")
            }
            LabeledRow(label: "Last system refresh", value: Formatters.timeShort(appState.backgroundScheduler.lastBackgroundRefresh))
            DetailLine(text: "iOS schedules background refreshes; DeviceLab never runs background loops.")
        } header: {
            Text("Background")
        } footer: {
            Text(appState.backgroundScheduler.statusMessage)
        }
    }

    private var liveActivitiesLink: some View {
        Section {
            NavigationLink {
                LiveActivitiesSettingsView()
            } label: {
                Label("Live Activities & Dynamic Island", systemImage: "rectangle.inset.filled.and.person.filled")
            }
        }
    }

    private var benchmarkSection: some View {
        Section {
            Stepper(value: Binding(
                get: { Double(appState.settings.settings.cpuBenchmarkDuration) },
                set: { newValue in appState.settings.update { $0.cpuBenchmarkDuration = newValue } }
            ), in: 2...15, step: 1) {
                LabeledRow(label: "CPU test duration", value: "\(Int(appState.settings.settings.cpuBenchmarkDuration)) s")
            }
            Stepper(value: Binding(
                get: { Double(appState.settings.settings.gpuBenchmarkDuration) },
                set: { newValue in appState.settings.update { $0.gpuBenchmarkDuration = newValue } }
            ), in: 2...15, step: 1) {
                LabeledRow(label: "GPU test duration", value: "\(Int(appState.settings.settings.gpuBenchmarkDuration)) s")
            }
            Stepper(value: Binding(
                get: { Double(appState.settings.settings.storageBenchmarkSizeMB) },
                set: { newValue in appState.settings.update { $0.storageBenchmarkSizeMB = Int(newValue) } }
            ), in: 100...1000, step: 100) {
                LabeledRow(label: "Storage test size", value: "\(appState.settings.settings.storageBenchmarkSizeMB) MB")
            }
            Toggle(isOn: Binding(
                get: { appState.settings.settings.thermalSafeguardEnabled },
                set: { newValue in appState.settings.update { $0.thermalSafeguardEnabled = newValue } }
            )) {
                Label("Thermal safeguard", systemImage: "thermometer")
            }
            Toggle(isOn: Binding(
                get: { appState.settings.settings.autoCleanupBenchmarkFiles },
                set: { newValue in appState.settings.update { $0.autoCleanupBenchmarkFiles = newValue } }
            )) {
                Label("Auto-cleanup temporary files", systemImage: "trash")
            }
        } header: {
            Text("Benchmark")
        } footer: {
            Text("Storage benchmarks clamp the test size to a fraction of free space and always delete temporary files.")
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: Binding(
                get: { appState.settings.settings.appearance },
                set: { newValue in appState.settings.update { $0.appearance = newValue } }
            )) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var hapticsSection: some View {
        Section("Haptics") {
            Toggle(isOn: Binding(
                get: { appState.settings.settings.hapticsEnabled },
                set: { newValue in appState.settings.update { $0.hapticsEnabled = newValue } }
            )) {
                Label("Master haptic switch", systemImage: "waveform.path")
            }
            Toggle(isOn: Binding(
                get: { appState.settings.settings.diagnosticHaptics },
                set: { newValue in appState.settings.update { $0.diagnosticHaptics = newValue } }
            )) {
                Label("Diagnostic haptics", systemImage: "iphone")
            }
        }
    }

    private var notificationsSection: some View {
        Section("Notifications") {
            Toggle(isOn: Binding(
                get: { appState.settings.settings.notifyBatteryThresholdEnabled },
                set: { newValue in appState.settings.update { $0.notifyBatteryThresholdEnabled = newValue } }
            )) {
                Label("Battery threshold", systemImage: "battery.25percent")
            }
            if appState.settings.settings.notifyBatteryThresholdEnabled {
                Stepper(value: Binding(
                    get: { Double(appState.settings.settings.batteryThresholdPercent) },
                    set: { newValue in appState.settings.update { $0.batteryThresholdPercent = Int(newValue) } }
                ), in: 5...50, step: 5) {
                    LabeledRow(label: "Threshold", value: "\(appState.settings.settings.batteryThresholdPercent)%")
                }
            }
            Toggle(isOn: Binding(
                get: { appState.settings.settings.notifyThermalWarning },
                set: { newValue in appState.settings.update { $0.notifyThermalWarning = newValue } }
            )) {
                Label("Thermal warning", systemImage: "thermometer.high")
            }
            Toggle(isOn: Binding(
                get: { appState.settings.settings.notifyChargingComplete },
                set: { newValue in appState.settings.update { $0.notifyChargingComplete = newValue } }
            )) {
                Label("Charging complete", systemImage: "bolt.badge.checkmark")
            }
            Toggle(isOn: Binding(
                get: { appState.settings.settings.notifyDiagnosticComplete },
                set: { newValue in appState.settings.update { $0.notifyDiagnosticComplete = newValue } }
            )) {
                Label("Diagnostic complete", systemImage: "checkmark.seal")
            }
            Toggle(isOn: Binding(
                get: { appState.settings.settings.notifyBenchmarkComplete },
                set: { newValue in appState.settings.update { $0.notifyBenchmarkComplete = newValue } }
            )) {
                Label("Benchmark complete", systemImage: "flag.checkered")
            }
        }
    }

    private var batteryAndReports: some View {
        Section {
            NavigationLink {
                BatteryView()
            } label: {
                Label("Battery details", systemImage: "battery.100percent")
            }
            NavigationLink {
                ReportsView()
            } label: {
                Label("Reports & export", systemImage: "doc.richtext")
            }
        }
    }

    private var privacySection: some View {
        Section {
            NavigationLink {
                PrivacyView()
            } label: {
                Label("Privacy", systemImage: "hand.raised")
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledRow(label: "App", value: "DeviceLab 1.0")
            LabeledRow(label: "Device", value: appState.deviceInfo.marketingName)
            LabeledRow(label: "Model", value: appState.deviceInfo.modelIdentifier)
            LabeledRow(label: "OS", value: appState.deviceInfo.osLabel)
            LabeledRow(label: "Cores", value: "\(appState.deviceInfo.processorCount)")
            LabeledRow(label: "RAM", value: String(format: "%.1f GB", appState.deviceInfo.memoryGB))
            DetailLine(text: "Local-first: no account, no server, no telemetry, no analytics.")
                .padding(.top, 4)
        }
    }
}