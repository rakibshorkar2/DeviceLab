import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @State private var showScore = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    header
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(appState.systemMonitor.dashboardKinds) { kind in
                            DashboardCard(kind: kind)
                        }
                    }
                    footer
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("DeviceLab")
            .navigationDestination(for: MetricKind.self) { kind in
                MonitorDetailView(kind: kind)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    LiveIndicator(isLive: appState.systemMonitor.isRunning)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showScore = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "rosette")
                            Text("\(appState.computeScore().total)")
                                .fontWeight(.bold)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .sheet(isPresented: $showScore) {
                DeviceScoreView()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.tint.gradient)
                    .frame(width: 52, height: 52)
                Image(systemName: "waveform.path.ecg")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.deviceInfo.marketingName)
                    .font(.headline)
                Text(appState.deviceInfo.osLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let updated = appState.systemMonitor.lastUpdated {
                    Text("Updated \(Formatters.time(updated))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    private var footer: Text {
        Text("All metrics are real, measured locally. Restricted system-wide values are labeled, never fabricated.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }
}

// MARK: - Dashboard card

struct DashboardCard: View {
    @Environment(AppState.self) private var appState
    let kind: MetricKind

    private var snapshot: MetricSnapshot {
        appState.systemMonitor.snapshot(for: kind)
    }

    var body: some View {
        NavigationLink(value: kind) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: kind.symbolName)
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                    Spacer()
                    StatusBadge(status: snapshot.status)
                }
                Text(snapshot.valueText)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(snapshot.status.isUnavailable ? .secondary : .primary)
                Text(snapshot.subtext)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack {
                    ProvenanceBadge(provenance: snapshot.provenance)
                    Spacer()
                    Text(Formatters.time(snapshot.updatedAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}