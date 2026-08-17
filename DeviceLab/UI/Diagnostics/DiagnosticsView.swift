import SwiftUI

struct DiagnosticsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        FullDiagnosticView()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Full Device Check", systemImage: "checklist")
                                .font(.headline)
                            Text("Runs every automatic test and pauses for interactive hardware tests.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Hardware tests") {
                    NavigationLink { DisplayTestView() } label: { testRow("Display", "display") }
                    NavigationLink { TouchTestView() } label: { testRow("Touch", "hand.tap") }
                    NavigationLink { SensorTestView() } label: { testRow("Sensors", "sensor.tag.radiowaves.forward") }
                    NavigationLink { CameraTestView() } label: { testRow("Camera", "camera") }
                    NavigationLink { AudioTestView() } label: { testRow("Microphone & Speaker", "waveform") }
                    NavigationLink { HapticTestView() } label: { testRow("Haptics", "iphone.radiowaves.left.and.right") }
                    NavigationLink { NetworkTestView() } label: { testRow("Network", "wifi") }
                }

                Section {
                    NavigationLink {
                        CapabilityMatrixView()
                    } label: {
                        testRow("What iOS allows", "info.circle")
                    }
                } footer: {
                    Text("DeviceLab only measures what public iOS APIs allow. Restricted system-wide metrics are labeled as such.")
                }
            }
            .navigationTitle("Diagnostics")
        }
    }

    private func testRow(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .padding(.vertical, 2)
    }
}