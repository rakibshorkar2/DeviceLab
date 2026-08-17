import Foundation
import CryptoKit
import Compression
import CoreGraphics

/// CPU benchmark built from real workloads:
/// integer math, floating point, SHA-256 hashing, zlib compression,
/// JSON processing, matrix multiplication, image drawing, multithread.
/// Scores are DeviceLab-normalized against internal calibration constants.
struct CPUBenchmark: Benchmark {
    let category = "CPU"
    let name = "CPU Benchmark"
    let detailName = "Single & multi-thread workloads"
    let roundCount = 3

    // MARK: Workloads

    private enum Workload: CaseIterable {
        case integer
        case float
        case hash
        case compression
        case json
        case matrix
        case image

        var referenceUnitsPerSecond: Double {
            switch self {
            case .integer: return 1.6e9
            case .float: return 1.0e8
            case .hash: return 1.4e9
            case .compression: return 3.5e8
            case .json: return 260
            case .matrix: return 2.8e11
            case .image: return 34
            }
        }
    }

    func run(progress: @escaping @Sendable (Double) async -> Void, cancelled: @escaping @Sendable () async -> Bool) async throws -> BenchmarkOutcome {
        var singleScores: [Double] = []
        var multiScores: [Double] = []

        let totalSteps = (Workload.allCases.count + 1) * roundCount
        var step = 0

        for _ in 0..<roundCount {
            for workload in Workload.allCases {
                if await cancelled() { throw BenchmarkError.cancelled }
                let units = Self.runSingle(workload)
                let normalized = BenchmarkMeasurement.normalizedScore(workPerSecond: units, reference: workload.referenceUnitsPerSecond)
                singleScores.append(normalized)
                step += 1
                await progress(Double(step) / Double(totalSteps))
            }
            if await cancelled() { throw BenchmarkError.cancelled }
            let multiUnits = Self.runMultiInteger()
            let multiNormalized = BenchmarkMeasurement.normalizedScore(
                workPerSecond: multiUnits,
                reference: multiReference
            )
            multiScores.append(multiNormalized)
            step += 1
            await progress(Double(step) / Double(totalSteps))
        }

        let single = singleScores.reduce(0, +) / Double(singleScores.count)
        let multi = multiScores.reduce(0, +) / Double(multiScores.count)
        let consistency = Self.consistencyOf(singleScores)

        let detail = """
        Single-thread score: \(Int(single))
        Multi-thread score: \(Int(multi))
        Round consistency: \(Int(consistency))% (min/mean of \(roundCount) rounds)
        Workloads: integer, floating point, SHA-256, zlib, JSON, matrix, image, multithread
        Thermal state during run: \(ThermalMonitor.name(for: ProcessInfo.processInfo.thermalState))

        Scores are DeviceLab-normalized (0–10,000) against internal calibration
        constants, derived from actual measured execution times.
        """

        let outcome = BenchmarkOutcome(
            score: single,
            metrics: ["single": single, "multi": multi, "consistency": consistency],
            detail: detail
        )
        return outcome
    }

    private var multiReference: Double {
        let cores = ProcessInfo.processInfo.activeProcessorCount
        return 1.5e9 * Double(max(1, cores))
    }

    // MARK: Individual workloads (units = "work units per second")

    private static func runSingle(_ workload: Workload) -> Double {
        switch workload {
        case .integer:
            return Self.integerWorkload()
        case .float:
            return Self.floatWorkload()
        case .hash:
            return Self.hashWorkload()
        case .compression:
            return Self.compressionWorkload()
        case .json:
            return Self.jsonWorkload()
        case .matrix:
            return Self.matrixWorkload()
        case .image:
            return Self.imageWorkload()
        }
    }

    @inline(never)
    private static func consume(_ value: UInt64) {
        if value == UInt64.max { print("unreachable") }
    }

    static func integerWorkload() -> Double {
        let iterations = 150_000_000
        var sum: UInt64 = 0
        let seconds = BenchmarkMeasurement.measureSeconds {
            for i in 0..<iterations {
                sum = sum &* 31 &+ UInt64(i)
            }
        }
        consume(sum)
        return Double(iterations) / seconds
    }

    static func floatWorkload() -> Double {
        let iterations = 40_000_000
        var acc = 0.0
        let seconds = BenchmarkMeasurement.measureSeconds {
            for i in 0..<iterations {
                acc += sin(Double(i % 65_536) * 0.001)
            }
        }
        consume(UInt64(bitPattern: Int64(acc)))
        return Double(iterations) / seconds
    }

    static func hashWorkload() -> Double {
        let chunk = Data(repeating: 0x5A, count: 1_048_576)
        let iterations = 8
        var total = 0
        let seconds = BenchmarkMeasurement.measureSeconds {
            for _ in 0..<iterations {
                let digest = SHA256.hash(data: chunk)
                total = digest.reduce(0) { $0 + Int($1) }
            }
        }
        consume(UInt64(total))
        return Double(iterations * chunk.count) / seconds
    }

    static func compressionWorkload() -> Double {
        let source = Data((0..<1_048_576).map { UInt8($0 % 251) })
        let destinationSize = 2 * source.count
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationSize)
        defer { destination.deallocate() }
        let iterations = 6
        var total = 0
        let seconds = source.withUnsafeBytes { sourcePtr in
            BenchmarkMeasurement.measureSeconds {
                for _ in 0..<iterations {
                    let written = compression_encode_buffer(
                        destination,
                        destinationSize,
                        sourcePtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        source.count,
                        nil,
                        COMPRESSION_ZLIB
                    )
                    total = written
                }
            }
        }
        consume(UInt64(total))
        return Double(iterations * source.count) / seconds
    }

    static func jsonWorkload() -> Double {
        let payload: [String: Any] = [
            "id": 42,
            "name": "DeviceLab JSON payload",
            "values": (0..<512).map { ["index": $0, "value": Double($0) * 1.5] },
        ]
        let iterations = 200
        var total = 0
        let seconds = BenchmarkMeasurement.measureSeconds {
            for _ in 0..<iterations {
                if let data = try? JSONSerialization.data(withJSONObject: payload),
                   let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    total += parsed.isEmpty ? 0 : 1
                }
            }
        }
        consume(UInt64(total))
        return Double(iterations) / seconds
    }

    static func matrixWorkload() -> Double {
        let size = 384
        let n = size * size
        var a = [Double](repeating: 0.5, count: n)
        var b = [Double](repeating: 0.25, count: n)
        var c = [Double](repeating: 0, count: n)
        var total = 0.0
        let seconds = BenchmarkMeasurement.measureSeconds {
            for i in 0..<size {
                for k in 0..<size {
                    let aik = a[i * size + k]
                    for j in 0..<size {
                        c[i * size + j] += aik * b[k * size + j]
                    }
                }
            }
            total = c[n - 1]
        }
        consume(UInt64(bitPattern: Int64(total)))
        let multiplications = Double(size) * Double(size) * Double(size)
        return multiplications / seconds
    }

    static func imageWorkload() -> Double {
        guard let context = CGContext(
            data: nil,
            width: 512,
            height: 512,
            bitsPerComponent: 8,
            bytesPerRow: 512 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        let iterations = 60
        var total = 0
        let seconds = BenchmarkMeasurement.measureSeconds {
            for i in 0..<iterations {
                let hue = CGFloat(i % 20) / 20
                context.setFillColor(CGColor(red: hue, green: 0.5, blue: 0.8, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
                context.setFillColor(CGColor(red: 0.2, green: 0.9, blue: 0.3, alpha: 0.6))
                for _ in 0..<200 {
                    context.fillEllipse(in: CGRect(
                        x: CGFloat((i * 37 + total) % 480),
                        y: CGFloat((i * 53 + total) % 480),
                        width: 24,
                        height: 24
                    ))
                    total += 1
                }
                _ = context.makeImage()
            }
        }
        consume(UInt64(total))
        return Double(iterations) / seconds
    }

    static func runMultiInteger() -> Double {
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let perCore = 60_000_000
        var sums = [UInt64](repeating: 0, count: cores)
        let seconds = BenchmarkMeasurement.measureSeconds {
            sums.withUnsafeMutableBufferPointer { sumsPtr in
                DispatchQueue.concurrentPerform(iterations: cores) { core in
                    var sum: UInt64 = 0
                    for i in 0..<perCore {
                        sum = sum &* 29 &+ UInt64(i) &+ UInt64(core)
                    }
                    sumsPtr[core] = sum
                }
            }
        }
        consume(sums.reduce(0, +))
        return Double(cores * perCore) / seconds
    }

    static func consistencyOf(_ scores: [Double]) -> Double {
        guard let min = scores.min(), !scores.isEmpty else { return 0 }
        let mean = scores.reduce(0, +) / Double(scores.count)
        guard mean > 0 else { return 0 }
        return min / mean * 100
    }
}