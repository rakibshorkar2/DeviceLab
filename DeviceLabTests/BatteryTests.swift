import XCTest
@testable import DeviceLab

@MainActor
final class BatteryTests: XCTestCase {

    private var store: BatteryHistoryStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        store = BatteryHistoryStore.makeInMemory()
        XCTAssertNotNil(store)
    }

    override func tearDownWithError() throws {
        store = nil
        try super.tearDownWithError()
    }

    func testRecordAndQueryBatterySamples() {
        let now = Date()
        store.recordBattery(level: 50, state: .unplugged, thermalRaw: "Nominal", at: now.addingTimeInterval(-120))
        store.recordBattery(level: 48, state: .unplugged, thermalRaw: "Nominal", at: now.addingTimeInterval(-60))
        store.recordBattery(level: 46, state: .unplugged, thermalRaw: "Nominal", at: now)

        let samples = store.batterySamples(since: now.addingTimeInterval(-180))
        XCTAssertEqual(samples.count, 3)
        XCTAssertEqual(samples.last?.level, 46)
        XCTAssertEqual(samples.first?.stateRaw, "unplugged")
    }

    func testBatterySamplesFilteredBySince() {
        let now = Date()
        store.recordBattery(level: 90, state: .unplugged, thermalRaw: "Nominal", at: now.addingTimeInterval(-3600))
        store.recordBattery(level: 80, state: .unplugged, thermalRaw: "Nominal", at: now)

        let recent = store.batterySamples(since: now.addingTimeInterval(-600))
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent.first?.level, 80)
    }

    func testChargingSessionsRoundTrip() {
        let start = Date().addingTimeInterval(-3600)
        store.addChargingSession(ChargingSessionRecord(
            start: start,
            end: Date(),
            startLevel: 20,
            endLevel: 85,
            peakLevel: 85
        ))
        let sessions = store.chargingSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.startLevel, 20)
        XCTAssertEqual(sessions.first?.endLevel, 85)
        XCTAssertEqual(sessions.first?.peakLevel, 85)
    }

    func testBenchmarkResultsPersist() {
        store.addBenchmarkResult(category: "CPU", name: "CPU Benchmark", score: 4321, metricsJSON: "{}")
        let results = store.benchmarkResults(category: "CPU")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.score, 4321)
        let filtered = store.benchmarkResults(category: "GPU")
        XCTAssertTrue(filtered.isEmpty)
    }

    func testMeasurementTrimLimit() {
        let kind = MetricKind.cpu
        let limit = AppConstants.History.maxSamplesPerKind
        let now = Date()
        for i in 0..<(limit + 5) {
            store.record(kind: kind, value: Double(i), unit: "%", detail: "t", timestamp: now.addingTimeInterval(TimeInterval(i)))
        }
        let remaining = store.measurements(kind: kind, since: .distantPast)
        XCTAssertLessThanOrEqual(remaining.count, limit)
    }

    func testChargeRateEstimator() {
        let start = Date().addingTimeInterval(-3600)
        let rate = ChargingMonitor.estimateRate(sessionStart: start, now: Date(), startLevel: 20, currentLevel: 80)
        XCTAssertEqual(rate ?? 0, 60, accuracy: 0.001)

        XCTAssertNil(ChargingMonitor.estimateRate(sessionStart: start, now: Date(), startLevel: nil, currentLevel: 80))
        XCTAssertNil(ChargingMonitor.estimateRate(sessionStart: start, now: Date(), startLevel: 20, currentLevel: nil))
        // Too short a window → no estimate
        let short = ChargingMonitor.estimateRate(sessionStart: Date(), now: Date().addingTimeInterval(1), startLevel: 20, currentLevel: 21)
        XCTAssertNil(short)
    }

    func testPowerMonitorDischargeEstimate() async {
        let now = Date()
        // 3 hours ago at 60%, now at 45% → 5%/hr
        store.recordBattery(level: 60, state: .unplugged, thermalRaw: "Nominal", at: now.addingTimeInterval(-3 * 3600))
        store.recordBattery(level: 52, state: .unplugged, thermalRaw: "Nominal", at: now.addingTimeInterval(-2 * 3600))
        store.recordBattery(level: 45, state: .unplugged, thermalRaw: "Nominal", at: now)

        let charging = ChargingMonitor()
        let power = PowerMonitor(charging: charging, history: store)
        await power.refresh()

        XCTAssertEqual(power.dischargeRatePerHour ?? 0, 5, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(power.estimateWindowMinutes, 180)
        XCTAssertEqual(power.sampleCount, 3)
        // The snapshot should be reported with the .power kind.
        XCTAssertEqual(power.snapshot.kind, .power)
    }
}