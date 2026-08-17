import Foundation

/// Power monitor.
/// All values here are DEVICELAB estimates derived from DeviceLab's own
/// battery-level history — never Apple's private power database, and never
/// passed off as exact wattage measurements.
@MainActor
final class PowerMonitor: BaseMonitor {
    private weak var charging: ChargingMonitor?
    private let history: BatteryHistoryStore?

    private(set) var dischargeRatePerHour: Double?
    private(set) var estimateWindowMinutes: Double = 0
    private(set) var sampleCount = 0

    init(charging: ChargingMonitor, history: BatteryHistoryStore?) {
        self.charging = charging
        self.history = history
        super.init(kind: .power)
    }

    override func refresh() async {
        let now = Date()
        var dischargeRate: Double?
        var windowMinutes = 0.0
        var count = 0

        if let history {
            let since = now.addingTimeInterval(-60 * 60)
            let samples = history.batterySamples(since: since)
            let unplugged = samples.filter { $0.stateRaw == "unplugged" }
            if let first = unplugged.first, let last = unplugged.last, unplugged.count >= 2 {
                let hours = last.timestamp.timeIntervalSince(first.timestamp) / 3600
                if hours >= 0.10 {
                    dischargeRate = (first.level - last.level) / hours
                    windowMinutes = hours * 60
                    count = unplugged.count
                }
            }
        }
        dischargeRatePerHour = dischargeRate
        estimateWindowMinutes = windowMinutes
        sampleCount = count

        let isCharging = charging?.isCharging ?? false
        let chargeRate = charging?.ratePerHour

        let valueText: String
        var subtext = ""
        var numeric: Double?

        if isCharging, let chargeRate {
            valueText = String(format: "+%.1f%% / hr", chargeRate)
            subtext = String(format: "+%.1f%% / 10 min", chargeRate / 6)
            numeric = chargeRate
        } else if let dischargeRate, dischargeRate > 0 {
            valueText = String(format: "%.1f%% / hr", dischargeRate)
            subtext = "estimated over \(Int(windowMinutes)) min"
            numeric = -dischargeRate
        } else {
            valueText = "Measuring…"
            subtext = "Collects battery history over time"
        }

        let detail = """
        Estimated discharge rate: \(dischargeRate.map { String(format: "%.1f%% / hour", $0) } ?? "—")
        Window: \(Int(windowMinutes)) minutes · \(sampleCount) samples
        Source: DeviceLab's own battery-level history (derived estimate).

        Estimated charging rate: \(chargeRate.map { String(format: "+%.1f%% / hour", $0) } ?? "—")

        Exact electrical power (watts) drawn by the charger is not exposed
        to third-party apps by public iOS APIs and is therefore unavailable.
        """

        updateSnapshot(MetricSnapshot(
            kind: .power,
            valueText: valueText,
            subtext: subtext,
            detail: detail,
            status: .normal,
            provenance: .derivedEstimate,
            updatedAt: now,
            numericValue: numeric,
            unit: "%/hr"
        ))
    }
}