import Foundation
import UIKit

/// Battery monitor using UIDevice's public battery APIs.
/// iOS does NOT expose battery health, cycle count, or charger wattage
/// to third-party apps; those values are handled by BatteryHealthView
/// and are reported as restricted rather than faked.
@MainActor
final class BatteryMonitor: BaseMonitor {
    private(set) var levelPercent: Double?
    private(set) var batteryState: UIDevice.BatteryState = .unknown
    private(set) var isLowPowerMode = false

    override init() {
        super.init(kind: .battery)
    }

    override func refresh() async {
        let device = UIDevice.current
        if !device.isBatteryMonitoringEnabled {
            device.isBatteryMonitoringEnabled = true
        }
        let rawLevel = device.batteryLevel
        batteryState = device.batteryState
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        var numeric: Double?
        var valueText = "Unavailable"
        if rawLevel >= 0 {
            levelPercent = Double(rawLevel) * 100
            numeric = levelPercent
            valueText = String(format: "%.0f%%", numeric ?? 0)
        } else {
            levelPercent = nil
        }

        let stateText: String = {
            switch batteryState {
            case .unknown: return "Unknown"
            case .unplugged: return "Not charging"
            case .charging: return "Charging"
            case .full: return "Full"
            @unknown default: return "Unknown"
            }
        }()

        var subtext = stateText
        if isLowPowerMode { subtext += " · Low Power Mode" }

        let status: MetricStatus = {
            guard let levelPercent else { return .inactive }
            if levelPercent <= 10 { return .critical }
            if levelPercent <= 20 { return .warning }
            return .normal
        }()

        let detail = """
        Battery level: \(valueText)
        State: \(stateText)
        Low Power Mode: \(isLowPowerMode ? "on" : "off")
        Source: UIDevice public API.

        Battery health, cycle count and charger wattage are not exposed
        to third-party apps by iOS public APIs.
        """

        updateSnapshot(MetricSnapshot(
            kind: .battery,
            valueText: valueText,
            subtext: subtext,
            detail: detail,
            status: status,
            provenance: .directPublicAPI,
            updatedAt: Date(),
            numericValue: numeric,
            unit: "%"
        ))
    }
}