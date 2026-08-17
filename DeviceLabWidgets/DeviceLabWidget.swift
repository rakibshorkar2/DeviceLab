import WidgetKit
import SwiftUI

/// Simple home-screen widget: branding + honest guidance.
/// Live data lives in the Live Activity / Dynamic Island presentation.
struct DeviceLabSnapshotWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DeviceLabSnapshot", provider: SnapshotProvider()) { entry in
            DeviceLabSnapshotView(entry: entry)
        }
        .configurationDisplayName("DeviceLab")
        .description("Open DeviceLab for live device diagnostics and monitoring.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct SnapshotEntry: TimelineEntry {
    let date = Date()
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry()
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        completion(Timeline(entries: [SnapshotEntry()], policy: .never))
    }
}

struct DeviceLabSnapshotView: View {
    let entry: SnapshotEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .font(.title2)
                Text("DeviceLab")
                    .font(.headline)
            }
            Text("Diagnostics · Monitoring · Benchmarks")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text("Open DeviceLab for live device metrics.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }
}