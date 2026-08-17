import Foundation
import Observation

/// Aggregate snapshot of all monitored values, used by the dashboard
/// and by the Live Activity bridge.
struct DeviceData: Sendable {
    var cpuPercent: Double?
    var ownCPUPercent: Double?
    var memoryAvailableGB: Double?
    var memoryFootprintMB: Double?
    var storageFreeGB: Double?
    var storageTotalGB: Double?
    var batteryLevel: Double?
    var isCharging: Bool?
    var chargeRatePerHour: Double?
    var thermalState: String?
    var networkStatus: String?
    var networkLatencyMs: Double?
    var networkDownMbps: Double?
    var networkUpMbps: Double?
    var gpuLabel: String?
    var isLowPowerMode: Bool?
    var updatedAt: Date?

    static let empty = DeviceData()

    var liveValues: LiveMetricValues {
        LiveMetricValues(
            cpuPercent: cpuPercent,
            ownCPUPercent: ownCPUPercent,
            memoryAvailableGB: memoryAvailableGB,
            memoryFootprintMB: memoryFootprintMB,
            storageFreeGB: storageFreeGB,
            storageTotalGB: storageTotalGB,
            batteryLevel: batteryLevel,
            isCharging: isCharging,
            chargeRatePerHour: chargeRatePerHour,
            thermalStateRaw: thermalState,
            networkStatus: networkStatus,
            networkLatencyMs: networkLatencyMs,
            networkDownMbps: networkDownMbps,
            networkUpMbps: networkUpMbps,
            gpuLabel: gpuLabel,
            isLowPowerMode: isLowPowerMode,
            updatedAt: updatedAt
        )
    }
}

/// SystemMonitor orchestrates all monitors with a single sampling loop,
/// records history, and bridges to Live Activities. No 1-second polling
/// loops unless the user selects the Fast interval.
@MainActor
@Observable
final class SystemMonitor {
    let settings: SettingsStore
    let cpu = CPUMonitor()
    let memory = MemoryMonitor()
    let gpu = GPUMonitor()
    let storage = StorageMonitor()
    let thermal = ThermalMonitor()
    let battery = BatteryMonitor()
    let network = NetworkMonitor()
    let charging: ChargingMonitor
    let power: PowerMonitor

    private(set) var snapshots: [MetricKind: MetricSnapshot] = [:]
    private(set) var isRunning = false
    private(set) var lastUpdated: Date?
    private(set) var deviceData = DeviceData.empty
    private(set) var sampleCount = 0

    var liveActivityBridge: ((LiveMetricValues) -> Void)?
    var historyStore: BatteryHistoryStore?

    private var loopTask: Task<Void, Never>?
    private var lastHistoryRecord: [MetricKind: Date] = [:]

    var allMonitors: [any DeviceMonitor] {
        [cpu, memory, gpu, storage, thermal, battery, charging, network, power]
    }

    var dashboardKinds: [MetricKind] {
        [.cpu, .memory, .gpu, .storage, .battery, .charging, .thermal, .network]
    }

    init(settings: SettingsStore, historyStore: BatteryHistoryStore?) {
        self.settings = settings
        self.historyStore = historyStore
        let charging = ChargingMonitor()
        let power = PowerMonitor(charging: charging, history: historyStore)
        self.charging = charging
        self.power = power

        charging.onSessionCompleted = { [weak self] record in
            self?.historyStore?.addChargingSession(record)
        }
    }

    func snapshot(for kind: MetricKind) -> MetricSnapshot {
        snapshots[kind] ?? .placeholder(kind: kind)
    }

    func startMonitoring() {
        guard !isRunning else { return }
        isRunning = true
        loopTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshAll()
                try? await Task.sleep(for: self.settings.settings.effectiveInterval.duration)
            }
        }
    }

    func stopMonitoring() {
        loopTask?.cancel()
        loopTask = nil
        isRunning = false
        for monitor in allMonitors {
            monitor.stop()
        }
    }

    func restartIfNeeded() {
        if isRunning {
            stopMonitoring()
            startMonitoring()
        }
    }

    func refreshAll() async {
        for monitor in allMonitors where settings.isMonitoringEnabled(monitor.kind) {
            await monitor.refresh()
            snapshots[monitor.kind] = monitor.snapshot
            recordHistoryIfDue(monitor)
        }
        sampleCount += 1
        lastUpdated = Date()
        updateDeviceData()
        liveActivityBridge?(deviceData.liveValues)
    }

    private func recordHistoryIfDue(_ monitor: any DeviceMonitor) {
        guard let store = historyStore, let value = monitor.snapshot.numericValue else { return }
        let now = Date()
        if let last = lastHistoryRecord[monitor.kind], now.timeIntervalSince(last) < 60 { return }
        lastHistoryRecord[monitor.kind] = now
        store.record(kind: monitor.kind, value: value, unit: monitor.snapshot.unit, detail: monitor.snapshot.valueText, timestamp: now)
        if let batteryMonitor = monitor as? BatteryMonitor, let level = batteryMonitor.levelPercent {
            store.recordBattery(level: level, state: batteryMonitor.batteryState, thermalRaw: ThermalMonitor.name(for: ProcessInfo.processInfo.thermalState), at: now)
        }
    }

    private func updateDeviceData() {
        deviceData = DeviceData(
            cpuPercent: cpu.systemPercent,
            ownCPUPercent: cpu.ownPercent,
            memoryAvailableGB: memory.availableBytes.map { Double($0) / 1_073_741_824 },
            memoryFootprintMB: Double(memory.footprintBytes) / 1_048_576,
            storageFreeGB: Double(storage.availableBytes) / 1_073_741_824,
            storageTotalGB: Double(storage.totalBytes) / 1_073_741_824,
            batteryLevel: battery.levelPercent,
            isCharging: charging.isCharging,
            chargeRatePerHour: charging.ratePerHour,
            thermalState: ThermalMonitor.name(for: ProcessInfo.processInfo.thermalState),
            networkStatus: network.connectivityLabel,
            networkLatencyMs: network.latencyMs,
            networkDownMbps: network.downMbps,
            networkUpMbps: network.upMbps,
            gpuLabel: gpu.lastBenchmarkFPS.map { String(format: "%.0f FPS", $0) } ?? "Measured",
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            updatedAt: lastUpdated
        )
    }
}