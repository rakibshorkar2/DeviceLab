import SwiftUI

/// Device Score with full transparency: every category shows how it was
/// calculated.
struct DeviceScoreView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            let score = appState.computeScore()
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(score.total)")
                                .font(.system(size: 56, weight: .bold, design: .rounded))
                                .foregroundStyle(.tint)
                            Text("out of 100")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "rosette")
                            .font(.system(size: 44))
                            .foregroundStyle(.tint)
                    }
                } footer: {
                    Text("The score is a transparent average of the categories below. Each category explains its calculation. No hidden scoring.")
                }

                Section("Categories") {
                    ForEach(score.categories) { category in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(category.name)
                                    .font(.headline)
                                Spacer()
                                Text("\(Int(category.score))/100")
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(tint(for: category.score))
                            }
                            Text(category.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(category.basedOn, id: \.self) { basis in
                                Text("• \(basis)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Device Score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func tint(for score: Double) -> Color {
        if score >= 70 { return .green }
        if score >= 40 { return .orange }
        return .red
    }
}