import Foundation
import Observation

/// On-demand network diagnostics: latency/jitter/packet loss/DNS estimate
/// plus download/upload throughput against public endpoints.
@MainActor
@Observable
final class NetworkDiagnosticsEngine {
    private(set) var phase: Phase = .idle
    private(set) var probe = NetworkProbeResult()
    private(set) var speed = SpeedTestResult()
    private(set) var errorMessage: String?

    private weak var networkMonitor: NetworkMonitor?

    enum Phase: Equatable {
        case idle
        case latency
        case download
        case upload
        case done
    }

    var isRunning: Bool { phase != .idle && phase != .done }

    init(networkMonitor: NetworkMonitor?) {
        self.networkMonitor = networkMonitor
    }

    func runFullTest() async {
        errorMessage = nil
        speed = SpeedTestResult()
        probe = NetworkProbeResult()

        phase = .latency
        probe = await NetworkProbe.measureLatency()

        do {
            phase = .download
            let down = try await NetworkProbe.measureDownload()
            speed.downBytes = down.bytes
            speed.downMbps = Double(down.bytes) * 8 / 1_000_000 / down.seconds

            phase = .upload
            let up = try await NetworkProbe.measureUpload()
            speed.upBytes = up.bytes
            speed.upMbps = Double(up.bytes) * 8 / 1_000_000 / up.seconds

            speed.measuredAt = Date()
        } catch {
            errorMessage = error.localizedDescription
        }

        networkMonitor?.recordSpeedTest(down: speed.downMbps, up: speed.upMbps)
        phase = .done
    }

    func runProbeOnly() async {
        errorMessage = nil
        phase = .latency
        probe = await NetworkProbe.measureLatency()
        phase = .done
    }

    func reset() {
        phase = .idle
        probe = NetworkProbeResult()
        speed = SpeedTestResult()
        errorMessage = nil
    }
}