import Foundation
import UIKit

/// Lightweight report data types (decoupled from SwiftData models).
struct ReportBatterySession: Sendable, Identifiable {
    let id = UUID()
    let start: Date
    let end: Date?
    let startLevel: Double?
    let endLevel: Double?
    let peakLevel: Double?
}

struct ReportBenchmark: Sendable, Identifiable {
    let id = UUID()
    let category: String
    let name: String
    let score: Double
    let timestamp: Date
}

/// Builds a DeviceLab Diagnostic Report from real data.
/// Restricted metrics are explicitly labeled, never faked.
struct DiagnosticReportBuilder {
    var device = DeviceInfo.current
    var generatedAt = Date()
    var systemData = DeviceData.empty
    var snapshots: [MetricSnapshot] = []
    var batterySessions: [ReportBatterySession] = []
    var benchmarks: [ReportBenchmark] = []
    var diagnostics: [String: String] = [:]
    var score: DeviceScoreEngine.ScoreSet?
    var powerDischargeRatePerHour: Double?
    var powerEstimateWindowMinutes: Double?

    // MARK: Plain text

    func plainText() -> String {
        var lines: [String] = []
        lines.append("DeviceLab Diagnostic Report")
        lines.append("Generated: \(Formatters.dateTime(generatedAt))")
        lines.append(String(repeating: "=", count: 44))
        lines.append("")

        lines.append("Device")
        lines.append("  Model: \(device.marketingName) (\(device.modelIdentifier))")
        lines.append("  OS: \(device.osLabel)")
        lines.append("  Cores: \(device.processorCount)")
        lines.append(String(format: "  Physical memory: %.1f GB", device.memoryGB))
        lines.append("")

        if let score {
            lines.append("Device Score: \(score.total)/100")
            for category in score.categories {
                lines.append("  \(category.name): \(Int(category.score))/100 — \(category.explanation)")
                for basis in category.basedOn {
                    lines.append("    • \(basis)")
                }
            }
            lines.append("")
        }

        lines.append("Live Measurements")
        for snapshot in snapshots {
            lines.append("  \(snapshot.kind.displayName): \(snapshot.valueText)")
            lines.append("    \(snapshot.subtext)")
            lines.append("    Source: \(snapshot.provenance.displayName)")
            lines.append("    Updated: \(Formatters.time(snapshot.updatedAt))")
            lines.append("")
        }

        lines.append("Battery History")
        if batterySessions.isEmpty {
            lines.append("  No charging sessions recorded yet.")
        } else {
            for session in batterySessions {
                let end = session.end.map { Formatters.timeShort($0) } ?? "ongoing"
                lines.append("  \(Formatters.dateTime(session.start)) → \(end)")
                lines.append("    \(session.startLevel.map { "\(Int($0))%" } ?? "—") → \(session.endLevel.map { "\(Int($0))%" } ?? "—") (peak \(session.peakLevel.map { "\(Int($0))%" } ?? "—"))")
            }
        }
        lines.append("")

        if let powerDischargeRatePerHour {
            lines.append("Power")
            lines.append("  Estimated discharge: \(String(format: "%.1f%%/hour", powerDischargeRatePerHour))")
            lines.append("  Estimate window: \(powerEstimateWindowMinutes.map { "\(Int($0)) minutes" } ?? "—") (DeviceLab estimate from local history, not an Apple power metric)")
            lines.append("")
        }

        lines.append("Benchmarks")
        if benchmarks.isEmpty {
            lines.append("  No benchmarks run yet.")
        } else {
            for benchmark in benchmarks {
                lines.append("  \(benchmark.category) / \(benchmark.name): \(Int(benchmark.score)) (DeviceLab score, \(Formatters.dateTime(benchmark.timestamp)))")
            }
        }
        lines.append("")

        lines.append("Diagnostics")
        if diagnostics.isEmpty {
            lines.append("  No manual diagnostics recorded.")
        } else {
            for (name, result) in diagnostics {
                lines.append("  \(name): \(result)")
            }
        }
        lines.append("")

        lines.append("Restricted Metrics")
        lines.append("  • Per-app CPU/GPU/RAM of other apps — not exposed by iOS public APIs")
        lines.append("  • Battery health / cycle count — not exposed to third-party apps (see Settings → Battery → Battery Health)")
        lines.append("  • Exact charger wattage — not exposed to third-party apps")
        lines.append("  • Internal chip temperature in °C — not exposed; thermal state used instead")
        lines.append("")
        lines.append("All data was collected locally on this device. Nothing leaves the device.")
        return lines.joined(separator: "\n")
    }

    // MARK: JSON

    func jsonData() -> Data? {
        let payload: [String: Any] = [
            "report": "DeviceLab Diagnostic Report",
            "generatedAt": Formatters.dateTime(generatedAt),
            "device": [
                "model": device.marketingName,
                "identifier": device.modelIdentifier,
                "os": device.osLabel,
                "cores": device.processorCount,
                "physicalMemoryGB": device.memoryGB,
            ],
            "measurements": snapshots.map { snapshot in
                [
                    "metric": snapshot.kind.displayName,
                    "value": snapshot.valueText,
                    "detail": snapshot.subtext,
                    "provenance": snapshot.provenance.rawValue,
                    "updatedAt": Formatters.dateTime(snapshot.updatedAt ?? .distantPast),
                ]
            },
            "batterySessions": batterySessions.map { session in
                [
                    "start": Formatters.dateTime(session.start),
                    "end": session.end.map { Formatters.dateTime($0) } ?? "ongoing",
                    "startLevel": session.startLevel ?? -1,
                    "endLevel": session.endLevel ?? -1,
                    "peakLevel": session.peakLevel ?? -1,
                ]
            },
            "power": [
                "estimatedDischargeRatePerHour": powerDischargeRatePerHour.map { Double(round($0 * 10) / 10) as Any } ?? "n/a",
                "estimateWindowMinutes": powerEstimateWindowMinutes.map { Int($0) } ?? 0,
            ],
            "benchmarks": benchmarks.map { benchmark in
                [
                    "category": benchmark.category,
                    "name": benchmark.name,
                    "score": benchmark.score,
                    "timestamp": Formatters.dateTime(benchmark.timestamp),
                ]
            },
            "diagnostics": diagnostics,
            "restrictedMetrics": [
                "perAppCpu": "Not exposed by iOS public APIs",
                "perAppGpu": "Not exposed by iOS public APIs",
                "perAppRam": "Not exposed by iOS public APIs",
                "batteryHealth": "Not exposed to third-party apps",
                "cycleCount": "Not exposed to third-party apps",
                "chargerWatts": "Not exposed to third-party apps",
            ],
            "privacy": "Local-only. No data leaves the device.",
        ]
        return try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    // MARK: CSV

    func csvData() -> Data? {
        var rows: [String] = []
        rows.append("DeviceLab Diagnostic Report")
        rows.append("Generated,\(Formatters.dateTime(generatedAt))")
        rows.append("Device,\(device.marketingName) (\(device.modelIdentifier)),\(device.osLabel)")
        rows.append("")
        rows.append("Metric,Value,Detail,Provenance,Updated")
        for snapshot in snapshots {
            rows.append("\(snapshot.kind.displayName),\"\(snapshot.valueText)\",\"\(snapshot.subtext)\",\(snapshot.provenance.rawValue),\(Formatters.dateTime(snapshot.updatedAt ?? .distantPast))")
        }
        rows.append("")
        rows.append("Benchmark,Score,Timestamp")
        for benchmark in benchmarks {
            rows.append("\(benchmark.name),\(Int(benchmark.score)),\(Formatters.dateTime(benchmark.timestamp))")
        }
        rows.append("")
        rows.append("ChargingSession,Start,End,StartLevel,EndLevel,Peak")
        for session in batterySessions {
            rows.append("Session,\(Formatters.dateTime(session.start)),\(session.end.map { Formatters.dateTime($0) } ?? "ongoing"),\(session.startLevel.map { Int($0) } ?? -1),\(session.endLevel.map { Int($0) } ?? -1),\(session.peakLevel.map { Int($0) } ?? -1)")
        }
        rows.append("")
        rows.append("Diagnostic,Result")
        for (name, result) in diagnostics.sorted(by: { $0.key < $1.key }) {
            rows.append("\"\(name)\",\"\(result)\"")
        }
        return rows.joined(separator: "\n").data(using: .utf8)
    }

    // MARK: PDF

    func pdfData() -> Data? {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let text = plainText()
        return renderer.pdfData { context in
            context.beginPage()
            drawText(text, in: pageRect, context: context)
        }
    }

    private func drawText(_ text: String, in rect: CGRect, context: UIGraphicsPDFRendererContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9),
            .foregroundColor: UIColor.black,
        ]
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        var merged = attributes
        merged[.paragraphStyle] = paragraphStyle

        let yStart: CGFloat = 24
        var y = yStart
        let maxWidth = rect.width - 48
        let lines = text.components(separatedBy: "\n")
        for line in lines {
            let attributed = NSAttributedString(string: line, attributes: merged)
            let size = attributed.boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], context: nil)
            let lineHeight = max(size.height, 11)
            if y + lineHeight > rect.height - 24 {
                context.beginPage()
                y = yStart
            }
            attributed.draw(in: CGRect(x: 24, y: y, width: maxWidth, height: lineHeight))
            y += lineHeight + 2
        }
    }
}