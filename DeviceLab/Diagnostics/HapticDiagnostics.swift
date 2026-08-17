import Foundation
import Observation
import CoreHaptics
import UIKit

/// Haptic diagnostics using public feedback APIs (UIFeedbackGenerator + Core Haptics).
@MainActor
@Observable
final class HapticDiagnosticsEngine {
    private(set) var engineAvailable = false
    private var hapticEngine: CHHapticEngine?

    init() {
        engineAvailable = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    func prepare() {
        guard engineAvailable else { return }
        do {
            let engine = try CHHapticEngine()
            try engine.start()
            hapticEngine = engine
        } catch {
            hapticEngine = nil
        }
    }

    func play(_ kind: HapticKind) {
        switch kind {
        case .light:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .heavy:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .rigid:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .soft:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    /// Custom pulse via Core Haptics (public API).
    func playCustom(intensity: Float, sharpness: Float, duration: Double) throws {
        guard let hapticEngine else {
            hapticEngine = try? CHHapticEngine()
            guard let hapticEngine else { throw HapticError.engineUnavailable }
            try hapticEngine.start()
        }
        let continuous = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: 0,
            duration: duration
        )
        let pattern = try CHHapticPattern(events: [continuous], parameters: [])
        let player = try hapticEngine.makePlayer(with: pattern)
        try player.start(atTime: 0)
    }

    enum HapticKind: String, CaseIterable, Identifiable {
        case light
        case medium
        case heavy
        case rigid
        case soft
        case success
        case warning
        case error
        case selection

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .light: return "Light tap"
            case .medium: return "Medium tap"
            case .heavy: return "Heavy tap"
            case .rigid: return "Rigid tap"
            case .soft: return "Soft tap"
            case .success: return "Success"
            case .warning: return "Warning"
            case .error: return "Error"
            case .selection: return "Selection tick"
            }
        }
    }

    enum HapticError: Error {
        case engineUnavailable
    }
}