import Foundation

enum Formatters {
    static func gigabytes(_ bytes: Double) -> String {
        String(format: "%.1f GB", bytes / 1_073_741_824)
    }

    static func megabytes(_ bytes: Double) -> String {
        if bytes >= 1_048_576 { return String(format: "%.1f GB", bytes / 1_073_741_824) }
        return String(format: "%.0f MB", bytes / 1_048_576)
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }

    static func percent1(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    static func megabitsPerSecond(_ bytesPerSecond: Double) -> String {
        let mbps = bytesPerSecond * 8 / 1_000_000
        return String(format: "%.0f Mbps", mbps)
    }

    static func time(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    static func timeShort(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func dateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: seconds) ?? "0:00"
    }
}

extension TimeInterval {
    var durationLabel: String { Formatters.duration(self) }
}