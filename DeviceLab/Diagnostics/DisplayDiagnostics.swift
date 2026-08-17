import Foundation
import SwiftUI

/// Modes for the full-screen display tests.
/// DeviceLab does NOT claim automatic dead-pixel detection; these are
/// visual inspection patterns.
enum DisplayTestMode: String, CaseIterable, Identifiable {
    case black
    case white
    case red
    case green
    case blue
    case gray
    case gradient

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .black: return "Black (OLED)"
        case .white: return "White"
        case .red: return "Red"
        case .green: return "Green"
        case .blue: return "Blue"
        case .gray: return "Gray (Uniformity)"
        case .gradient: return "Gradient"
        }
    }

    var color: Color {
        switch self {
        case .black: return .black
        case .white: return .white
        case .red: return .red
        case .green: return .green
        case .blue: return .blue
        case .gray: return Color(white: 0.5)
        case .gradient: return .clear
        }
    }

    var isGradient: Bool { self == .gradient }

    var instructions: String {
        switch self {
        case .black: return "Inspect for bright spots, stuck pixels, or uneven black. OLED black should be uniform and true."
        case .white: return "Inspect for tinting, dim areas, or dead pixels."
        case .red, .green, .blue: return "Inspect for color uniformity across the full screen."
        case .gray: return "Inspect for banding or uneven brightness (mura)."
        case .gradient: return "Inspect the smoothness of the gradient; look for banding."
        }
    }

    var purpose: String {
        switch self {
        case .black: return "OLED black test · burn-in inspection"
        case .white: return "Brightness & dead-pixel inspection"
        case .red, .green, .blue: return "Color accuracy visual test"
        case .gray: return "Uniformity test"
        case .gradient: return "Gradient / banding test"
        }
    }
}

/// Display information available through public APIs.
struct DisplayDiagnosticsInfo {
    let screenBounds: CGRect
    let scale: CGFloat
    let nativeScale: CGFloat?
    let pixelSize: CGSize
    let brightness: CGFloat
    let supportsTrueTone: Bool
    let maxFrameRate: Int
    let isOLED: Bool?

    static let current: DisplayDiagnosticsInfo = {
        let screen = UIScreen.main
        return DisplayDiagnosticsInfo(
            screenBounds: screen.bounds,
            scale: screen.scale,
            nativeScale: screen.nativeScale,
            pixelSize: CGSize(width: screen.bounds.width * screen.scale, height: screen.bounds.height * screen.scale),
            brightness: UIScreen.main.brightness,
            supportsTrueTone: false,
            maxFrameRate: 120,
            isOLED: nil
        )
    }()

    var summary: String {
        """
        Resolution: \(Int(pixelSize.width)) × \(Int(pixelSize.height))
        Scale: \(scale) (\(nativeScale.map { String(format: "%.0f", $0) } ?? "—") native)
        Brightness: \(String(format: "%.0f%%", brightness * 100))
        True Tone availability: not exposed to third-party apps
        Refresh rate: fixed by system (up to \(maxFrameRate) Hz on supported displays)
        Panel type (OLED/LCD): not exposed to third-party apps
        """
    }
}