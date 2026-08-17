import Foundation

enum AppConstants {
    static let backgroundTaskIdentifier = "com.devicelab.app.refresh"

    enum Notifications {
        static let batteryThreshold = "com.devicelab.notification.battery"
        static let thermalWarning = "com.devicelab.notification.thermal"
        static let chargingComplete = "com.devicelab.notification.charging"
        static let diagnosticComplete = "com.devicelab.notification.diagnostic"
        static let benchmarkComplete = "com.devicelab.notification.benchmark"
    }

    enum Network {
        static let latencyTargets = ["1.1.1.1", "8.8.8.8", "9.9.9.9"]
        static let dnsComparisonHost = "one.one.one.one"
        static let downloadURL = URL(string: "https://speed.cloudflare.com/__down?bytes=25000000")!
        static let uploadURL = URL(string: "https://speed.cloudflare.com/__up")!
        static let testPort = 443
    }

    enum LiveActivity {
        static let staleAfter: TimeInterval = 90
        static let minimumUpdateInterval: TimeInterval = 5
        static let cpuThreshold = 1.0
        static let batteryThreshold = 1.0
        static let memoryThresholdGB = 0.1
    }

    enum Benchmark {
        static let referenceCPUOpsPerSecond: Double = 140_000_000
        static let referenceMemoryBandwidthGBps: Double = 50.0
        static let referenceStorageWriteMBps: Double = 900.0
        static let referenceGPUScore: Double = 2_000_000
        static let thermalSafeguardState = ProcessInfo.ThermalState.serious
    }

    enum History {
        static let sampleRetentionDays: Int = 30
        static let maxSamplesPerKind = 2_000
    }
}