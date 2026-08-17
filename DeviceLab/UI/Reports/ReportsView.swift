import SwiftUI

/// Reports: assemble, preview and export the diagnostic report
/// as PDF, JSON, CSV or plain text. All data is local.
struct ReportsView: View {
    @Environment(AppState.self) private var appState
    @State private var exportedURL: URL?
    @State private var showShare = false
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            List {
                let report = appState.buildReport()

                Section("Device") {
                    LabeledRow(label: "Model", value: report.device.marketingName)
                    LabeledRow(label: "Identifier", value: report.device.modelIdentifier)
                    LabeledRow(label: "OS", value: report.device.osLabel)
                    LabeledRow(label: "Generated", value: Formatters.dateTime(report.generatedAt))
                }

                if let score = report.score {
                    Section("Device Score") {
                        LabeledRow(label: "Total", value: "\(score.total)/100")
                        ForEach(score.categories) { category in
                            LabeledRow(label: category.name, value: "\(Int(category.score))/100")
                        }
                    }
                }

                Section("Measurements") {
                    ForEach(report.snapshots) { snapshot in
                        HStack {
                            Text(snapshot.kind.displayName)
                            Spacer()
                            Text(snapshot.valueText)
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                            ProvenanceBadge(provenance: snapshot.provenance)
                        }
                    }
                }

                Section("Battery sessions") {
                    if report.batterySessions.isEmpty {
                        Text("None recorded.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(report.batterySessions) { session in
                            Text("\(Formatters.dateTime(session.start)) → \(session.startLevel.map { "\(Int($0))%" } ?? "—")")
                                .font(.footnote)
                        }
                    }
                }

                Section("Benchmarks") {
                    if report.benchmarks.isEmpty {
                        Text("No benchmark results.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(report.benchmarks) { benchmark in
                            HStack {
                                Text(benchmark.category)
                                Spacer()
                                Text("\(Int(benchmark.score))")
                                    .font(.subheadline.monospacedDigit())
                            }
                        }
                    }
                }

                Section("Restricted metrics") {
                    DetailLine(text: "Per-app CPU/GPU/RAM, battery health, cycle count and charger wattage are labeled as restricted — iOS does not expose them to third-party apps.")
                }

                Section("Export") {
                    ForEach(ExportManager.Format.allCases) { format in
                        Button {
                            export(format)
                        } label: {
                            HStack {
                                Text(format.rawValue)
                                Spacer()
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    if let exportError {
                        Text(exportError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text("Reports contain only real data collected locally. Nothing leaves the device unless you share the file yourself.")
                }
            }
            .navigationTitle("Reports")
        }
        .sheet(isPresented: $showShare) {
            if let exportedURL {
                ShareSheet(items: [exportedURL])
            }
        }
    }

    private func export(_ format: ExportManager.Format) {
        exportError = nil
        do {
            let url = try ExportManager.export(appState.buildReport(), format: format)
            exportedURL = url
            showShare = true
        } catch {
            exportError = error.localizedDescription
        }
    }
}