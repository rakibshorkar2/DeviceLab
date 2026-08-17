import Foundation
import UIKit

struct ChargingSessionRecord: Sendable {
    let start: Date
    let end: Date
    let startLevel: Double?
    let endLevel: Double?
    let peakLevel: Double?
}

/// Charging monitor: session tracking and charge-rate estimation.
/// Charge rate is a DeviceLab measurement derived from level deltas over time.
/// Exact charger wattage is not exposed by iOS public APIs and is reported as such.
@MainActor
final class ChargingMonitor: BaseMonitor {
    private(set) var isCharging = false
    private(set) var sessionStart: Date?
    private(set) var sessionStartLevel: Double?
    private(set) var currentLevel: Double?
    private(set) var peakLevel: Double?
    private(set) var ratePerHour: Double?
    private(set) var ratePer10Minutes: Double?
    private(set) var chargingDuration: TimeInterval?
    private(set) var thermalDuringCharging: String?

    var onSessionCompleted: ((ChargingSessionRecord) -> Void)?

    /// Pure charge-rate estimation (%/hour) from level deltas. Testable without hardware.
    static func estimateRate(sessionStart: Date, now: Date, startLevel: Double?, currentLevel: Double?) -> Double? {
        guard let startLevel, startLevel >= 0, let currentLevel else { return nil }
        let hours = now.timeIntervalSince(sessionStart) / 3600
        guard hours >= 0.02 else { return nil }
        return (currentLevel - startLevel) / hours
    }

    private var lastLevel: Double?
    private var lastLevelDate: Date?

    init() {
        super.init(kind: .charging)
    }

    override func refresh() async {
        let device = UIDevice.current
        if !device.isBatteryMonitoringEnabled {
            device.isBatteryMonitoringEnabled = true
        }
        let level = device.batteryLevel >= 0 ? Double(device.batteryLevel) * 100 : nil
        let state = device.batteryState
        let now = Date()
        thermalDuringCharging = ThermalMonitor.name(for: ProcessInfo.processInfo.thermalState)

        if state == .charging || state == .full {
            if !isCharging {
                isCharging = true
                sessionStart = now
                sessionStartLevel = level
                peakLevel = level
            }
            currentLevel = level
            if let level {
                peakLevel = max(peakLevel ?? 0, level)
            }
            chargingDuration = sessionStart.map { now.timeIntervalSince($0) }

            if let start = sessionStart {
                ratePerHour = Self.estimateRate(sessionStart: start, now: now, startLevel: sessionStartLevel, currentLevel: level)
            }
            if let level, let lastLevel, let lastLevelDate {
                let hours = now.timeIntervalSince(lastLevelDate) / 3600
                if hours >= 0.02 {
                    let shortRate = (level - lastLevel) / hours
                    if let currentRate = ratePerHour, abs(shortRate - currentRate) / currentRate < 2.0 {
                        ratePerHour = shortRate
                    } else if ratePerHour == nil {
                        ratePerHour = shortRate
                    }
                }
            }
            ratePer10Minutes = ratePerHour.map { $0 / 6 }
        } else {
            if isCharging {
                onSessionCompleted?(ChargingSessionRecord(
                    start: sessionStart ?? now,
                    end: now,
                    startLevel: sessionStartLevel,
                    endLevel: currentLevel,
                    peakLevel: peakLevel
                ))
            }
            resetSessionState()
        }

        lastLevel = level
        lastLevelDate = now
        publishSnapshot(now: now)
    }

    private func resetSessionState() {
        isCharging = false
        sessionStart = nil
        sessionStartLevel = nil
        currentLevel = nil
        peakLevel = nil
        ratePerHour = nil
        ratePer10Minutes = nil
        chargingDuration = nil
    }

    private func publishSnapshot(now: Date) {
        let valueText: String
        var subtext = "Not connected"
        var numeric: Double?

        if isCharging {
            valueText = "Charging"
            if let ratePer10Minutes {
                subtext = String(format: "+%.1f%% / 10 min", ratePer10Minutes)
                numeric = ratePer10Minutes
            } else {
                subtext = "Measuring rate…"
            }
            if let duration = chargingDuration {
                subtext += " · \(duration.durationLabel)"
            }
        } else {
            valueText = "Not charging"
        }

        let detail = """
        Charging: \(isCharging ? "yes" : "no")
        Session start: \(Formatters.time(sessionStart))
        Level at start: \(sessionStartLevel.map { String(format: "%.0f%%", $0) } ?? "—")
        Level now: \(currentLevel.map { String(format: "%.0f%%", $0) } ?? "—")
        Charge rate: \(ratePerHour.map { String(format: "+%.1f%% / hour (DeviceLab estimate)", $0) } ?? "—")
        Charging duration: \(chargingDuration?.durationLabel ?? "—")
        Thermal during charging: \(thermalDuringCharging ?? "—")

        Exact charger wattage (W) is not exposed to third-party apps
        by any public iOS API; it is reported as unavailable.
        """

        updateSnapshot(MetricSnapshot(
            kind: .charging,
            valueText: valueText,
            subtext: subtext,
            detail: detail,
            status: isCharging ? .normal : .inactive,
            provenance: .measuredByDeviceLab,
            updatedAt: now,
            numericValue: numeric,
            unit: "%/10min"
        ))
    }
}