import SwiftUI

/// Network diagnostics: full probe + throughput test with honest labels.
struct NetworkTestView: View {
    @Environment(AppState.self) private var appState

    private var engine: NetworkDiagnosticsEngine {
        appState.networkDiagnostics
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    if engine.isRunning {
                        ProgressView("Running \(phaseLabel)")
                    } else {
                        Button {
                            Task { await engine.runFullTest() }
                        } label: {
                            Label("Run full network test", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            Task { await engine.runProbeOnly() }
                        } label: {
                            Label("Probe only (latency)", systemImage: "bolt")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    if let error = engine.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            } footer: {
                Text("Throughput is measured by transferring real payloads to public endpoints. Latency is a TCP-handshake approximation — ICMP ping is not available to sandboxed apps.")
            }

            Section("Latency") {
                LabeledRow(label: "Latency", value: engine.probe.latencyMs.map { String(format: "%.0f ms", $0) } ?? "—")
                LabeledRow(label: "Jitter", value: engine.probe.jitterMs.map { String(format: "%.0f ms", $0) } ?? "—")
                LabeledRow(label: "Packet loss", value: engine.probe.packetLossPercent.map { String(format: "%.0f%%", $0) } ?? "—")
                LabeledRow(label: "DNS estimate", value: engine.probe.dnsEstimateMs.map { String(format: "%.0f ms", $0) } ?? "—")
            }

            Section("Throughput") {
                LabeledRow(label: "Download", value: engine.speed.downMbps.map { String(format: "%.0f Mbps", $0) } ?? "—")
                LabeledRow(label: "Upload", value: engine.speed.upMbps.map { String(format: "%.0f Mbps", $0) } ?? "—")
                LabeledRow(label: "Payload down", value: engine.speed.downBytes > 0 ? "\(Int(engine.speed.downBytes / 1_048_576)) MB" : "—")
                LabeledRow(label: "Payload up", value: engine.speed.upBytes > 0 ? "\(Int(engine.speed.upBytes / 1_048_576)) MB" : "—")
            }

            Section("Interface") {
                LabeledRow(label: "Status", value: appState.systemMonitor.network.connectivityLabel ?? "—")
                LabeledRow(label: "Interface", value: appState.systemMonitor.network.interfaceLabel ?? "—")
                LabeledRow(label: "IPv4", value: appState.systemMonitor.network.supportsIPv4 ? "Supported" : "No")
                LabeledRow(label: "IPv6", value: appState.systemMonitor.network.supportsIPv6 ? "Supported" : "No")
            }
        }
        .navigationTitle("Network Test")
    }

    private var phaseLabel: String {
        switch engine.phase {
        case .latency: return "latency…"
        case .download: return "download…"
        case .upload: return "upload…"
        default: return "…"
        }
    }
}