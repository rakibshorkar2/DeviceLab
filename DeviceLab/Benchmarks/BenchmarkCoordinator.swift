import Foundation
import Observation

/// Runs benchmarks off the main thread, reports progress, honors
/// cancellation and the thermal safeguard, and persists results.
@MainActor
@Observable
final class BenchmarkCoordinator {
    private let store: BatteryHistoryStore?
    private let settings: SettingsStore

    private(set) var isRunning = false
    private(set) var currentBenchmarkName: String?
    private(set) var progress: Double = 0
    private(set) var lastOutcome: BenchmarkOutcome?
    private(set) var lastError: String?
    private(set) var lastFinishedAt: Date?

    private var cancellation: BenchmarkCancellationToken?
    private var task: Task<Void, Never>?

    /// Called on the main actor after a benchmark finishes successfully.
    var onBenchmarkFinished: ((String, Double) -> Void)?

    init(store: BatteryHistoryStore?, settings: SettingsStore) {
        self.store = store
        self.settings = settings
    }

    var cpuBenchmark: CPUBenchmark { CPUBenchmark() }
    var gpuBenchmark: GPUBenchmark { GPUBenchmark() }
    var memoryBenchmark: MemoryBenchmark { MemoryBenchmark() }
    var storageBenchmark: StorageBenchmark {
        StorageBenchmark(sizeMB: max(100, settings.settings.storageBenchmarkSizeMB))
    }
    var networkBenchmark: NetworkBenchmark { NetworkBenchmark() }

    func run(_ benchmark: Benchmark) {
        guard !isRunning else { return }
        if settings.settings.thermalSafeguardEnabled,
           ProcessInfo.processInfo.thermalState.rawValue >= AppConstants.Benchmark.thermalSafeguardState.rawValue {
            lastError = "Thermal safeguard: the device is in a high thermal state (\(ThermalMonitor.name(for: ProcessInfo.processInfo.thermalState))). Benchmark not started."
            return
        }

        let token = BenchmarkCancellationToken()
        cancellation = token
        isRunning = true
        progress = 0
        currentBenchmarkName = benchmark.name
        lastOutcome = nil
        lastError = nil

        task = Task { [weak self] in
            do {
                let outcome = try await Task.detached(priority: .userInitiated) {
                    try await benchmark.run(
                        progress: { value in
                            await MainActor.run { self?.progress = value }
                        },
                        cancelled: { await token.isCancelled() }
                    )
                }.value
                await MainActor.run {
                    self?.finish(benchmark: benchmark, outcome: outcome)
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.isRunning = false
                    self.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    func cancel() {
        cancellation?.cancel()
    }

    private func finish(benchmark: Benchmark, outcome: BenchmarkOutcome) {
        isRunning = false
        progress = 1
        lastOutcome = outcome
        lastFinishedAt = Date()
        store?.addBenchmarkResult(
            category: benchmark.category,
            name: benchmark.name,
            score: outcome.score,
            metricsJSON: (try? JSONSerialization.data(withJSONObject: outcome.metrics))?.base64EncodedString() ?? ""
        )
        onBenchmarkFinished?(benchmark.name, outcome.score)
    }

    var latestResultsByCategory: [String: BenchmarkOutcome] {
        guard let lastOutcome, let currentBenchmarkName else { return [:] }
        return [currentBenchmarkName: lastOutcome]
    }
}

actor BenchmarkCancellationToken {
    private var cancelled = false

    func cancel() {
        cancelled = true
    }

    func isCancelled() -> Bool {
        cancelled
    }
}