import SwiftUI
import Charts

/// Battery hub: current status, charging session, history, sessions,
/// and the honest "health is restricted" explanation.
struct BatteryView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                statusCard
                chargingCard
                dischargeCard
                historyCard
                sessionsCard
                healthCard
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Battery")
    }

    private var system: SystemMonitor { appState.systemMonitor }

    private var statusCard: some View {
        SectionCard(title: "Status", symbol: "battery.100percent") {
            HStack(spacing: 16) {
                Gauge(value: (system.battery.levelPercent ?? 0) / 100, in: 0...1) {
                    EmptyView()
                } currentValueLabel: {
                    Text(system.battery.levelPercent.map { String(format: "%.0f%%", $0) } ?? "—")
                        .font(.caption)
                        .monospacedDigit()
                }
                .gaugeStyle(.accessoryCircular)
                .tint(batteryTint)
                .frame(width: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text(system.battery.levelPercent.map { String(format: "%.0f%%", $0) } ?? "Unavailable")
                        .font(.title.weight(.semibold))
                        .monospacedDigit()
                    Label(system.charging.isCharging ? "Charging" : "Not charging", systemImage: system.charging.isCharging ? "bolt.fill" : "plug")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if system.battery.isLowPowerMode {
                        Label("Low Power Mode", systemImage: "leaf")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
            }
            DetailLine(text: "Source: UIDevice public API.")
                .padding(.top, 4)
        }
    }

    private var batteryTint: Color {
        guard let level = system.battery.levelPercent else { return .secondary }
        if level <= 20 { return .red }
        if level <= 50 { return .orange }
        return .green
    }

    private var chargingCard: some View {
        SectionCard(title: "Charging", symbol: "bolt.fill") {
            LabeledRow(label: "Charging", value: system.charging.isCharging ? "Yes" : "No")
            LabeledRow(label: "Session started", value: Formatters.time(system.charging.sessionStart))
            LabeledRow(label: "Level at start", value: system.charging.sessionStartLevel.map { String(format: "%.0f%%", $0) } ?? "—")
            LabeledRow(label: "Level now", value: system.charging.currentLevel.map { String(format: "%.0f%%", $0) } ?? "—")
            LabeledRow(label: "Estimated rate", value: system.charging.ratePer10Minutes.map { String(format: "+%.1f%% / 10 min", $0) } ?? "measuring…")
            LabeledRow(label: "Duration", value: system.charging.chargingDuration?.durationLabel ?? "—")
            LabeledRow(label: "Thermal (charging)", value: system.charging.thermalDuringCharging ?? "—")
            LabeledRow(label: "Exact wattage", value: "Unavailable")
            DetailLine(text: "iOS does not expose exact charger wattage to third-party apps. The rate above is a DeviceLab estimate from level deltas.")
                .padding(.top, 4)
        }
    }

    private var dischargeCard: some View {
        SectionCard(title: "Power estimate", symbol: "bolt.circle") {
            LabeledRow(label: "Estimated discharge", value: system.power.dischargeRatePerHour.map { String(format: "%.1f%% / hour", $0) } ?? "measuring…")
            if system.power.estimateWindowMinutes > 0 {
                LabeledRow(label: "Window", value: "\(Int(system.power.estimateWindowMinutes)) min · \(system.power.sampleCount) samples")
            }
            DetailLine(text: "Derived from DeviceLab's own battery history — an estimate, not an Apple power metric.")
                .padding(.top, 4)
        }
    }

    private var historyCard: some View {
        SectionCard(title: "Battery history", subtitle: "24 h") {
            let samples = appState.historyStore.batterySamples(since: Date().addingTimeInterval(-86_400))
            if samples.isEmpty {
                Text("No battery history yet — DeviceLab records levels while monitoring runs.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Chart(samples, id: \.persistentModelID) { sample in
                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Level", sample.level)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.tint)
                }
                .frame(height: 120)
                HStack {
                    Text("Estimated discharge rate: \(system.power.dischargeRatePerHour.map { String(format: "%.1f%% / hr", $0) } ?? "—")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }

    private var sessionsCard: some View {
        SectionCard(title: "Charging sessions", symbol: "clock") {
            let sessions = appState.historyStore.chargingSessions()
            if sessions.isEmpty {
                Text("No charging sessions recorded yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sessions.prefix(10), id: \.persistentModelID) { session in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Formatters.timeShort(session.start))
                                .font(.subheadline)
                            Text(session.end.map { Formatters.timeShort($0) } ?? "ongoing")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text("\(session.startLevel.map { Int($0) } ?? 0)% → \(session.endLevel.map { Int($0) } ?? 0)%")
                            .font(.subheadline.monospacedDigit())
                        if let peak = session.peakLevel {
                            Text("peak \(Int(peak))%")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var healthCard: some View {
        SectionCard(title: "Battery Health", symbol: "heart.text.square") {
            Label("Not exposed to third-party apps", systemImage: "lock.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            DetailLine(text: "Apple does not provide battery health, maximum capacity, or cycle count to third-party apps through public APIs.")
                .padding(.vertical, 4)
            DetailLine(text: "DeviceLab instead tracks what it legitimately can: charging sessions, estimated energy throughput, and level history.")
            Button("Open Settings → Battery → Battery Health") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.subheadline)
            .padding(.top, 6)
        }
    }
}