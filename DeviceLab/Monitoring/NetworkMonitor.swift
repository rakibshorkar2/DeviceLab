import Foundation
import Network

/// Network monitor built on the Network framework (public API).
/// Latency/jitter/packet loss are DeviceLab TCP-handshake measurements.
/// Throughput is only measured on demand (speed test) to avoid battery impact.
@MainActor
final class NetworkMonitor: BaseMonitor {
    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "devicelab.pathmonitor")
    private var currentPath: NWPath?
    private var probeLoop: Task<Void, Never>?

    private(set) var interfaceLabel: String?
    private(set) var connectivityLabel: String?
    private(set) var latencyMs: Double?
    private(set) var jitterMs: Double?
    private(set) var packetLossPercent: Double?
    private(set) var dnsEstimateMs: Double?
    private(set) var downMbps: Double?
    private(set) var upMbps: Double?
    private(set) var supportsIPv4 = true
    private(set) var supportsIPv6 = false
    private(set) var isExpensive = false
    private(set) var isConstrained = false
    private(set) var lastProbeAt: Date?

    init() {
        super.init(kind: .network)
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.handlePath(path)
            }
        }
        pathMonitor.start(queue: pathQueue)
    }

    override func start() {
        super.start()
        probeLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.currentPath?.status == .satisfied {
                    let result = await NetworkProbe.measureLatency()
                    self.latencyMs = result.latencyMs
                    self.jitterMs = result.jitterMs
                    self.packetLossPercent = result.packetLossPercent
                    self.dnsEstimateMs = result.dnsEstimateMs
                    self.lastProbeAt = result.measuredAt
                    await self.refresh()
                }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    override func stop() {
        probeLoop?.cancel()
        probeLoop = nil
        super.stop()
    }

    private func handlePath(_ path: NWPath) {
        currentPath = path
        isExpensive = path.isExpensive
        isConstrained = path.isConstrained
        supportsIPv4 = path.supportsIPv4
        supportsIPv6 = path.supportsIPv6

        switch path.status {
        case .satisfied:
            connectivityLabel = "Connected"
        case .unsatisfied:
            connectivityLabel = "Not connected"
        case .requiresConnection:
            connectivityLabel = "Needs connection"
        @unknown default:
            connectivityLabel = "Unknown"
        }

        if path.usesInterfaceType(.wifi) {
            interfaceLabel = "Wi-Fi"
        } else if path.usesInterfaceType(.cellular) {
            interfaceLabel = "Cellular"
        } else if path.usesInterfaceType(.wiredEthernet) {
            interfaceLabel = "Ethernet"
        } else if path.usesInterfaceType(.other) {
            interfaceLabel = "Other"
        } else {
            interfaceLabel = "Offline"
        }
        Task { await refresh() }
    }

    override func refresh() async {
        let now = Date()
        var subtextParts: [String] = []
        if let interfaceLabel { subtextParts.append(interfaceLabel) }
        if let connectivityLabel { subtextParts.append(connectivityLabel) }
        if isExpensive { subtextParts.append("Expensive") }
        var subtext = subtextParts.joined(separator: " · ")
        if subtext.isEmpty { subtext = "No interface" }

        let valueText: String
        var numeric: Double?
        if currentPath?.status == .satisfied {
            if let latencyMs {
                valueText = String(format: "%.0f ms", latencyMs)
                numeric = latencyMs
                subtext += String(format: " · Jitter %.0f ms", jitterMs ?? 0)
                if let packetLossPercent, packetLossPercent > 0 {
                    subtext += String(format: " · Loss %.0f%%", packetLossPercent)
                }
            } else {
                valueText = "Measuring…"
            }
        } else {
            valueText = "Offline"
        }

        let detail = """
        Connectivity: \(connectivityLabel ?? "—") via \(interfaceLabel ?? "—")
        IPv4: \(supportsIPv4 ? "supported" : "not supported") · IPv6: \(supportsIPv6 ? "supported" : "not supported")
        Expensive (cellular): \(isExpensive ? "yes" : "no") · Constrained: \(isConstrained ? "yes" : "no")
        Latency: \(latencyMs.map { String(format: "%.0f ms", $0) } ?? "—") (TCP handshake approximation)
        Jitter: \(jitterMs.map { String(format: "%.0f ms", $0) } ?? "—")
        Packet loss: \(packetLossPercent.map { String(format: "%.0f%%", $0) } ?? "—") (connect-failure approximation)
        DNS estimate: \(dnsEstimateMs.map { String(format: "%.0f ms", $0) } ?? "—")
        Download/upload: measured on demand via Network Diagnostics speed test.
        """

        updateSnapshot(MetricSnapshot(
            kind: .network,
            valueText: valueText,
            subtext: subtext,
            detail: detail,
            status: currentPath?.status == .satisfied ? .normal : .warning,
            provenance: .measuredByDeviceLab,
            updatedAt: now,
            numericValue: numeric,
            unit: "ms"
        ))
    }

    /// Called by the speed test to publish results into the snapshot.
    func recordSpeedTest(down: Double?, up: Double?) {
        downMbps = down
        upMbps = up
        Task { await refresh() }
    }

    deinit {
        pathMonitor.cancel()
    }
}