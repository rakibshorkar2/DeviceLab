import SwiftUI

/// Microphone + speaker diagnostics. Values are DeviceLab-level checks,
/// explicitly not laboratory-calibrated measurements.
struct AudioTestView: View {
    @Environment(AppState.self) private var appState
    var embeddedMicCompletion: ((String) -> Void)?
    var embeddedSpeakerCompletion: ((String) -> Void)?
    @State private var permissionGranted = false
    @State private var activeTone: TonePreset?

    private var engine: AudioDiagnosticsEngine {
        appState.audioEngine
    }

    enum TonePreset: Double, CaseIterable, Identifiable {
        case c4 = 261.63
        case a4 = 440
        case a5 = 880
        case c6 = 1046.5
        case eightK = 8000

        var id: Double { rawValue }

        var displayName: String {
            switch self {
            case .c4: return "C4 262 Hz"
            case .a4: return "A4 440 Hz"
            case .a5: return "A5 880 Hz"
            case .c6: return "C6 1047 Hz"
            case .eightK: return "8 kHz"
            }
        }
    }

    var body: some View {
        List {
            microphoneSection
            speakerSection
            routeSection

            if embeddedMicCompletion != nil || embeddedSpeakerCompletion != nil {
                Section {
                    if embeddedMicCompletion != nil {
                        Button("Finish microphone test") {
                            engine.stopInputMonitoring()
                            embeddedMicCompletion?(micSummary)
                        }
                    }
                    if embeddedSpeakerCompletion != nil {
                        Button("Finish speaker test") {
                            engine.stopTone()
                            embeddedSpeakerCompletion?("Speaker output confirmed by user.")
                        }
                    }
                }
            }
        }
        .navigationTitle("Audio Test")
        .onAppear {
            engine.refreshSessionInfo()
            Task {
                permissionGranted = await engine.requestPermission()
            }
        }
        .onDisappear {
            engine.stopInputMonitoring()
            engine.stopTone()
        }
    }

    private var micSummary: String {
        let floor = engine.noiseFloorEstimate.map { String(format: "%.0f dBFS", $0) } ?? "not measured"
        return "Mic peak \(Int(engine.peakLeveldB)) dBFS · noise floor \(floor)"
    }

    // MARK: Microphone

    private var microphoneSection: some View {
        Section("Microphone") {
            if !permissionGranted {
                Text("Microphone permission required for input level tests.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Grant microphone access") {
                    Task { permissionGranted = await engine.requestPermission() }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Input level")
                        Spacer()
                        Text("\(Int(engine.currentLeveldB)) dBFS")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    levelBar(value: engine.currentLeveldB)
                    LabeledRow(label: "Peak", value: "\(Int(engine.peakLeveldB)) dBFS")
                    LabeledRow(label: "Noise floor estimate", value: engine.noiseFloorEstimate.map { String(format: "%.0f dBFS", $0) } ?? "measuring…")
                    LabeledRow(label: "Recorded", value: "\(Int(engine.recordedDuration)) s")

                    Button {
                        if engine.isRecording {
                            engine.stopInputMonitoring()
                        } else {
                            engine.startInputMonitoring()
                        }
                    } label: {
                        Label(engine.isRecording ? "Stop monitoring" : "Start input monitoring", systemImage: engine.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(engine.isRecording ? .red : .blue)

                    Text("Speak at different volumes and distances. dBFS levels are DeviceLab measurements, not calibrated SPL values.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func levelBar(value: Float) -> some View {
        GeometryReader { proxy in
            let normalized = min(1, max(0, (Double(value) + 60) / 60))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.2))
                Capsule()
                    .fill(normalized > 0.85 ? Color.red : (normalized > 0.6 ? Color.orange : Color.green))
                    .frame(width: proxy.size.width * normalized)
            }
        }
        .frame(height: 8)
    }

    // MARK: Speaker

    private var speakerSection: some View {
        Section("Speaker") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TonePreset.allCases) { tone in
                        Button {
                            playTone(tone)
                        } label: {
                            Text(tone.displayName)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(activeTone == tone ? Color.blue : Color.gray.opacity(0.2), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Button {
                    try? engine.playTone(frequency: 440, pan: -1)
                } label: {
                    Label("Left", systemImage: "arrow.left.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    try? engine.playTone(frequency: 440, pan: 1)
                } label: {
                    Label("Right", systemImage: "arrow.right.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Button("Frequency sweep 20 Hz → 16 kHz") {
                try? engine.playSweep(from: 20, to: 16_000, seconds: 4)
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.bordered)

            Button {
                engine.stopTone()
                activeTone = nil
            } label: {
                Label("Stop tone", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(!engine.isPlayingTone)

            Text("Test tones are functional output checks. Frequency response is not calibrated.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func playTone(_ tone: TonePreset) {
        activeTone = tone
        try? engine.playTone(frequency: tone.rawValue, pan: 0)
    }

    private var routeSection: some View {
        Section("Audio route") {
            LabeledRow(label: "Output", value: engine.outputDescription ?? "—")
            LabeledRow(label: "Output channels", value: "\(engine.outputChannelCount)")
            Text("Speaker test uses the current audio route (speaker, headphones or Bluetooth).")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}