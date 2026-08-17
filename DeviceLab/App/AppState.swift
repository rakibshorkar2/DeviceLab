import Foundation
import Observation
import SwiftUI

/// Central service container. Dependency injection only — no singletons.
@MainActor
@Observable
final class AppState {
    let settings: SettingsStore
    let historyStore: BatteryHistoryStore
    let systemMonitor: SystemMonitor
    let liveActivityManager: LiveActivityManager
    let benchmarkCoordinator: BenchmarkCoordinator
    let metricKitManager: MetricKitManager
    let backgroundScheduler: BackgroundScheduler
    let notificationService = NotificationService()
    let networkDiagnostics: NetworkDiagnosticsEngine
    let sensorEngine = SensorDiagnosticsEngine()
    let audioEngine = AudioDiagnosticsEngine()
    let cameraEngine = CameraDiagnosticsEngine()
    let hapticEngine = HapticDiagnosticsEngine()
    let fullDiagnostic: FullDiagnosticCoordinator
    let deviceInfo = DeviceInfo.current

    private(set) var monitoringStarted = false
    private var liveActivityStarted = false

    init() {
        let settings = SettingsStore()
        self.settings = settings

        let historyStore = BatteryHistoryStore()
        self.historyStore = historyStore

        let systemMonitor = SystemMonitor(settings: settings, historyStore: historyStore)
        self.systemMonitor = systemMonitor

        let liveActivityManager = LiveActivityManager(settings: settings)
        self.liveActivityManager = liveActivityManager

        self.benchmarkCoordinator = BenchmarkCoordinator(store: historyStore, settings: settings)
        self.metricKitManager = MetricKitManager()

        let backgroundScheduler = BackgroundScheduler(settings: settings)
        self.backgroundScheduler = backgroundScheduler

        self.networkDiagnostics = NetworkDiagnosticsEngine(networkMonitor: systemMonitor.network)

        self.fullDiagnostic = FullDiagnosticCoordinator(dependencies: FullDiagnosticCoordinator.FullDiagnosticDependencies(
            systemMonitor: systemMonitor,
            networkEngine: NetworkDiagnosticsEngine(networkMonitor: systemMonitor.network),
            sensorEngine: SensorDiagnosticsEngine(),
            audioEngine: AudioDiagnosticsEngine(),
            cameraEngine: CameraDiagnosticsEngine(),
            hapticEngine: HapticDiagnosticsEngine(),
            settings: settings
        ))

        systemMonitor.liveActivityBridge = { [weak self] values in
            guard let self else { return }
            if !self.liveActivityStarted {
                self.liveActivityStarted = true
                self.liveActivityManager.startAll(values: values)
            }
            self.liveActivityManager.update(values: values)
            self.notificationService.check(deviceData: self.systemMonitor.deviceData, settings: self.settings.settings)
        }

        benchmarkCoordinator.onBenchmarkFinished = { [weak self] name, score in
            guard let self, self.settings.settings.notifyBenchmarkComplete else { return }
            self.notificationService.notifyBenchmarkComplete(name: name, score: score)
        }

        metricKitManager.onMetricsReceived = { [weak self] in
            guard let self, let gpuSeconds = self.metricKitManager.gpuTimeSeconds else { return }
            self.systemMonitor.gpu.recordMetricKitGPUTime(gpuSeconds)
        }

        backgroundScheduler.onBackgroundRefresh = { [weak self] in
            guard let self else { return }
            // Persist a fresh snapshot of the last known measurements.
            let data = self.systemMonitor.deviceData
            for (kind, value) in [(MetricKind.cpu, data.cpuPercent), (.battery, data.batteryLevel)] {
                if let value {
                    self.historyStore.record(kind: kind, value: value, unit: kind == .cpu ? "%" : "%", detail: kind.displayName, timestamp: Date())
                }
            }
        }
    }

    func start() {
        guard !monitoringStarted else { return }
        monitoringStarted = true
        systemMonitor.startMonitoring()
        metricKitManager.subscribe()
        backgroundScheduler.scheduleAppRefresh()
        if settings.settings.notifyDiagnosticComplete {
            NotificationCenter.default.addObserver(
                forName: .diagnosticRunFinished,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    let summary = self.fullDiagnostic.summaryLines.map { "\($0.step.displayName): \($0.result)" }.joined(separator: "\n")
                    self.notificationService.notifyDiagnosticComplete(summary: summary)
                }
            }
        }
        NotificationCenter.default.post(name: .appStateStarted, object: nil)
    }

    // MARK: Report & score assembly

    func buildReport() -> DiagnosticReportBuilder {
        var builder = DiagnosticReportBuilder()
        builder.generatedAt = Date()
        builder.systemData = systemMonitor.deviceData
        builder.snapshots = systemMonitor.dashboardKinds.map { systemMonitor.snapshot(for: $0) }
        builder.batterySessions = historyStore.chargingSessions().map {
            ReportBatterySession(start: $0.start, end: $0.end, startLevel: $0.startLevel, endLevel: $0.endLevel, peakLevel: $0.peakLevel)
        }
        builder.benchmarks = historyStore.benchmarkResults().map {
            ReportBenchmark(category: $0.category, name: $0.name, score: $0.score, timestamp: $0.timestamp)
        }
        builder.diagnostics = fullDiagnostic.results.reduce(into: [String: String]()) { result, entry in
            result[entry.key.rawValue] = entry.value
        }
        builder.powerDischargeRatePerHour = systemMonitor.power.dischargeRatePerHour
        builder.powerEstimateWindowMinutes = systemMonitor.power.estimateWindowMinutes
        builder.score = computeScore()
        return builder
    }

    func computeScore() -> DeviceScoreEngine.ScoreSet {
        let benchmarkResults = historyStore.benchmarkResults().map {
            ReportBenchmark(category: $0.category, name: $0.name, score: $0.score, timestamp: $0.timestamp)
        }
        let storageFreeFraction: Double? = {
            guard let free = systemMonitor.deviceData.storageFreeGB, let total = systemMonitor.deviceData.storageTotalGB, total > 0 else { return nil }
            return free / total
        }()
        let sensorsAvailable = {
            let engine = sensorEngine
            return [
                engine.accelerometerAvailable, engine.gyroscopeAvailable, engine.magnetometerAvailable,
                engine.deviceMotionAvailable, engine.barometerAvailable, engine.pedometerAvailable,
                engine.proximitySensorAvailable,
            ].filter { $0 }.count
        }()

        return DeviceScoreEngine.compute(DeviceScoreEngine.Input(
            benchmarkResults: benchmarkResults,
            batteryLevel: systemMonitor.battery.levelPercent,
            isCharging: systemMonitor.charging.isCharging,
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            dischargeRatePerHour: systemMonitor.power.dischargeRatePerHour,
            thermalState: systemMonitor.deviceData.thermalState,
            storageFreeFraction: storageFreeFraction,
            networkLatencyMs: systemMonitor.network.latencyMs,
            networkDownMbps: systemMonitor.network.downMbps,
            networkUpMbps: systemMonitor.network.upMbps,
            sensorsAvailableCount: sensorsAvailable,
            cameraCount: cameraEngine.devices.isEmpty ? nil : cameraEngine.devices.count,
            cameraCapturePerformed: cameraEngine.lastPhotoData != nil,
            displayTestsPerformed: UserDefaults.standard.bool(forKey: "devicelab.displayTestPerformed"),
            audioTestsPerformed: UserDefaults.standard.bool(forKey: "devicelab.audioTestPerformed")
        ))
    }
}

extension Notification.Name {
    static let appStateStarted = Notification.Name("devicelab.appState.started")
}