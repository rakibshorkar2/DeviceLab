import Foundation
import Observation

// MARK: - Step machine

enum FullDiagnosticStep: String, CaseIterable, Identifiable {
    case device
    case battery
    case charging
    case thermal
    case storage
    case cpu
    case gpu
    case memory
    case network
    case sensors
    case display
    case touch
    case camera
    case microphone
    case speaker
    case haptics

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .device: return "Device"
        case .battery: return "Battery"
        case .charging: return "Charging"
        case .thermal: return "Thermal"
        case .storage: return "Storage"
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return "Memory"
        case .network: return "Network"
        case .sensors: return "Sensors"
        case .display: return "Display"
        case .touch: return "Touch"
        case .camera: return "Camera"
        case .microphone: return "Microphone"
        case .speaker: return "Speaker"
        case .haptics: return "Haptics"
        }
    }

    var isInteractive: Bool {
        [.display, .touch, .camera, .microphone, .speaker, .haptics].contains(self)
    }
}

/// Runs the Full Device Check: automatic steps execute in sequence;
/// interactive steps pause and wait for the user, then continue.
@MainActor
@Observable
final class FullDiagnosticCoordinator {
    enum Phase: Equatable {
        case idle
        case running
        case waitingForUser
        case finished
    }

    private(set) var phase: Phase = .idle
    private(set) var currentStep: FullDiagnosticStep?
    private(set) var results: [FullDiagnosticStep: String] = [:]
    private(set) var progress: Double = 0
    private(set) var startedAt: Date?
    private(set) var finishedAt: Date?

    private var task: Task<Void, Never>?
    private let deps: FullDiagnosticDependencies

    struct FullDiagnosticDependencies {
        let systemMonitor: SystemMonitor
        let networkEngine: NetworkDiagnosticsEngine
        let sensorEngine: SensorDiagnosticsEngine
        let audioEngine: AudioDiagnosticsEngine
        let cameraEngine: CameraDiagnosticsEngine
        let hapticEngine: HapticDiagnosticsEngine
        let settings: SettingsStore
    }

    init(dependencies: FullDiagnosticDependencies) {
        self.deps = dependencies
    }

    var isInteractivePause: Bool {
        phase == .waitingForUser
    }

    var elapsedSeconds: TimeInterval? {
        guard let startedAt else { return nil }
        return (finishedAt ?? Date()).timeIntervalSince(startedAt)
    }

    var completedSteps: [FullDiagnosticStep] {
        FullDiagnosticStep.allCases.filter { results[$0] != nil }
    }

    func start() {
        guard phase == .idle || phase == .finished else { return }
        phase = .running
        results = [:]
        progress = 0
        startedAt = Date()
        finishedAt = nil
        task = Task { [weak self] in
            await self?.advanceAutomaticSteps()
        }
    }

    func reset() {
        task?.cancel()
        task = nil
        phase = .idle
        currentStep = nil
        results = [:]
        progress = 0
        startedAt = nil
        finishedAt = nil
    }

    /// Called by interactive test views when the user completes them.
    func completeInteractive(result: String) {
        guard phase == .waitingForUser, let currentStep else { return }
        results[currentStep] = result
        phase = .running
        task = Task { [weak self] in
            await self?.advanceAutomaticSteps()
        }
    }

    // MARK: Engine

    private func advanceAutomaticSteps() async {
        let allSteps = FullDiagnosticStep.allCases
        let startIndex = currentStep.flatMap { allSteps.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        guard startIndex < allSteps.count else { return }
        let remaining = allSteps[startIndex...]
        for step in remaining {
            self.currentStep = step
            if step.isInteractive {
                phase = .waitingForUser
                return
            }
            results[step] = await evaluateAutomatic(step)
            progress = Double(allSteps.firstIndex(of: step) ?? 0) / Double(allSteps.count)
        }
        finishedAt = Date()
        phase = .finished
        progress = 1
        try? await Task.sleep(for: .seconds(0.2))
        NotificationCenter.default.post(name: .diagnosticRunFinished, object: nil)
    }

    private func evaluateAutomatic(_ step: FullDiagnosticStep) async -> String {
        let monitor = deps.systemMonitor
        await monitor.refreshAll()
        switch step {
        case .device:
            let info = DeviceInfo.current
            return "\(info.marketingName) · \(info.osLabel) · \(info.processorCount) cores · \(info.memoryGB.formatted(.number.precision(.fractionLength(1)))) GB RAM"
        case .battery:
            let snapshot = monitor.snapshot(for: .battery)
            return snapshot.valueText + " · " + snapshot.subtext
        case .charging:
            let snapshot = monitor.snapshot(for: .charging)
            return snapshot.valueText + (snapshot.numericValue.map { String(format: " (+%.1f%%/10min)", $0) } ?? "")
        case .thermal:
            let snapshot = monitor.snapshot(for: .thermal)
            return snapshot.valueText
        case .storage:
            let snapshot = monitor.snapshot(for: .storage)
            return snapshot.valueText + " free · " + snapshot.subtext
        case .cpu:
            let snapshot = monitor.snapshot(for: .cpu)
            return snapshot.valueText + " · " + snapshot.subtext
        case .gpu:
            let snapshot = monitor.snapshot(for: .gpu)
            return snapshot.valueText + " (DeviceLab own workload; system attribution restricted)"
        case .memory:
            let snapshot = monitor.snapshot(for: .memory)
            return snapshot.valueText + " available · " + snapshot.subtext
        case .network:
            let result = await NetworkProbe.measureLatency()
            if let latency = result.latencyMs {
                return String(format: "%.0f ms latency, %.0f ms jitter", latency, result.jitterMs ?? 0)
            }
            return "No connectivity"
        case .sensors:
            deps.sensorEngine.refreshCapabilities()
            return sensorSummary()
        default:
            return "—"
        }
    }

    private func sensorSummary() -> String {
        let engine = deps.sensorEngine
        var available: [String] = []
        if engine.accelerometerAvailable { available.append("accelerometer") }
        if engine.gyroscopeAvailable { available.append("gyroscope") }
        if engine.magnetometerAvailable { available.append("magnetometer") }
        if engine.deviceMotionAvailable { available.append("device motion") }
        if engine.barometerAvailable { available.append("barometer") }
        if engine.pedometerAvailable { available.append("pedometer") }
        if engine.proximitySensorAvailable { available.append("proximity") }
        return available.isEmpty ? "No sensors reported by Core Motion" : available.joined(separator: ", ")
    }

    /// Result summary lines for the finished view.
    var summaryLines: [(step: FullDiagnosticStep, result: String)] {
        FullDiagnosticStep.allCases.compactMap { step in
            guard let result = results[step] else { return nil }
            return (step, result)
        }
    }
}

extension Notification.Name {
    static let diagnosticRunFinished = Notification.Name("devicelab.diagnostic.finished")
}