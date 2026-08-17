import XCTest
@testable import DeviceLab

final class FullDiagnosticTests: XCTestCase {

    /// The Full Device Check must start automatically — the very first
    /// step must not be skipped (regression test for the nil currentStep bug).
    @MainActor
    func testAutomaticStepsStartFromBeginning() async {
        let monitor = SystemMonitor(settings: SettingsStore(), historyStore: nil)
        let coordinator = FullDiagnosticCoordinator(dependencies: .init(
            systemMonitor: monitor,
            networkEngine: NetworkDiagnosticsEngine(networkMonitor: monitor.network),
            sensorEngine: SensorDiagnosticsEngine(),
            audioEngine: AudioDiagnosticsEngine(),
            cameraEngine: CameraDiagnosticsEngine(),
            hapticEngine: HapticDiagnosticsEngine(),
            settings: SettingsStore()
        ))

        coordinator.start()
        XCTAssertEqual(coordinator.phase, .running)

        // Wait for the automatic steps to produce at least one result.
        for _ in 0..<100 {
            if !coordinator.results.isEmpty { break }
            try? await Task.sleep(for: .milliseconds(100))
        }

        let firstIndex = FullDiagnosticStep.allCases.firstIndex(of: coordinator.currentStep ?? .device) ?? 0
        // It must have started at the first step (or advanced past a couple),
        // never jumped straight to an interactive step while nothing ran.
        XCTAssertLessThan(firstIndex, FullDiagnosticStep.allCases.count / 2)
        XCTAssertFalse(coordinator.results.isEmpty, "Automatic steps should produce results")
        coordinator.reset()
    }
}