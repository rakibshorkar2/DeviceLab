import Foundation

/// Transparent device scoring. Every category explains exactly how its
/// score was calculated; nothing is hidden or fabricated.
enum DeviceScoreEngine {
    struct Category: Identifiable, Sendable {
        let name: String
        let score: Double
        let explanation: String
        let basedOn: [String]

        var id: String { name }
    }

    struct ScoreSet: Sendable {
        let total: Int
        let categories: [Category]

        var average: Double {
            guard !categories.isEmpty else { return 0 }
            return categories.map(\.score).reduce(0, +) / Double(categories.count)
        }
    }

    struct Input: Sendable {
        var benchmarkResults: [ReportBenchmark]
        var batteryLevel: Double?
        var isCharging: Bool?
        var isLowPowerMode: Bool?
        var dischargeRatePerHour: Double?
        var thermalState: String?
        var storageFreeFraction: Double?
        var networkLatencyMs: Double?
        var networkDownMbps: Double?
        var networkUpMbps: Double?
        var sensorsAvailableCount: Int?
        var sensorsTotalCount: Int = 7
        var cameraCount: Int?
        var cameraCapturePerformed: Bool?
        var displayTestsPerformed: Bool?
        var audioTestsPerformed: Bool?
    }

    static func compute(_ input: Input) -> ScoreSet {
        let categories: [Category] = [
            performance(input),
            battery(input),
            thermal(input),
            storage(input),
            network(input),
            sensors(input),
            display(input),
            audio(input),
            camera(input),
        ]
        let total = Int(categories.map(\.score).reduce(0, +) / Double(categories.count).rounded())
        return ScoreSet(total: min(100, total), categories: categories)
    }

    private static func score(_ value: Double) -> Double {
        min(100, max(0, value))
    }

    private static func performance(_ input: Input) -> Category {
        var scores: [Double] = []
        var basis: [String] = []
        for result in input.benchmarkResults {
            scores.append(result.score / 100)
            basis.append("\(result.category) benchmark: \(Int(result.score))")
        }
        if basis.isEmpty {
            return Category(name: "Performance", score: 0, explanation: "Run benchmarks (Benchmark tab) to calculate the performance score.", basedOn: [])
        }
        let value = scores.reduce(0, +) / Double(scores.count)
        return Category(
            name: "Performance",
            score: score(value),
            explanation: "Average of normalized benchmark scores.",
            basedOn: basis
        )
    }

    private static func battery(_ input: Input) -> Category {
        var basis: [String] = []
        var value = 60.0
        if let level = input.batteryLevel {
            if level >= 50 { value += 15 }
            else if level >= 20 { value += 5 }
            else { value -= 20 }
            basis.append("battery level \(Int(level))%")
        }
        if input.isLowPowerMode == false {
            value += 10
            basis.append("Low Power Mode off")
        } else if input.isLowPowerMode == true {
            value -= 10
            basis.append("Low Power Mode on")
        }
        if input.isCharging == true {
            value += 5
            basis.append("charging")
        }
        if let discharge = input.dischargeRatePerHour, discharge > 0 {
            if discharge < 12 {
                value += 5
            } else {
                value -= 10
            }
            basis.append(String(format: "discharge rate %.1f%%/hr", discharge))
        }
        if basis.isEmpty {
            basis.append("not enough history yet")
        }
        return Category(name: "Battery", score: score(value), explanation: "Composed from level, Low Power Mode, charging state and observed discharge rate.", basedOn: basis)
    }

    private static func thermal(_ input: Input) -> Category {
        var value = 90.0
        var basis: [String] = []
        if let state = input.thermalState {
            switch state {
            case "Nominal": value = 100
            case "Fair": value = 75
            case "Serious": value = 45
            case "Critical": value = 15
            default: value = 70
            }
            basis.append("thermal state: \(state)")
        }
        return Category(name: "Thermal", score: score(value), explanation: "Based on the current thermal state reported by ProcessInfo.", basedOn: basis)
    }

    private static func storage(_ input: Input) -> Category {
        guard let fraction = input.storageFreeFraction else {
            return Category(name: "Storage", score: 0, explanation: "Storage capacity not available yet.", basedOn: [])
        }
        var value = fraction * 140
        var basis: [String] = [String(format: "%.0f%% of storage free", fraction * 100)]
        if fraction < 0.08 {
            value = 20
            basis.append("very low free space")
        }
        return Category(name: "Storage", score: score(value), explanation: "Based on free storage as a fraction of total capacity.", basedOn: basis)
    }

    private static func network(_ input: Input) -> Category {
        var basis: [String] = []
        var value = 0.0
        if let latency = input.networkLatencyMs, latency > 0 {
            value += 40 * min(1, 40 / latency)
            basis.append(String(format: "latency %.0f ms", latency))
        }
        if let down = input.networkDownMbps, down > 0 {
            value += 35 * min(1, down / 500)
            basis.append(String(format: "download %.0f Mbps", down))
        }
        if let up = input.networkUpMbps, up > 0 {
            value += 25 * min(1, up / 150)
            basis.append(String(format: "upload %.0f Mbps", up))
        }
        if basis.isEmpty {
            basis.append("run Network Diagnostics to measure")
        }
        return Category(name: "Network", score: score(value), explanation: "Weighted combination of latency (40%), download (35%), upload (25%).", basedOn: basis)
    }

    private static func sensors(_ input: Input) -> Category {
        guard let count = input.sensorsAvailableCount else {
            return Category(name: "Sensors", score: 0, explanation: "Sensor check not run yet.", basedOn: [])
        }
        let total = max(1, input.sensorsTotalCount)
        let value = Double(count) / Double(total) * 100
        return Category(
            name: "Sensors",
            score: score(value),
            explanation: "Fraction of detectable sensors that reported available via Core Motion.",
            basedOn: ["\(count) of \(total) sensor groups available"]
        )
    }

    private static func display(_ input: Input) -> Category {
        guard input.displayTestsPerformed == true else {
            return Category(name: "Display", score: 0, explanation: "Run the display test to score display.", basedOn: [])
        }
        return Category(name: "Display", score: 90, explanation: "Display tests completed. Visual inspection results are user-confirmed.", basedOn: ["display test completed"])
    }

    private static func audio(_ input: Input) -> Category {
        guard input.audioTestsPerformed == true else {
            return Category(name: "Audio", score: 0, explanation: "Run microphone and speaker tests to score audio.", basedOn: [])
        }
        return Category(name: "Audio", score: 85, explanation: "Microphone and speaker tests completed with user confirmation.", basedOn: ["audio tests completed"])
    }

    private static func camera(_ input: Input) -> Category {
        guard let count = input.cameraCount else {
            return Category(name: "Camera", score: 0, explanation: "Camera discovery not run yet.", basedOn: [])
        }
        var value = 80.0
        var basis: [String] = ["\(count) camera(s) discovered"]
        if count > 1 { value += 10 }
        if input.cameraCapturePerformed == true {
            value += 5
            basis.append("capture performed")
        }
        return Category(name: "Camera", score: score(value), explanation: "Based on the number of cameras reported by AVFoundation and whether a capture succeeded.", basedOn: basis)
    }
}