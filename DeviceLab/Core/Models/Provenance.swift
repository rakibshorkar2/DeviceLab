import Foundation

// MARK: - Provenance
//
// Every displayed value in DeviceLab is classified by how it was obtained.
// This is the backbone of the "NO FAKE DATA" principle.

enum Provenance: String, Codable, Sendable {
    case directPublicAPI = "DIRECT_PUBLIC_API"
    case measuredByDeviceLab = "MEASURED_BY_DEVICELAB"
    case systemReported = "SYSTEM_REPORTED"
    case derivedEstimate = "DERIVED_ESTIMATE"
    case unavailableOnStockiOS = "UNAVAILABLE_ON_STOCK_IOS"

    var displayName: String {
        switch self {
        case .directPublicAPI: return "Public API"
        case .measuredByDeviceLab: return "Measured by DeviceLab"
        case .systemReported: return "System reported"
        case .derivedEstimate: return "DeviceLab estimate"
        case .unavailableOnStockiOS: return "Unavailable on stock iOS"
        }
    }

    var shortLabel: String {
        switch self {
        case .directPublicAPI: return "PUBLIC API"
        case .measuredByDeviceLab: return "DEVICELAB"
        case .systemReported: return "SYSTEM"
        case .derivedEstimate: return "ESTIMATE"
        case .unavailableOnStockiOS: return "RESTRICTED"
        }
    }
}

// MARK: - Metric kinds

enum MetricKind: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case cpu
    case memory
    case gpu
    case storage
    case battery
    case charging
    case thermal
    case network
    case power
    case device

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .gpu: return "GPU"
        case .storage: return "Storage"
        case .battery: return "Battery"
        case .charging: return "Charging"
        case .thermal: return "Thermal"
        case .network: return "Network"
        case .power: return "Power"
        case .device: return "Device"
        }
    }

    var symbolName: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .gpu: return "cpu.fill"
        case .storage: return "internaldrive"
        case .battery: return "battery.100percent"
        case .charging: return "bolt.fill"
        case .thermal: return "thermometer.medium"
        case .network: return "wifi"
        case .power: return "bolt.circle"
        case .device: return "iphone"
        }
    }
}

// MARK: - Metric status

enum MetricStatus: Equatable, Sendable {
    case normal
    case warning
    case critical
    case inactive
    case unavailable(String)

    var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }

    var title: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "Warning"
        case .critical: return "Critical"
        case .inactive: return "Inactive"
        case .unavailable: return "Unavailable"
        }
    }
}

// MARK: - Monitor availability

enum MonitorAvailability: Equatable, Sendable {
    case available
    case unavailable(String)
    case permissionRequired(String)
    case temporarilyUnavailable(String)
    case notSupported(String)
    case error(String)

    var isAvailable: Bool { self == .available }

    var displayLabel: String {
        switch self {
        case .available: return "Available"
        case .unavailable(let reason): return "Unavailable — \(reason)"
        case .permissionRequired(let reason): return "Permission required — \(reason)"
        case .temporarilyUnavailable(let reason): return "Temporarily unavailable — \(reason)"
        case .notSupported(let reason): return "Not supported — \(reason)"
        case .error(let reason): return "Error — \(reason)"
        }
    }
}

// MARK: - Metric snapshot

/// A single point-in-time snapshot of one metric.
/// `valueText`/`subtext` are pre-formatted for display; `numericValue` is for charts.
struct MetricSnapshot: Identifiable, Equatable, Sendable {
    let kind: MetricKind
    var valueText: String
    var subtext: String
    var detail: String
    var status: MetricStatus
    var provenance: Provenance
    var updatedAt: Date?
    var numericValue: Double?
    var unit: String

    var id: MetricKind { kind }

    static func unavailable(kind: MetricKind, reason: String) -> MetricSnapshot {
        MetricSnapshot(
            kind: kind,
            valueText: "Unavailable",
            subtext: reason,
            detail: reason,
            status: .unavailable(reason),
            provenance: .unavailableOnStockiOS,
            updatedAt: nil,
            numericValue: nil,
            unit: ""
        )
    }

    static func placeholder(kind: MetricKind) -> MetricSnapshot {
        MetricSnapshot(
            kind: kind,
            valueText: "—",
            subtext: "Not started",
            detail: "Start monitoring to collect data.",
            status: .inactive,
            provenance: .measuredByDeviceLab,
            updatedAt: nil,
            numericValue: nil,
            unit: ""
        )
    }
}