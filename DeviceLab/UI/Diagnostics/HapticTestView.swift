import SwiftUI

/// Haptic diagnostics: system feedback patterns + custom Core Haptics pulse.
/// The user confirms whether each pattern was felt.
struct HapticTestView: View {
    @Environment(AppState.self) private var appState
    var embeddedCompletion: ((String) -> Void)?
    @State private var confirmed: Set<HapticDiagnosticsEngine.HapticKind> = []
    @State private var notFelt: Set<HapticDiagnosticsEngine.HapticKind> = []
    @State private var customIntensity: Float = 0.6
    @State private var customSharpness: Float = 0.5
    @State private var customDuration: Double = 0.5
    @State private var customPlayed = false
    @State private var customError: String?

    private var engine: HapticDiagnosticsEngine {
        appState.hapticEngine
    }

    var body: some View {
        List {
            Section {
                if !engine.engineAvailable {
                    Label("This device does not report haptic capabilities (Core Haptics unavailable).", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            Section("System patterns") {
                ForEach(HapticDiagnosticsEngine.HapticKind.allCases) { kind in
                    HStack {
                        Button {
                            engine.play(kind)
                        } label: {
                            HStack {
                                Text(kind.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "play.circle")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .buttonStyle(.plain)

                        Menu {
                            Button("I felt it") { confirmed.insert(kind) }
                            Button("I did not feel it") { notFelt.insert(kind) }
                        } label: {
                            if confirmed.contains(kind) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else if notFelt.contains(kind) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                            } else {
                                Image(systemName: "questionmark.circle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Custom pulse (Core Haptics)") {
                VStack(spacing: 10) {
                    LabeledRow(label: "Intensity", value: String(format: "%.2f", customIntensity))
                    Slider(value: $customIntensity, in: 0...1)
                    LabeledRow(label: "Sharpness", value: String(format: "%.2f", customSharpness))
                    Slider(value: $customSharpness, in: 0...1)
                    LabeledRow(label: "Duration", value: String(format: "%.2f s", customDuration))
                    Slider(value: $customDuration, in: 0.1...2)

                    Button {
                        do {
                            try engine.playCustom(intensity: customIntensity, sharpness: customSharpness, duration: customDuration)
                            customPlayed = true
                            customError = nil
                        } catch {
                            customError = error.localizedDescription
                        }
                    } label: {
                        Label("Play custom pulse", systemImage: "waveform.path")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!engine.engineAvailable)

                    if let customError {
                        Text(customError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            if embeddedCompletion != nil {
                Section {
                    Button("Finish haptics test") {
                        let felt = confirmed.count
                        let missed = notFelt.count
                        let result = "\(felt) patterns felt, \(missed) not felt\(customPlayed ? ", custom pulse played" : "")"
                        embeddedCompletion?(result)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Haptic Test")
        .onAppear {
            engine.prepare()
        }
    }
}