import Foundation
import ActivityKit

// MARK: - Shared Live Activity model
//
// Compiled into BOTH the app target and the widget extension target.
// One attribute type with a kind discriminator allows multiple
// independent Live Activities (CPU, battery, charging, summary, …) to
// coexist, using ActivityKit's built-in rules for Dynamic Island
// presentation and relevance scores.

enum DeviceLabActivityKind: String, Codable, Hashable, Sendable {
    case cpu
    case memory
    case gpu
    case battery
    case charging
    case thermal
    case network
    case device

    var displayName: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .gpu: return "GPU"
        case .battery: return "Battery"
        case .charging: return "Charging"
        case .thermal: return "Thermal"
        case .network: return "Network"
        case .device: return "Device Summary"
        }
    }

    var symbolName: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .gpu: return "cpu.fill"
        case .battery: return "battery.100percent"
        case .charging: return "bolt.fill"
        case .thermal: return "thermometer.medium"
        case .network: return "wifi"
        case .device: return "iphone"
        }
    }
}

struct DeviceLabLiveActivityAttributes: ActivityAttributes {
    let kind: DeviceLabActivityKind
}

struct DeviceLabLiveActivityContentState: Codable, Hashable, Sendable {
    var cpuPercent: Double?
    var memoryAvailableGB: Double?
    var memoryFootprintMB: Double?
    var storageFreeGB: Double?
    var batteryLevel: Double?
    var isCharging: Bool?
    var chargeRatePer10min: Double?
    var thermalState: String?
    var networkLatencyMs: Double?
    var networkDownMbps: Double?
    var networkUpMbps: Double?
    var gpuLabel: String?
    var updatedAt: Date?
}

/// Snapshot values bridging the app's monitoring to Live Activities.
struct LiveMetricValues: Sendable, Equatable {
    var cpuPercent: Double?
    var ownCPUPercent: Double?
    var memoryAvailableGB: Double?
    var memoryFootprintMB: Double?
    var storageFreeGB: Double?
    var storageTotalGB: Double?
    var batteryLevel: Double?
    var isCharging: Bool?
    var chargeRatePerHour: Double?
    var thermalStateRaw: String?
    var networkStatus: String?
    var networkLatencyMs: Double?
    var networkDownMbps: Double?
    var networkUpMbps: Double?
    var gpuLabel: String?
    var isLowPowerMode: Bool?
    var updatedAt: Date?

    func contentState(for kind: DeviceLabActivityKind) -> DeviceLabLiveActivityContentState {
        DeviceLabLiveActivityContentState(
            cpuPercent: cpuPercent,
            memoryAvailableGB: memoryAvailableGB,
            memoryFootprintMB: memoryFootprintMB,
            storageFreeGB: storageFreeGB,
            batteryLevel: batteryLevel,
            isCharging: isCharging,
            chargeRatePer10min: chargeRatePerHour.map { $0 / 6 },
            thermalState: thermalStateRaw,
            networkLatencyMs: networkLatencyMs,
            networkDownMbps: networkDownMbps,
            networkUpMbps: networkUpMbps,
            gpuLabel: gpuLabel,
            updatedAt: updatedAt
        )
    }

    func summaryLine() -> String {
        var parts: [String] = []
        if let cpuPercent { parts.append("CPU \(Int(cpuPercent))%") }
        if let memoryAvailableGB { parts.append(String(format: "RAM %.1fG", memoryAvailableGB)) }
        if let batteryLevel { parts.append("BAT \(Int(batteryLevel))%") }
        return parts.joined(separator: " ")
    }
}