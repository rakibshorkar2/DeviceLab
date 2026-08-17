import Foundation

/// Thermal monitor based on ProcessInfo.thermalState (public API).
/// iOS does not expose internal temperature in °C to third-party apps;
/// only the nominal/fair/serious/critical state is provided, so that is
/// exactly what DeviceLab reports.
@MainActor
final class ThermalMonitor: BaseMonitor {
    private(set) var thermalState: ProcessInfo.ThermalState = .nominal

    init() {
        super.init(kind: .thermal)
    }

    override func refresh() async {
        thermalState = ProcessInfo.processInfo.thermalState

        let status: MetricStatus = {
            switch thermalState {
            case .nominal: return .normal
            case .fair: return .normal
            case .serious: return .warning
            case .critical: return .critical
            @unknown default: return .normal
            }
        }()

        let detail = """
        Thermal state: \(Self.name(for: thermalState))
        iOS does not expose internal chip temperature in °C to third-party apps.
        Apple reports only a categorical thermal state via ProcessInfo.
        """

        updateSnapshot(MetricSnapshot(
            kind: .thermal,
            valueText: Self.name(for: thermalState),
            subtext: Self.explanation(for: thermalState),
            detail: detail,
            status: status,
            provenance: .directPublicAPI,
            updatedAt: Date(),
            numericValue: Double(thermalState.rawValue),
            unit: "level"
        ))
    }

    nonisolated static func name(for state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    nonisolated static func explanation(for state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Normal operating temperature"
        case .fair: return "Slightly elevated"
        case .serious: return "Performance may be reduced"
        case .critical: return "Extreme conditions; limit usage"
        @unknown default: return ""
        }
    }
}