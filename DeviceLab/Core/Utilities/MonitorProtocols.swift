import Foundation

// MARK: - Monitor protocol & base implementation
//
// All monitors conform to DeviceMonitor and expose a snapshot with provenance.
// BaseMonitor owns the sampling task lifecycle so no monitor can leak a timer.

@MainActor
protocol DeviceMonitor: AnyObject {
    var kind: MetricKind { get }
    var availability: MonitorAvailability { get }
    var snapshot: MetricSnapshot { get }
    var isRunning: Bool { get }
    func start()
    func stop()
    func refresh() async
}

@MainActor
class BaseMonitor: DeviceMonitor {
    let kind: MetricKind
    private(set) var availability: MonitorAvailability = .available
    private(set) var snapshot: MetricSnapshot
    private(set) var isRunning = false
    var samplingInterval: Duration = .seconds(5)

    private var task: Task<Void, Never>?

    init(kind: MetricKind) {
        self.kind = kind
        self.snapshot = MetricSnapshot.placeholder(kind: kind)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: self.samplingInterval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    func refresh() async {}

    func setAvailability(_ value: MonitorAvailability) {
        availability = value
        if case .unavailable(let reason) = value {
            snapshot = MetricSnapshot.unavailable(kind: kind, reason: reason)
        } else if case .notSupported(let reason) = value {
            snapshot = MetricSnapshot.unavailable(kind: kind, reason: reason)
        }
    }

    func updateSnapshot(_ newSnapshot: MetricSnapshot) {
        snapshot = newSnapshot
    }
}