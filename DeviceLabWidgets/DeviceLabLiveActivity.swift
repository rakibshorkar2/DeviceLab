import ActivityKit
import WidgetKit
import SwiftUI

/// Live Activity: Lock Screen + Dynamic Island presentations.
/// Content is fully driven by the shared attributes/content state.
struct DeviceLabLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DeviceLabLiveActivityAttributes.self) { context in
            LiveActivityLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ActivityIcon(kind: context.attributes.kind)
                }
                DynamicIslandExpandedRegion(.center) {
                    ActivityPrimaryLine(kind: context.attributes.kind, state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivitySecondaryLine(kind: context.attributes.kind, state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ActivityDetailLine(kind: context.attributes.kind, state: context.state)
                        .padding(.top, 4)
                }
            } compactLeading: {
                ActivityIcon(kind: context.attributes.kind)
            } compactTrailing: {
                ActivityCompactValue(kind: context.attributes.kind, state: context.state)
            } minimal: {
                ActivityIcon(kind: context.attributes.kind)
            }
        }
    }
}

// MARK: - Lock screen

struct LiveActivityLockScreenView: View {
    let context: ActivityViewContext<DeviceLabLiveActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            ActivityIcon(kind: context.attributes.kind)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.kind.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ActivityPrimaryLine(kind: context.attributes.kind, state: context.state)
                    .font(.headline)
            }
            Spacer()
            ActivitySecondaryLine(kind: context.attributes.kind, state: context.state)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .activityBackgroundTint(.cyan.opacity(0.2))
        .activitySystemActionForegroundColor(.black)
    }
}

// MARK: - Content builders (shared between lock screen and Dynamic Island)

struct ActivityIcon: View {
    let kind: DeviceLabActivityKind

    var body: some View {
        Image(systemName: kind.symbolName)
            .symbolRenderingMode(.hierarchical)
    }
}

struct ActivityPrimaryLine: View {
    let kind: DeviceLabActivityKind
    let state: DeviceLabLiveActivityContentState

    var body: some View {
        Text(primaryText)
    }

    private var primaryText: String {
        switch kind {
        case .cpu:
            return state.cpuPercent.map { String(format: "%.0f%%", $0) } ?? "—"
        case .memory:
            return state.memoryAvailableGB.map { String(format: "%.1f GB free", $0) } ?? "—"
        case .gpu:
            return state.gpuLabel ?? "Measured"
        case .battery:
            return state.batteryLevel.map { String(format: "%.0f%%", $0) } ?? "—"
        case .charging:
            return state.batteryLevel.map { String(format: "⚡ %.0f%%", $0) } ?? "—"
        case .thermal:
            return state.thermalState ?? "—"
        case .network:
            return state.networkLatencyMs.map { String(format: "%.0f ms", $0) } ?? "—"
        case .device:
            return state.cpuPercent.map { "CPU \(String(format: "%.0f", $0))%" } ?? "CPU —"
        }
    }
}

struct ActivitySecondaryLine: View {
    let kind: DeviceLabActivityKind
    let state: DeviceLabLiveActivityContentState

    var body: some View {
        Text(secondaryText)
    }

    private var secondaryText: String {
        switch kind {
        case .cpu:
            return state.cpuPercent.map { String(format: "App %.0f%%", $0) } ?? ""
        case .memory:
            return state.memoryFootprintMB.map { String(format: "App %.0f MB", $0) } ?? ""
        case .gpu:
            return "Metal"
        case .battery:
            return (state.isCharging == true) ? "Charging" : "Battery"
        case .charging:
            return state.chargeRatePer10min.map { String(format: "+%.1f%%/10m", $0) } ?? "Charging"
        case .thermal:
            return "Thermal"
        case .network:
            return state.networkDownMbps.map { String(format: "%.0f Mbps", $0) } ?? ""
        case .device:
            var parts: [String] = []
            if let memory = state.memoryAvailableGB { parts.append(String(format: "RAM %.1fG", memory)) }
            if let battery = state.batteryLevel { parts.append(String(format: "BAT %.0f%%", battery)) }
            return parts.joined(separator: " · ")
        }
    }
}

struct ActivityDetailLine: View {
    let kind: DeviceLabActivityKind
    let state: DeviceLabLiveActivityContentState

    var body: some View {
        HStack(spacing: 8) {
            Text(detailText)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let updated = state.updatedAt {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var detailText: String {
        switch kind {
        case .cpu:
            return state.storageFreeGB.map { "Storage \(String(format: "%.0f", $0)) GB free" } ?? ""
        case .memory:
            return state.storageFreeGB.map { "Storage \(String(format: "%.0f", $0)) GB free" } ?? ""
        case .charging:
            return state.thermalState.map { "Thermal: \($0)" } ?? ""
        case .network:
            return state.networkUpMbps.map { "↑ \(String(format: "%.0f", $0)) Mbps" } ?? ""
        case .device:
            return state.thermalState.map { "Thermal: \($0)" } ?? ""
        default:
            return ""
        }
    }
}

/// Compact (Dynamic Island collapsed / minimal) value.
struct ActivityCompactValue: View {
    let kind: DeviceLabActivityKind
    let state: DeviceLabLiveActivityContentState

    var body: some View {
        Text(text)
            .font(.caption2)
            .monospacedDigit()
    }

    private var text: String {
        switch kind {
        case .cpu:
            return state.cpuPercent.map { String(format: "%.0f%%", $0) } ?? "—"
        case .memory:
            return state.memoryAvailableGB.map { String(format: "%.1fG", $0) } ?? "—"
        case .battery, .charging:
            return state.batteryLevel.map { String(format: "%.0f%%", $0) } ?? "—"
        case .gpu:
            return state.gpuLabel ?? "GPU"
        case .thermal:
            return state.thermalState?.prefix(1).uppercased() ?? "—"
        case .network:
            return state.networkLatencyMs.map { String(format: "%.0f", $0) } ?? "—"
        case .device:
            return state.batteryLevel.map { String(format: "%.0f%%", $0) } ?? "—"
        }
    }
}