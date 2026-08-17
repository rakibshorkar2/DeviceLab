import SwiftUI
import Charts

/// Detail view for a single metric: live value, badges, history chart,
/// provenance, and kind-specific extras (speed test, storage analyzer…).
struct MonitorDetailView: View {
    @Environment(AppState.self) private var appState
    let kind: MetricKind

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                currentValueCard
                historyCard
                extras
                provenanceCard
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(kind.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var snapshot: MetricSnapshot {
        appState.systemMonitor.snapshot(for: kind)
    }

    private var currentValueCard: some View {
        SectionCard(title: "Current", symbol: kind.symbolName) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.valueText)
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(snapshot.status.isUnavailable ? .secondary : .primary)
                    Text(snapshot.subtext)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(status: snapshot.status)
            }
        }
    }

    private var historyCard: some View {
        SectionCard(title: "History", subtitle: "last 24 h") {
            if samples.isEmpty {
                Text("No history yet — samples are recorded while monitoring runs.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                HistoryChartView(samples: samples, unit: snapshot.unit)
            }
        }
    }

    private var samples: [(date: Date, value: Double)] {
        appState.historyStore.measurements(kind: kind, since: Date().addingTimeInterval(-86_400))
            .map { (date: $0.timestamp, value: $0.value) }
    }

    @ViewBuilder
    private var extras: some View {
        switch kind {
        case .network:
            NetworkSpeedTestCard()
        case .storage:
            StorageAnalyzerCard()
        case .gpu:
            GPUCard()
        case .battery:
            BatteryDetailCard()
        default:
            EmptyView()
        }
    }

    private var provenanceCard: some View {
        SectionCard(title: "Source & details", symbol: "doc.text.magnifyingglass") {
            HStack {
                ProvenanceBadge(provenance: snapshot.provenance)
                Text(snapshot.provenance.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !snapshot.detail.isEmpty {
                Divider()
                Text(snapshot.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Kind-specific cards

struct NetworkSpeedTestCard: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        SectionCard(title: "Speed test", symbol: "speedometer") {
            let engine = appState.networkDiagnostics
            if engine.isRunning {
                ProgressView("Testing \(phaseLabel)")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if let down = engine.speed.downMbps {
                        LabeledRow(label: "Download", value: String(format: "%.0f Mbps", down))
                        LabeledRow(label: "Upload", value: engine.speed.upMbps.map { String(format: "%.0f Mbps", $0) } ?? "—")
                    }
                    if let latency = engine.probe.latencyMs {
                        LabeledRow(label: "Latency", value: String(format: "%.0f ms", latency))
                        LabeledRow(label: "Jitter", value: String(format: "%.0f ms", engine.probe.jitterMs ?? 0))
                        LabeledRow(label: "DNS estimate", value: engine.probe.dnsEstimateMs.map { String(format: "%.0f ms", $0) } ?? "—")
                    }
                    if let error = engine.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    Button("Run full network test") {
                        Task { await engine.runFullTest() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(engine.isRunning)
                }
            }
        }
    }

    private var phaseLabel: String {
        switch appState.networkDiagnostics.phase {
        case .latency: return "latency…"
        case .download: return "download…"
        case .upload: return "upload…"
        default: return "…"
        }
    }
}

struct StorageAnalyzerCard: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        SectionCard(title: "Storage analyzer", symbol: "internaldrive") {
            let monitor = appState.systemMonitor.storage
            LabeledRow(label: "Total", value: Formatters.gigabytes(Double(monitor.totalBytes)))
            LabeledRow(label: "Free", value: Formatters.gigabytes(Double(monitor.availableBytes)))
            Divider()
            LabeledRow(label: "DeviceLab documents", value: Formatters.megabytes(Double(monitor.documentsBytes)))
            LabeledRow(label: "DeviceLab caches", value: Formatters.megabytes(Double(monitor.cachesBytes)))
            LabeledRow(label: "DeviceLab temporary", value: Formatters.megabytes(Double(monitor.temporaryBytes)))
            LabeledRow(label: "Files (sandbox)", value: "\(monitor.fileCount)")
            DetailLine(text: "Only DeviceLab's own sandbox is scanned. Other apps' directories are protected by iOS.")
                .padding(.top, 4)
        }
    }
}

struct GPUCard: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        SectionCard(title: "GPU", symbol: "cpu.fill") {
            let gpu = appState.systemMonitor.gpu
            LabeledRow(label: "MetricKit GPU time", value: gpu.metricKitGPUTime.map { String(format: "%.2f s", $0) } ?? "No payload yet")
            LabeledRow(label: "Last benchmark", value: gpu.lastBenchmarkFPS.map { String(format: "%.0f FPS", $0) } ?? "Not run")
            DetailLine(text: "System-wide GPU attribution for other apps is not exposed by iOS public APIs.")
                .padding(.top, 4)
        }
    }
}

struct BatteryDetailCard: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        SectionCard(title: "Battery", symbol: "battery.100percent") {
            let system = appState.systemMonitor
            LabeledRow(label: "Level", value: system.battery.levelPercent.map { String(format: "%.0f%%", $0) } ?? "Unavailable")
            LabeledRow(label: "Charging", value: system.charging.isCharging ? "Yes" : "No")
            LabeledRow(label: "Charge rate", value: system.charging.ratePerHour.map { String(format: "+%.1f%%/hr", $0) } ?? "—")
            LabeledRow(label: "Discharge (est.)", value: system.power.dischargeRatePerHour.map { String(format: "%.1f%%/hr", $0) } ?? "—")
            LabeledRow(label: "Low Power Mode", value: system.battery.isLowPowerMode ? "On" : "Off")
            LabeledRow(label: "Health / cycle count", value: "Restricted")
            DetailLine(text: "Apple does not expose battery health, cycle count, or charger wattage to third-party apps.")
                .padding(.top, 4)
        }
    }
}