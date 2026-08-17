import Foundation

/// Network benchmark: latency/jitter + download/upload throughput
/// against public endpoints. All values are DeviceLab measurements.
struct NetworkBenchmark: Benchmark {
    let category = "Network"
    let name = "Network Benchmark"
    let detailName = "Latency, download, upload"

    func run(progress: @escaping @Sendable (Double) async -> Void, cancelled: @escaping @Sendable () async -> Bool) async throws -> BenchmarkOutcome {
        await progress(0.1)
        let probe = await NetworkProbe.measureLatency()
        if await cancelled() { throw BenchmarkError.cancelled }
        await progress(0.35)

        let down = try await NetworkProbe.measureDownload()
        if await cancelled() { throw BenchmarkError.cancelled }
        await progress(0.7)

        let up = try await NetworkProbe.measureUpload()
        await progress(1.0)

        let downMbps = Double(down.bytes) * 8 / 1_000_000 / down.seconds
        let upMbps = Double(up.bytes) * 8 / 1_000_000 / up.seconds

        let latencyScore: Double = {
            guard let latency = probe.latencyMs, latency > 0 else { return 0 }
            return BenchmarkMeasurement.normalizedScore(workPerSecond: 1.0 / latency, reference: 1.0 / 25.0)
        }()
        let downScore = BenchmarkMeasurement.normalizedScore(workPerSecond: downMbps, reference: 900.0)
        let upScore = BenchmarkMeasurement.normalizedScore(workPerSecond: upMbps, reference: 300.0)
        let score = latencyScore * 0.3 + downScore * 0.4 + upScore * 0.3

        let detail = """
        Latency: \(probe.latencyMs.map { String(format: "%.0f ms", $0) } ?? "—") (TCP handshake)
        Jitter: \(probe.jitterMs.map { String(format: "%.0f ms", $0) } ?? "—")
        Packet loss: \(probe.packetLossPercent.map { String(format: "%.0f%%", $0) } ?? "—")
        Download: \(String(format: "%.0f Mbps", downMbps))
        Upload: \(String(format: "%.0f Mbps", upMbps))

        Measured by DeviceLab against public endpoints.
        """

        return BenchmarkOutcome(
            score: score,
            metrics: [
                "latencyScore": latencyScore,
                "downScore": downScore,
                "upScore": upScore,
                "downMbps": downMbps,
                "upMbps": upMbps,
                "latencyMs": probe.latencyMs ?? -1,
            ],
            detail: detail
        )
    }
}