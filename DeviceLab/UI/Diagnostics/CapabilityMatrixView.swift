import SwiftUI
import ActivityKit
import CoreMotion
import Metal
import UIKit

/// Transparency screen: exactly what iOS allows DeviceLab to measure.
/// Availability is validated against the running SDK/OS at runtime.
struct CapabilityMatrixView: View {
    var body: some View {
        List {
            Section {
                Label("Every displayed value has a provenance: Public API, System reported, Measured by DeviceLab, Estimate, or Restricted. Nothing is fabricated.", systemImage: "checkmark.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Capability matrix") {
                ForEach(rows, id: \.metric) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.metric)
                            .font(.subheadline)
                        HStack {
                            Text("DeviceLab: \(row.deviceLab)")
                                .font(.caption)
                                .foregroundStyle(row.deviceLabTint)
                            Spacer()
                            Text("Other apps: \(row.otherApps)")
                                .font(.caption)
                                .foregroundStyle(row.otherAppsTint)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("Checked at runtime") {
                runtimeRow("Device battery level", available: UIDevice.current.batteryLevel >= 0)
                runtimeRow("Thermal state", available: true)
                runtimeRow("Live Activities", available: ActivityAuthorizationInfo().areActivitiesEnabled)
                runtimeRow("Core Motion sensors", available: CMMotionManager().isDeviceMotionAvailable)
                runtimeRow("Metal GPU", available: MTLCreateSystemDefaultDevice() != nil)
            }

            Section {
                Text("Restricted values are shown as “Unavailable” with an explanation — never as 0%, 0 MB or 0 W.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("What iOS Allows")
    }

    private func runtimeRow(_ label: String, available: Bool) -> some View {
        HStack {
            Text(label)
            Spacer()
            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(available ? .green : .red)
            Text(available ? "Yes" : "No")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private struct CapabilityRow {
        let metric: String
        let deviceLab: String
        let otherApps: String
        let deviceLabTint: Color
        let otherAppsTint: Color
    }

    private var rows: [CapabilityRow] {
        [
            CapabilityRow(metric: "Device battery %", deviceLab: "YES", otherApps: "N/A", deviceLabTint: .green, otherAppsTint: .secondary),
            CapabilityRow(metric: "Thermal state", deviceLab: "YES", otherApps: "N/A", deviceLabTint: .green, otherAppsTint: .secondary),
            CapabilityRow(metric: "DeviceLab CPU (own process)", deviceLab: "YES", otherApps: "No unrestricted", deviceLabTint: .green, otherAppsTint: .red),
            CapabilityRow(metric: "DeviceLab GPU (own workload)", deviceLab: "YES", otherApps: "No unrestricted", deviceLabTint: .green, otherAppsTint: .red),
            CapabilityRow(metric: "DeviceLab memory (own footprint)", deviceLab: "YES", otherApps: "No unrestricted", deviceLabTint: .green, otherAppsTint: .red),
            CapabilityRow(metric: "DeviceLab power metrics", deviceLab: "YES, where supported", otherApps: "No", deviceLabTint: .green, otherAppsTint: .red),
            CapabilityRow(metric: "Arbitrary app CPU", deviceLab: "NO", otherApps: "Restricted", deviceLabTint: .red, otherAppsTint: .orange),
            CapabilityRow(metric: "Arbitrary app GPU", deviceLab: "NO", otherApps: "Restricted", deviceLabTint: .red, otherAppsTint: .orange),
            CapabilityRow(metric: "Arbitrary app RAM", deviceLab: "NO", otherApps: "Restricted", deviceLabTint: .red, otherAppsTint: .orange),
            CapabilityRow(metric: "Apple per-app battery attribution", deviceLab: "NO", otherApps: "Restricted", deviceLabTint: .red, otherAppsTint: .orange),
            CapabilityRow(metric: "Exact charger watts", deviceLab: "Only if public API", otherApps: "N/A", deviceLabTint: .orange, otherAppsTint: .secondary),
            CapabilityRow(metric: "Battery cycle count", deviceLab: "Only if public API", otherApps: "N/A", deviceLabTint: .orange, otherAppsTint: .secondary),
            CapabilityRow(metric: "Battery health", deviceLab: "Only if public API", otherApps: "N/A", deviceLabTint: .orange, otherAppsTint: .secondary),
        ]
    }
}