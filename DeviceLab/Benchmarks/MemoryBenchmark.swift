import Foundation
import Compression
import Darwin

/// Memory benchmark measuring DeviceLab-controlled workloads:
/// allocation speed, copy speed, read/write bandwidth, compression.
/// Explicitly NOT a measurement of physical DRAM specifications.
struct MemoryBenchmark: Benchmark {
    let category = "Memory"
    let name = "Memory Benchmark"
    let detailName = "Allocation, copy, bandwidth, compression"

    func run(progress: @escaping @Sendable (Double) async -> Void, cancelled: @escaping @Sendable () async -> Bool) async throws -> BenchmarkOutcome {
        // Allocation
        let blockSize = 16 * 1024 * 1024
        var blocks: [[UInt8]] = []
        let allocSeconds = BenchmarkMeasurement.measureSeconds {
            for _ in 0..<16 {
                blocks.append([UInt8](repeating: 0xAA, count: blockSize))
            }
        }
        if await cancelled() { throw BenchmarkError.cancelled }
        await progress(0.2)

        // Copy + bandwidth on a 64 MB working set
        var source = [UInt8](repeating: 0x3C, count: 64 * 1024 * 1024)
        var target = [UInt8](repeating: 0, count: 64 * 1024 * 1024)
        let copyIterations = 6
        let copySeconds: TimeInterval = try BenchmarkMeasurement.measureSeconds {
            for _ in 0..<copyIterations {
                source.withUnsafeBytes { src in
                    target.withUnsafeMutableBytes { dst in
                        if let s = src.baseAddress, let d = dst.baseAddress {
                            memcpy(d, s, 64 * 1024 * 1024)
                        }
                    }
                }
            }
        }
        if await cancelled() { throw BenchmarkError.cancelled }
        await progress(0.5)

        // Read-modify-write bandwidth
        var bandwidthTotal: UInt64 = 0
        let bandwidthSeconds = BenchmarkMeasurement.measureSeconds {
            source.withUnsafeMutableBytes { buf in
                if let base = buf.baseAddress {
                    let ptr = base.assumingMemoryBound(to: UInt64.self)
                    let count = 64 * 1024 * 1024 / 8
                    for i in 0..<count {
                        ptr[i] &+= 1
                    }
                    bandwidthTotal = ptr[count - 1]
                }
            }
        }
        if await cancelled() { throw BenchmarkError.cancelled }
        await progress(0.7)

        // Compression workload
        let compressData = Data(repeating: 0x7B, count: 64 * 1024 * 1024)
        let compressSeconds = try BenchmarkMeasurement.measureSeconds {
            _ = try compressData.compressed(using: .zlib)
        }
        await progress(0.9)

        let allocGBps = Double(16 * blockSize) / allocSeconds / 1e9
        let copyGBps = Double(copyIterations * 64 * 1024 * 1024) / copySeconds / 1e9
        let bandwidthGBps = Double(64 * 1024 * 1024) / bandwidthSeconds / 1e9 * 2 // read + write
        let compressGBps = Double(compressData.count) / compressSeconds / 1e9
        _ = bandwidthTotal

        let allocScore = BenchmarkMeasurement.normalizedScore(workPerSecond: allocGBps, reference: 8.0)
        let copyScore = BenchmarkMeasurement.normalizedScore(workPerSecond: copyGBps, reference: 45.0)
        let bandwidthScore = BenchmarkMeasurement.normalizedScore(workPerSecond: bandwidthGBps, reference: 35.0)
        let compressScore = BenchmarkMeasurement.normalizedScore(workPerSecond: compressGBps, reference: 1.5)
        let score = (allocScore + copyScore + bandwidthScore + compressScore) / 4

        let detail = """
        Allocation: \(String(format: "%.2f GB/s", allocGBps))
        Copy (memcpy): \(String(format: "%.1f GB/s", copyGBps))
        Read/write: \(String(format: "%.1f GB/s", bandwidthGBps))
        Compression (zlib): \(String(format: "%.2f GB/s", compressGBps))

        DeviceLab Memory Benchmark — measures DeviceLab-controlled workloads.
        This is NOT a direct measurement of physical DRAM specifications.
        """

        return BenchmarkOutcome(
            score: score,
            metrics: [
                "allocScore": allocScore,
                "copyScore": copyScore,
                "bandwidthScore": bandwidthScore,
                "compressScore": compressScore,
                "copyGBps": copyGBps,
                "bandwidthGBps": bandwidthGBps,
            ],
            detail: detail
        )
    }
}