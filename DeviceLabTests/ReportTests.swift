import XCTest
@testable import DeviceLab

final class ReportTests: XCTestCase {

    func testPlainTextReportContents() {
        var builder = DiagnosticReportBuilder()
        builder.generatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        builder.snapshots = [
            MetricSnapshot(
                kind: .cpu,
                valueText: "12%",
                subtext: "2% system · 10% DeviceLab",
                detail: "detail",
                status: .normal,
                provenance: .measuredByDeviceLab,
                updatedAt: Date(),
                numericValue: 12,
                unit: "%"
            )
        ]
        builder.powerDischargeRatePerHour = 5.0
        builder.benchmarks = [ReportBenchmark(category: "CPU", name: "CPU Benchmark", score: 5000, timestamp: Date())]

        let text = builder.plainText()
        XCTAssertTrue(text.contains("DeviceLab Diagnostic Report"))
        XCTAssertTrue(text.contains("CPU"))
        XCTAssertTrue(text.contains("Measured by DeviceLab"))
        XCTAssertTrue(text.contains("Estimated discharge: 5.0%/hour"))
        XCTAssertTrue(text.contains("Restricted Metrics"))
        XCTAssertTrue(text.contains("Nothing leaves the device"))
    }

    func testJSONReportSerializes() throws {
        var builder = DiagnosticReportBuilder()
        builder.snapshots = [MetricSnapshot(
            kind: .memory,
            valueText: "2.1 GB",
            subtext: "",
            detail: "",
            status: .normal,
            provenance: .systemReported,
            updatedAt: nil,
            numericValue: nil,
            unit: ""
        )]
        builder.powerDischargeRatePerHour = 3.4
        let data = try XCTUnwrap(builder.jsonData())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["report"] as? String, "DeviceLab Diagnostic Report")
        let measurements = try XCTUnwrap(json["measurements"] as? [[String: Any]])
        XCTAssertEqual(measurements.count, 1)
        XCTAssertEqual(measurements.first?["provenance"] as? String, "SYSTEM_REPORTED")
        let power = try XCTUnwrap(json["power"] as? [String: Any])
        XCTAssertEqual(power["estimatedDischargeRatePerHour"] as? Double, 3.4)
    }

    func testCSVReportContainsRows() throws {
        var builder = DiagnosticReportBuilder()
        builder.snapshots = [MetricSnapshot(
            kind: .battery,
            valueText: "72%",
            subtext: "",
            detail: "",
            status: .normal,
            provenance: .directPublicAPI,
            updatedAt: nil,
            numericValue: nil,
            unit: ""
        )]
        let csv = try XCTUnwrap(builder.csvData())
        let text = try XCTUnwrap(String(data: csv, encoding: .utf8))
        XCTAssertTrue(text.contains("Metric,Value,Detail,Provenance,Updated"))
        XCTAssertTrue(text.contains("DIRECT_PUBLIC_API"))
        XCTAssertTrue(text.contains("72%"))
    }

    func testPDFReportGenerates() throws {
        let builder = DiagnosticReportBuilder()
        let data = try XCTUnwrap(builder.pdfData())
        XCTAssertGreaterThan(data.count, 1000)
        XCTAssertEqual(data.prefix(4).map { String(format: "%02X", $0) }.joined(), "%PDF")
    }
}