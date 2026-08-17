import Foundation
import Observation

// MARK: - Enumerated settings

enum UpdateInterval: String, Codable, CaseIterable, Sendable, Identifiable {
    case fast
    case balanced
    case efficient
    case background

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fast: return "Fast"
        case .balanced: return "Balanced"
        case .efficient: return "Efficient"
        case .background: return "Background"
        }
    }

    var detail: String {
        switch self {
        case .fast: return "1 sec"
        case .balanced: return "5 sec"
        case .efficient: return "15 sec"
        case .background: return "System-managed"
        }
    }

    var duration: Duration {
        switch self {
        case .fast: return .seconds(1)
        case .balanced: return .seconds(5)
        case .efficient: return .seconds(15)
        case .background: return .seconds(30)
        }
    }
}

enum MonitoringProfile: String, Codable, CaseIterable, Sendable, Identifiable {
    case maximum
    case balanced
    case batterySaver

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .maximum: return "Maximum"
        case .balanced: return "Balanced"
        case .batterySaver: return "Battery Saver"
        }
    }

    var detail: String {
        switch self {
        case .maximum: return "Full detail, faster polling"
        case .balanced: return "Recommended daily use"
        case .batterySaver: return "Lower polling, fewer animations"
        }
    }

    var interval: UpdateInterval {
        switch self {
        case .maximum: return .fast
        case .balanced: return .balanced
        case .batterySaver: return .efficient
        }
    }
}

enum AppearanceMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

// MARK: - Settings model

struct AppSettings: Codable, Equatable, Sendable {
    var monitoringEnabled: [MetricKind: Bool] = {
        var dict: [MetricKind: Bool] = [:]
        for kind in MetricKind.allCases { dict[kind] = true }
        return dict
    }()
    var monitoringProfile: MonitoringProfile = .balanced
    var updateInterval: UpdateInterval? = nil

    var backgroundRefreshEnabled: Bool = true
    var wifiOnlyDiagnostics: Bool = false
    var batterySavingMode: Bool = false

    var liveActivitiesMasterEnabled: Bool = true
    var liveActivityKinds: [MetricKind: Bool] = {
        var dict: [MetricKind: Bool] = [:]
        for kind in MetricKind.allCases { dict[kind] = false }
        dict[.cpu] = true
        dict[.battery] = true
        dict[.charging] = true
        dict[.device] = true
        return dict
    }()
    var liveActivityPriority: [MetricKind] = [.charging, .battery, .cpu, .memory, .network]

    var cpuBenchmarkDuration: Double = 5.0
    var gpuBenchmarkDuration: Double = 5.0
    var storageBenchmarkSizeMB: Int = 200
    var thermalSafeguardEnabled: Bool = true
    var autoCleanupBenchmarkFiles: Bool = true

    var appearance: AppearanceMode = .system
    var hapticsEnabled: Bool = true
    var diagnosticHaptics: Bool = true

    var notifyBatteryThresholdEnabled: Bool = true
    var batteryThresholdPercent: Int = 20
    var notifyThermalWarning: Bool = true
    var notifyChargingComplete: Bool = true
    var notifyDiagnosticComplete: Bool = false
    var notifyBenchmarkComplete: Bool = false

    var effectiveInterval: UpdateInterval {
        updateInterval ?? monitoringProfile.interval
    }
}

// MARK: - Settings store

@MainActor
@Observable
final class SettingsStore {
    private static let defaultsKey = "devicelab.settings.v1"

    private(set) var settings: AppSettings {
        didSet { persist() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    func update(_ mutate: (inout AppSettings) -> Void) {
        var newValue = settings
        mutate(&newValue)
        settings = newValue
    }

    func isMonitoringEnabled(_ kind: MetricKind) -> Bool {
        settings.monitoringEnabled[kind] ?? true
    }

    func isLiveActivityEnabled(_ kind: MetricKind) -> Bool {
        settings.liveActivitiesMasterEnabled && (settings.liveActivityKinds[kind] ?? false)
    }
}