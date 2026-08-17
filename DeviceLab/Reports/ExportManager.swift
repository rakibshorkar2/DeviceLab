import Foundation
import UIKit

/// Writes report data to temporary files for sharing.
enum ExportManager {
    enum Format: String, CaseIterable, Identifiable {
        case pdf = "PDF"
        case json = "JSON"
        case csv = "CSV"
        case text = "Plain Text"

        var id: String { rawValue }

        var fileExtension: String {
            switch self {
            case .pdf: return "pdf"
            case .json: return "json"
            case .csv: return "csv"
            case .text: return "txt"
            }
        }
    }

    static func export(_ builder: DiagnosticReportBuilder, format: Format) throws -> URL {
        let fileName = "DeviceLab-Report-\(ISO8601DateFormatter().string(from: Date()))"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(fileName).\(format.fileExtension)")

        switch format {
        case .pdf:
            guard let data = builder.pdfData() else { throw ExportError.generationFailed }
            try data.write(to: url)
        case .json:
            guard let data = builder.jsonData() else { throw ExportError.generationFailed }
            try data.write(to: url)
        case .csv:
            guard let data = builder.csvData() else { throw ExportError.generationFailed }
            try data.write(to: url)
        case .text:
            try builder.plainText().write(to: url, atomically: true, encoding: .utf8)
        }
        return url
    }

    enum ExportError: Error {
        case generationFailed
    }
}