import SwiftUI

/// Display diagnostics: full-screen color patterns for visual inspection.
/// No automatic dead-pixel detection is claimed — these are inspection tools.
struct DisplayTestView: View {
    @Environment(AppState.self) private var appState
    var embeddedCompletion: ((String) -> Void)?
    @State private var activeMode: DisplayTestMode?
    @State private var runModeIndex = 0

    var body: some View {
        List {
            Section {
                LabeledRow(label: "Resolution", value: "\(Int(DisplayDiagnosticsInfo.current.pixelSize.width)) × \(Int(DisplayDiagnosticsInfo.current.pixelSize.height))")
                LabeledRow(label: "Scale", value: "\(DisplayDiagnosticsInfo.current.scale)")
                LabeledRow(label: "Brightness", value: String(format: "%.0f%%", DisplayDiagnosticsInfo.current.brightness * 100))
                LabeledRow(label: "Panel type", value: "Not exposed by iOS")
                LabeledRow(label: "True Tone", value: "Not exposed by iOS")
                LabeledRow(label: "Refresh rate", value: "System-managed (up to 120 Hz)")
            } footer: {
                Text("Some display properties are not exposed to third-party apps and are shown as such.")
            }

            Section("Test modes") {
                ForEach(DisplayTestMode.allCases) { mode in
                    Button {
                        activeMode = mode
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Circle()
                                    .fill(mode.color == .clear ? .gray : mode.color)
                                    .frame(width: 16, height: 16)
                                Text(mode.displayName)
                                Spacer()
                                Text(mode.purpose)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(mode.instructions)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            if embeddedCompletion != nil {
                Section {
                    Button("Finish display test") {
                        UserDefaults.standard.set(true, forKey: "devicelab.displayTestPerformed")
                        embeddedCompletion?("Display test completed: visual inspection confirmed.")
                    }
                }
            }
        }
        .navigationTitle("Display Test")
        .fullScreenCover(item: $activeMode) { mode in
            DisplayTestRunView(startMode: mode, isEmbedded: embeddedCompletion != nil)
        }
    }
}

/// Cycles through all color modes full screen. Tap to advance.
struct DisplayTestRunView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var index: Int
    let isEmbedded: Bool

    init(startMode: DisplayTestMode, isEmbedded: Bool) {
        self.isEmbedded = isEmbedded
        _index = State(initialValue: DisplayTestMode.allCases.firstIndex(of: startMode) ?? 0)
    }

    private var mode: DisplayTestMode {
        DisplayTestMode.allCases[index]
    }

    var body: some View {
        ZStack {
            if mode.isGradient {
                LinearGradient(
                    colors: [.black, .blue, .cyan, .white],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            } else {
                mode.color.ignoresSafeArea()
            }

            VStack {
                Spacer()
                VStack(spacing: 6) {
                    Text(mode.displayName)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(radius: 2)
                    Text(mode.instructions)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .shadow(radius: 2)
                    Text("Tap anywhere to advance (\(index + 1)/\(DisplayTestMode.allCases.count))")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.top, 4)
                }
                .padding(.bottom, 60)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if index < DisplayTestMode.allCases.count - 1 {
                index += 1
            } else {
                finish()
            }
        }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "devicelab.displayTestPerformed")
        dismiss()
    }
}