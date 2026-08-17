import Foundation

/// Storage benchmark. Creates temporary test files and ALWAYS deletes them.
/// Never fills the user's storage: size is clamped to a fraction of free space.
struct StorageBenchmark: Benchmark {
    let category = "Storage"
    let name = "Storage Benchmark"
    let detailName = "Sequential & small-file I/O"
    let requestedSizeMB: Int

    init(sizeMB: Int = 200) {
        requestedSizeMB = sizeMB
    }

    func run(progress: @escaping @Sendable (Double) async -> Void, cancelled: @escaping @Sendable () async -> Bool) async throws -> BenchmarkOutcome {
        let sizeMB = clampedSizeMB()
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("devicelab-bench-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let chunk = Data(repeating: 0x5C, count: 8 * 1024 * 1024)
        let bigFile = workDir.appendingPathComponent("big.bin")

        // Sequential write
        let writeSeconds = try BenchmarkMeasurement.measureSeconds {
            let handle = try FileHandle(forWritingTo: bigFile)
            defer { try? handle.close() }
            let chunks = sizeMB / 8
            for _ in 0..<chunks {
                try handle.write(contentsOf: chunk)
            }
        }
        if await cancelled() { throw BenchmarkError.cancelled }
        await progress(0.3)

        // Sequential read
        let readSeconds = try BenchmarkMeasurement.measureSeconds {
            let handle = try FileHandle(forReadingFrom: bigFile)
            defer { try? handle.close() }
            while try handle.read(upToCount: chunk.count)?.isEmpty == false {}
        }
        if await cancelled() { throw BenchmarkError.cancelled }
        await progress(0.6)

        // Small-file workload
        let smallCount = 200
        let smallSize = 8 * 1024
        let smallData = Data(repeating: 0xA1, count: smallSize)
        var smallWriteSeconds: TimeInterval = 0
        var smallReadSeconds: TimeInterval = 0
        smallWriteSeconds = try BenchmarkMeasurement.measureSeconds {
            for i in 0..<smallCount {
                try smallData.write(to: workDir.appendingPathComponent("small-\(i).bin"))
            }
        }
        smallReadSeconds = try BenchmarkMeasurement.measureSeconds {
            for i in 0..<smallCount {
                _ = try Data(contentsOf: workDir.appendingPathComponent("small-\(i).bin"))
            }
        }
        if await cancelled() { throw BenchmarkError.cancelled }
        await progress(0.85)

        // Random-like workload on a sparse region of the big file
        var randomSeconds: TimeInterval = 0
        randomSeconds = try BenchmarkMeasurement.measureSeconds {
            let handle = try FileHandle(forUpdating: bigFile)
            defer { try? handle.close() }
            let regionCount = 64
            for i in 0..<regionCount {
                let offset = UInt64((i * 7919) % max(1, (sizeMB * 1024 * 1024) / 1024)) * 1024
                try handle.seek(toOffset: offset)
                try handle.write(contentsOf: chunk)
            }
        }
        await progress(1.0)

        let writeMBps = Double(sizeMB) / writeSeconds
        let readMBps = Double(sizeMB) / readSeconds
        let smallWriteOpsPerSec = Double(smallCount) / smallWriteSeconds
        let smallReadOpsPerSec = Double(smallCount) / smallReadSeconds
        let randomMBps = Double(64 * 8) / randomSeconds

        let writeScore = BenchmarkMeasurement.normalizedScore(workPerSecond: writeMBps, reference: 900.0)
        let readScore = BenchmarkMeasurement.normalizedScore(workPerSecond: readMBps, reference: 1_100.0)
        let smallWriteScore = BenchmarkMeasurement.normalizedScore(workPerSecond: smallWriteOpsPerSec, reference: 120.0)
        let smallReadScore = BenchmarkMeasurement.normalizedScore(workPerSecond: smallReadOpsPerSec, reference: 200.0)
        let randomScore = BenchmarkMeasurement.normalizedScore(workPerSecond: randomMBps, reference: 250.0)
        let score = (writeScore + readScore + smallWriteScore + smallReadScore + randomScore) / 5

        let detail = """
        Test size: \(sizeMB) MB (clamped to available free space)
        Sequential write: \(String(format: "%.0f MB/s", writeMBps))
        Sequential read: \(String(format: "%.0f MB/s", readMBps))
        Small files (200 × 8 KB): \(String(format: "%.0f write/s", smallWriteOpsPerSec)) · \(String(format: "%.0f read/s", smallReadOpsPerSec))
        Random-like: \(String(format: "%.0f MB/s", randomMBps))

        All temporary files were removed after the test.
        """

        return BenchmarkOutcome(
            score: score,
            metrics: [
                "writeScore": writeScore,
                "readScore": readScore,
                "smallWriteScore": smallWriteScore,
                "smallReadScore": smallReadScore,
                "randomScore": randomScore,
                "writeMBps": writeMBps,
                "readMBps": readMBps,
            ],
            detail: detail
        )
    }

    private func clampedSizeMB() -> Int {
        if let info = StorageMonitor.volumeInfo() {
            let freeMB = Int(info.available / 1_048_576)
            return min(requestedSizeMB, max(50, freeMB / 4))
        }
        return requestedSizeMB
    }
}