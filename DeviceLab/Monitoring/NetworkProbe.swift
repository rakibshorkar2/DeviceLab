import Foundation
import Network

// MARK: - Network probe results

struct NetworkProbeResult: Sendable, Equatable {
    var latencyMs: Double?
    var jitterMs: Double?
    var packetLossPercent: Double?
    var dnsEstimateMs: Double?
    var measuredAt: Date?
    var attempts = 0
    var successes = 0
}

struct SpeedTestResult: Sendable, Equatable {
    var downMbps: Double?
    var upMbps: Double?
    var downBytes: Int64 = 0
    var upBytes: Int64 = 0
    var measuredAt: Date?
}

enum NetworkProbeError: LocalizedError {
    case noConnectivity
    case downloadFailed
    case uploadFailed

    var errorDescription: String? {
        switch self {
        case .noConnectivity: return "No network connectivity."
        case .downloadFailed: return "Download test failed."
        case .uploadFailed: return "Upload test failed."
        }
    }
}

// MARK: - Probe implementation
//
// All network measurements are made by DeviceLab against public endpoints.
// Latency is a TCP handshake-time approximation (ICMP is not available to
// sandboxed apps), clearly labeled as measured by DeviceLab.

enum NetworkProbe {
    /// Measures TCP handshake latency against public resolver hosts.
    static func measureLatency(samplesPerHost: Int = 3, timeout: TimeInterval = 2.0) async -> NetworkProbeResult {
        var samples: [Double] = []
        var attempts = 0
        var successes = 0

        for host in AppConstants.Network.latencyTargets {
            for _ in 0..<samplesPerHost {
                attempts += 1
                if let latency = await tcpConnectLatency(host: host, port: AppConstants.Network.testPort, timeout: timeout) {
                    successes += 1
                    samples.append(latency)
                }
            }
        }

        let dns = await estimateDNSResolution()

        var result = NetworkProbeResult(measuredAt: Date(), attempts: attempts, successes: successes)
        if let mean = mean(samples) {
            result.latencyMs = mean * 1000
            if let jitter = meanAbsoluteDeviation(samples) {
                result.jitterMs = jitter * 1000
            }
        }
        if attempts > 0 {
            result.packetLossPercent = Double(attempts - successes) / Double(attempts) * 100
        }
        result.dnsEstimateMs = dns.map { $0 * 1000 }
        return result
    }

    /// TCP connect timing against a host:port. Public NWConnection API.
    static func tcpConnectLatency(host: String, port: Int, timeout: TimeInterval) async -> TimeInterval? {
        await withCheckedContinuation { continuation in
            let start = Date()
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(integerLiteral: UInt16(port)),
                using: .tcp
            )
            var finished = false

            func finish(_ value: TimeInterval?) {
                guard !finished else { return }
                finished = true
                connection.cancel()
                continuation.resume(returning: value)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(Date().timeIntervalSince(start))
                case .failed:
                    finish(nil)
                case .cancelled:
                    finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                finish(nil)
            }
        }
    }

    /// DNS resolution estimate: difference between TCP latency to a hostname and
    /// to its literal IP address. Labeled as a DeviceLab estimate, not a DNS server metric.
    static func estimateDNSResolution() async -> TimeInterval? {
        let host = AppConstants.Network.dnsComparisonHost
        let ip = AppConstants.Network.latencyTargets[0]
        guard let hostLatency = await tcpConnectLatency(host: host, port: AppConstants.Network.testPort, timeout: 3.0),
              let ipLatency = await tcpConnectLatency(host: ip, port: AppConstants.Network.testPort, timeout: 3.0) else {
            return nil
        }
        return max(0, hostLatency - ipLatency)
    }

    /// Downloads a fixed-size payload and measures throughput.
    static func measureDownload() async throws -> (bytes: Int64, seconds: TimeInterval) {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: config)
        let start = Date()
        let (data, response) = try await session.data(from: AppConstants.Network.downloadURL)
        let elapsed = Date().timeIntervalSince(start)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, elapsed > 0 else {
            throw NetworkProbeError.downloadFailed
        }
        return (Int64(data.count), elapsed)
    }

    /// Uploads a fixed-size payload and measures throughput.
    static func measureUpload(byteCount: Int = 20_000_000) async throws -> (bytes: Int64, seconds: TimeInterval) {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 60
        let session = URLSession(configuration: config)

        var request = URLRequest(url: AppConstants.Network.uploadURL)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        var body = Data(count: byteCount)
        body.withUnsafeMutableBytes { ptr in
            if let base = ptr.baseAddress {
                var rng = SystemRandomNumberGenerator()
                (0..<byteCount).forEach { index in
                    base.storeBytes(of: UInt8.random(in: 0...255, using: &rng), toByteOffset: index, as: UInt8.self)
                }
            }
        }

        let start = Date()
        let (data, response) = try await session.upload(for: request, from: body)
        let elapsed = Date().timeIntervalSince(start)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, elapsed > 0 else {
            throw NetworkProbeError.uploadFailed
        }
        return (Int64(data.count), elapsed)
    }

    private static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func meanAbsoluteDeviation(_ values: [Double]) -> Double? {
        guard let mean = mean(values) else { return nil }
        return values.reduce(0) { $0 + abs($1 - mean) } / Double(values.count)
    }
}