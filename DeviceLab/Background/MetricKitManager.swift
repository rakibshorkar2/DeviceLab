import Foundation
import MetricKit
import Observation

/// MetricKit integration. The system delivers performance metrics for
/// DEVICELAB's own process (CPU time, CPU instructions, GPU time, peak
/// memory). These are real system-collected values for our app only.
@MainActor
@Observable
final class MetricKitManager: NSObject, MXMetricManagerSubscriber {
    private(set) var lastPayloadAt: Date?
    private(set) var cumulativeCPUSeconds: Double?
    private(set) var cpuInstructions: Double?
    private(set) var peakMemoryMB: Double?
    private(set) var gpuTimeSeconds: Double?
    private(set) var payloadCount = 0
    private(set) var lastPayloadSummary: String?

    var onMetricsReceived: (() -> Void)?

    func subscribe() {
        MXMetricManager.shared.add(self)
    }

    func unsubscribe() {
        MXMetricManager.shared.remove(self)
    }

    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        let cpuSeconds = payloads.compactMap { $0.cpuMetrics?.cumulativeCPUTime.converted(to: .seconds).value }.reduce(0, +)
        let instructions = payloads.compactMap { $0.cpuMetrics?.cumulativeCPUInstructions.value }.reduce(0, +)
        let gpuSeconds = payloads.compactMap { $0.gpuMetrics?.cumulativeGPUTime.converted(to: .seconds).value }.reduce(0, +)
        let peakMB = payloads.compactMap { $0.memoryMetrics?.peakMemoryUsage.converted(to: .bytes).value }.max() ?? 0
        let at = Date()

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.lastPayloadAt = at
            self.payloadCount += payloads.count
            if cpuSeconds > 0 { self.cumulativeCPUSeconds = cpuSeconds }
            if instructions > 0 { self.cpuInstructions = instructions }
            if gpuSeconds > 0 { self.gpuTimeSeconds = gpuSeconds }
            if peakMB > 0 { self.peakMemoryMB = peakMB }
            self.lastPayloadSummary = """
            MetricKit payload\(payloads.count == 1 ? "" : "s") received at \(Formatters.dateTime(at)):
            DeviceLab CPU time: \(String(format: "%.1f s", cpuSeconds))
            CPU instructions: \(String(format: "%.0f M", instructions / 1e6))
            DeviceLab GPU time: \(String(format: "%.2f s", gpuSeconds))
            Peak memory: \(peakMB > 0 ? String(format: "%.0f MB", peakMB / 1_048_576) : "—")
            """
            self.onMetricsReceived?()
        }
    }
}