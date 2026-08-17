import XCTest
@testable import DeviceLab

@MainActor
final class CoreTests: XCTestCase {

    func testProvenanceDisplayNames() {
        XCTAssertEqual(Provenance.directPublicAPI.displayName, "Public API")
        XCTAssertEqual(Provenance.measuredByDeviceLab.displayName, "Measured by DeviceLab")
        XCTAssertEqual(Provenance.systemReported.displayName, "System reported")
        XCTAssertEqual(Provenance.derivedEstimate.displayName, "DeviceLab estimate")
        XCTAssertEqual(Provenance.unavailableOnStockiOS.displayName, "Unavailable on stock iOS")
        XCTAssertEqual(Provenance.directPublicAPI.rawValue, "DIRECT_PUBLIC_API")
    }

    func testDurationLabels() {
        XCTAssertEqual(TimeInterval(5).durationLabel, "0:00:05")
        XCTAssertEqual(TimeInterval(75).durationLabel, "0:01:15")
        XCTAssertEqual(TimeInterval(3725).durationLabel, "1:02:05")
        XCTAssertEqual(TimeInterval(0).durationLabel, "0:00:00")
    }

    func testFormatters() {
        XCTAssertFalse(Formatters.dateTime(Date()).isEmpty)
        XCTAssertFalse(Formatters.time(Date()).isEmpty)
        XCTAssertFalse(Formatters.timeShort(Date()).isEmpty)
        XCTAssertFalse(Formatters.megabytes(1_000_000).isEmpty)
        XCTAssertEqual(Formatters.percent(42), "42%")
        XCTAssertEqual(Formatters.megabitsPerSecond(1_250_000), "10 Mbps")
    }

    func testSettingsDefaultValues() {
        let store = SettingsStore()
        XCTAssertTrue(store.settings.liveActivitiesMasterEnabled)
        XCTAssertEqual(store.settings.batteryThresholdPercent, 20)
        XCTAssertEqual(store.settings.storageBenchmarkSizeMB, 200)
        XCTAssertTrue(store.settings.thermalSafeguardEnabled)
        XCTAssertTrue(store.settings.autoCleanupBenchmarkFiles)
        XCTAssertFalse(store.settings.liveActivityPriority.isEmpty)
    }

    func testSettingsUpdateMutations() {
        let store = SettingsStore()
        let before = store.settings
        store.update { $0.batteryThresholdPercent = 35 }
        XCTAssertEqual(store.settings.batteryThresholdPercent, 35)
        XCTAssertNotEqual(store.settings, before)
    }

    func testMonitoringToggleRespectsDefaults() {
        let store = SettingsStore()
        // By default every metric is enabled.
        for kind in MetricKind.allCases {
            XCTAssertTrue(store.isMonitoringEnabled(kind), "\(kind.rawValue) should be enabled by default")
        }
        store.update { $0.monitoringEnabled[.cpu] = false }
        XCTAssertFalse(store.isMonitoringEnabled(.cpu))
        XCTAssertTrue(store.isMonitoringEnabled(.memory))
    }

    func testDeviceScoreEngineClamps() {
        let score = DeviceScoreEngine.compute(DeviceScoreEngine.Input(
            benchmarkResults: [],
            batteryLevel: 0,
            isCharging: false,
            isLowPowerMode: true,
            dischargeRatePerHour: nil,
            thermalState: "Nominal",
            storageFreeFraction: nil,
            networkLatencyMs: nil,
            networkDownMbps: nil,
            networkUpMbps: nil,
            sensorsAvailableCount: 0,
            cameraCount: nil,
            cameraCapturePerformed: false,
            displayTestsPerformed: false,
            audioTestsPerformed: false
        ))
        XCTAssertEqual(score.total, 0)
        XCTAssertFalse(score.categories.isEmpty)
    }

    func testDeviceScoreEngineBasicBatteryCredit() {
        let score = DeviceScoreEngine.compute(DeviceScoreEngine.Input(
            benchmarkResults: [],
            batteryLevel: 100,
            isCharging: false,
            isLowPowerMode: false,
            dischargeRatePerHour: nil,
            thermalState: "Nominal",
            storageFreeFraction: 0.5,
            networkLatencyMs: 10,
            networkDownMbps: 200,
            networkUpMbps: 50,
            sensorsAvailableCount: 6,
            cameraCount: 2,
            cameraCapturePerformed: false,
            displayTestsPerformed: false,
            audioTestsPerformed: false
        ))
        XCTAssertGreaterThan(score.total, 0)
        XCTAssertLessThanOrEqual(score.total, 100)
    }
}