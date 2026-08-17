import XCTest
@testable import DeviceLab

final class BenchmarkTests: XCTestCase {

    func testNormalizedScoreClamps() {
        XCTAssertEqual(BenchmarkMeasurement.normalizedScore(workPerSecond: 0, reference: 100), 0)
        XCTAssertEqual(BenchmarkMeasurement.normalizedScore(workPerSecond: 100, reference: 100), 10_000)
        XCTAssertEqual(BenchmarkMeasurement.normalizedScore(workPerSecond: 500, reference: 100), 10_000)
        XCTAssertEqual(BenchmarkMeasurement.normalizedScore(workPerSecond: 50, reference: 100), 5_000)
        XCTAssertEqual(BenchmarkMeasurement.normalizedScore(workPerSecond: 10, reference: 0), 0)
    }

    func testMeasureSecondsTimesNonNegativeWork() {
        let seconds = BenchmarkMeasurement.measureSeconds {
            var x = 0
            for _ in 0..<10_000 { x += 1 }
            _ = x
        }
        XCTAssertGreaterThanOrEqual(seconds, 0)
    }

    func testStorageBenchmarkDefaultSize() {
        XCTAssertEqual(StorageBenchmark().requestedSizeMB, 200)
        XCTAssertEqual(StorageBenchmark(sizeMB: 400).requestedSizeMB, 400)
    }

    func testCPUJSONWorkloadRuns() {
        // The JSON workload must produce a finite, positive throughput —
        // a regression test for the earlier responds(to:) misuse.
        let result = CPUBenchmark.jsonWorkload()
        XCTAssertTrue(result.isFinite)
        XCTAssertGreaterThan(result, 0)
    }

    func testMetricSnapshotComparison() {
        let a = MetricSnapshot(kind: .cpu, valueText: "10%", subtext: "", detail: "", status: .normal, provenance: .measuredByDeviceLab, updatedAt: Date(), numericValue: 10, unit: "%")
        let b = MetricSnapshot(kind: .cpu, valueText: "20%", subtext: "", detail: "", status: .normal, provenance: .measuredByDeviceLab, updatedAt: Date(), numericValue: 20, unit: "%")
        let c = MetricSnapshot(kind: .cpu, valueText: "10%", subtext: "", detail: "", status: .normal, provenance: .measuredByDeviceLab, updatedAt: Date(), numericValue: 10, unit: "%")
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a, c)
    }
}