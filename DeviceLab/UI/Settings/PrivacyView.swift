import SwiftUI

struct PrivacyView: View {
    var body: some View {
        List {
            Section("DeviceLab is local-first") {
                LabeledRow(label: "Server", value: "None")
                LabeledRow(label: "Account", value: "None")
                LabeledRow(label: "Telemetry", value: "None")
                LabeledRow(label: "Analytics", value: "None (off by default, no option to enable)")
                LabeledRow(label: "Cloud dependency", value: "None")
            }

            Section("What stays on device") {
                DetailLine(text: "All measurements, battery history, charging sessions, benchmark results and reports are stored only in DeviceLab's local database inside its sandbox.")
                DetailLine(text: "Reports are exported only when you explicitly tap Export and choose a destination (AirDrop, Files, Mail…).")
            }

            Section("Permissions DeviceLab may request") {
                permissionRow("Camera", "Camera diagnostics (preview, capture, video, torch).")
                permissionRow("Microphone", "Microphone level metering and noise-floor checks.")
                permissionRow("Motion sensors", "Accelerometer, gyroscope, magnetometer, barometer, pedometer diagnostics.")
                permissionRow("Notifications", "Optional battery/thermal/charging alerts. All opt-in.")
                permissionRow("Background refresh", "System-scheduled refresh to keep the last-known measurement current. iOS decides when it runs.")
            }

            Section("What DeviceLab never does") {
                DetailLine(text: "Never reads other apps' data, never scans protected directories, never uploads diagnostics, never abuses background execution, never uses private APIs.")
            }
        }
        .navigationTitle("Privacy")
    }

    private func permissionRow(_ name: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.subheadline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}