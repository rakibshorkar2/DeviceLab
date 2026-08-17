import SwiftUI

/// Full Device Check: automatic tests run sequentially; interactive tests
/// (display, touch, camera, microphone, speaker, haptics) pause for the user.
struct FullDiagnosticView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                headerCard
                if appState.fullDiagnostic.phase != .idle {
                    stepList
                    if appState.fullDiagnostic.isInteractivePause {
                        interactiveSection
                    }
                }
                if appState.fullDiagnostic.phase == .finished {
                    summaryCard
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Full Device Check")
    }

    private var headerCard: some View {
        SectionCard(title: "RUN FULL DIAGNOSTIC", symbol: "checklist") {
            VStack(alignment: .leading, spacing: 10) {
                Text("16 checks: device, battery, charging, thermal, storage, CPU, GPU, memory, network, sensors, display, touch, camera, microphone, speaker, haptics.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if appState.fullDiagnostic.phase == .running || appState.fullDiagnostic.phase == .waitingForUser {
                    ProgressView(value: appState.fullDiagnostic.progress)
                        .tint(.blue)
                    Text("\(Int(appState.fullDiagnostic.progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if appState.fullDiagnostic.phase == .idle {
                    Button {
                        appState.fullDiagnostic.start()
                    } label: {
                        Label("Start", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                if appState.fullDiagnostic.phase == .finished {
                    HStack {
                        Button {
                            appState.fullDiagnostic.reset()
                        } label: {
                            Label("Run again", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        if let elapsed = appState.fullDiagnostic.elapsedSeconds {
                            Text("Completed in \(Int(elapsed)) s")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var stepList: some View {
        SectionCard(title: "Progress", symbol: "list.bullet") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(FullDiagnosticStep.allCases) { step in
                    HStack(spacing: 10) {
                        Image(systemName: statusIcon(for: step))
                            .foregroundStyle(statusColor(for: step))
                        Text(step.displayName)
                            .font(.subheadline)
                        Spacer()
                        if let result = appState.fullDiagnostic.results[step] {
                            Text(result)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: 160, alignment: .trailing)
                        } else if step == appState.fullDiagnostic.currentStep, appState.fullDiagnostic.isInteractivePause {
                            Text("Awaiting you")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
    }

    private func statusIcon(for step: FullDiagnosticStep) -> String {
        if appState.fullDiagnostic.results[step] != nil {
            return "checkmark.circle.fill"
        }
        if step == appState.fullDiagnostic.currentStep, appState.fullDiagnostic.isInteractivePause {
            return "hand.tap.fill"
        }
        return "circle"
    }

    private func statusColor(for step: FullDiagnosticStep) -> Color {
        if appState.fullDiagnostic.results[step] != nil { return .green }
        if step == appState.fullDiagnostic.currentStep, appState.fullDiagnostic.isInteractivePause { return .orange }
        return .secondary
    }

    @ViewBuilder
    private var interactiveSection: some View {
        SectionCard(title: "Interactive test", symbol: "hand.tap") {
            if let step = appState.fullDiagnostic.currentStep {
                Text("\(step.displayName) test")
                    .font(.headline)
                switch step {
                case .display:
                    DisplayTestView(embeddedCompletion: { result in
                        appState.fullDiagnostic.completeInteractive(result: result)
                    })
                case .touch:
                    TouchTestView(embeddedCompletion: { result in
                        appState.fullDiagnostic.completeInteractive(result: result)
                    })
                case .camera:
                    CameraTestView(embeddedCompletion: { result in
                        appState.fullDiagnostic.completeInteractive(result: result)
                    })
                case .microphone:
                    AudioTestView(embeddedMicCompletion: { result in
                        appState.fullDiagnostic.completeInteractive(result: result)
                    })
                case .speaker:
                    AudioTestView(embeddedSpeakerCompletion: { result in
                        appState.fullDiagnostic.completeInteractive(result: result)
                    })
                case .haptics:
                    HapticTestView(embeddedCompletion: { result in
                        appState.fullDiagnostic.completeInteractive(result: result)
                    })
                default:
                    EmptyView()
                }
            }
        }
    }

    private var summaryCard: some View {
        SectionCard(title: "Summary", symbol: "checkmark.seal.fill") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(appState.fullDiagnostic.summaryLines, id: \.step) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Text(line.step.displayName)
                            .font(.subheadline.weight(.medium))
                            .frame(width: 90, alignment: .leading)
                        Text(line.result)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}