import Foundation

/// Outcome of one benchmark run. All values are real DeviceLab measurements.
struct BenchmarkOutcome: Sendable, Equatable {
    var score: Double
    var metrics: [String: Double]
    var detail: String
}

enum BenchmarkError: LocalizedError, Error {
    case metalUnavailable
    case cancelled

    var errorDescription: String? {
        switch self {
        case .metalUnavailable: return "Metal is not available on this device."
        case .cancelled: return "Benchmark cancelled."
        }
    }
}

/// All benchmarks are cancelable and report progress 0...1.
/// Scores are DeviceLab-normalized (0–10,000) relative to internal
/// calibration constants — never claimed to equal Apple's internal scores.
protocol Benchmark: Sendable {
    var category: String { get }
    var name: String { get }
    var detailName: String { get }

    func run(
        progress: @escaping @Sendable (Double) async -> Void,
        cancelled: @escaping @Sendable () async -> Bool
    ) async throws -> BenchmarkOutcome
}

enum BenchmarkMeasurement {
    static func measureSeconds(_ body: () -> Void) -> TimeInterval {
        let start = Date()
        body()
        return Date().timeIntervalSince(start)
    }

    static func measureSeconds(_ body: () throws -> Void) throws -> TimeInterval {
        let start = Date()
        try body()
        return Date().timeIntervalSince(start)
    }

    /// Normalizes measured work per second against a calibration constant.
    static func normalizedScore(workPerSecond: Double, reference: Double) -> Double {
        guard reference > 0 else { return 0 }
        return min(10_000, max(0, workPerSecond / reference * 10_000))
    }
}