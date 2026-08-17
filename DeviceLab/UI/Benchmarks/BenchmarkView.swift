import SwiftUI

struct BenchmarkView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            List {
                if let error = appState.benchmarkCoordinator.lastError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                if let outcome = appState.benchmarkCoordinator.lastOutcome {
                    Section("Latest result") {
                        LabeledRow(label: "Benchmark", value: appState.benchmarkCoordinator.currentBenchmarkName ?? "")
                        LabeledRow(label: "Score", value: "\(Int(outcome.score))")
                        if let finished = appState.benchmarkCoordinator.lastFinishedAt {
                            LabeledRow(label: "Finished", value: Formatters.timeShort(finished))
                        }
                    }
                }

                Section("CPU") {
                    benchmarkRow(
                        name: "CPU Benchmark",
                        detail: "Integer, float, hashing, compression, JSON, matrix, image, multithread",
                        benchmark: appState.benchmarkCoordinator.cpuBenchmark
                    )
                }
                Section("GPU (Metal)") {
                    benchmarkRow(
                        name: "GPU Benchmark",
                        detail: "Compute shader + offscreen rendering",
                        benchmark: appState.benchmarkCoordinator.gpuBenchmark
                    )
                }
                Section("Memory") {
                    benchmarkRow(
                        name: "Memory Benchmark",
                        detail: "Allocation, copy, bandwidth, compression (DeviceLab-controlled workloads)",
                        benchmark: appState.benchmarkCoordinator.memoryBenchmark
                    )
                }
                Section("Storage") {
                    benchmarkRow(
                        name: "Storage Benchmark",
                        detail: "Sequential + small-file + random-like I/O. Temporary files are always removed.",
                        benchmark: appState.benchmarkCoordinator.storageBenchmark
                    )
                }
                Section("Network") {
                    benchmarkRow(
                        name: "Network Benchmark",
                        detail: "Latency, download, upload against public endpoints",
                        benchmark: appState.benchmarkCoordinator.networkBenchmark
                    )
                }

                Section("History") {
                    let results = appState.historyStore.benchmarkResults()
                    if results.isEmpty {
                        Text("No benchmark results yet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(results.prefix(15)), id: \.persistentModelID) { result in
                            HStack {
                                Text("\(result.category) · \(result.name)")
                                    .font(.subheadline)
                                Spacer()
                                Text("\(Int(result.score))")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Text(Formatters.timeShort(result.timestamp))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                } footer: {
                    Text("Scores are DeviceLab-normalized (0–10,000). The thermal safeguard halts benchmarks when the device is seriously hot. Sizes can be configured in Settings → Benchmark.")
                }
            }
            .navigationTitle("Benchmark")
        }
    }

    private func benchmarkRow(name: String, detail: String, benchmark: any Benchmark) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name)
                    .font(.headline)
                Spacer()
                if appState.benchmarkCoordinator.isRunning,
                   appState.benchmarkCoordinator.currentBenchmarkName == benchmark.name {
                    ProgressView()
                } else {
                    Button("Run") {
                        appState.benchmarkCoordinator.run(benchmark)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.benchmarkCoordinator.isRunning)
                }
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            if appState.benchmarkCoordinator.isRunning,
               appState.benchmarkCoordinator.currentBenchmarkName == benchmark.name {
                ProgressView(value: appState.benchmarkCoordinator.progress)
                Button("Cancel") {
                    appState.benchmarkCoordinator.cancel()
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}