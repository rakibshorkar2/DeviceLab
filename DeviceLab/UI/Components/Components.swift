import SwiftUI
import Charts

// MARK: - Cards & badges

struct SectionCard<Content: View>: View {
    var title: String? = nil
    var subtitle: String? = nil
    var symbol: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack {
                    if let symbol {
                        Image(systemName: symbol)
                            .foregroundStyle(.tint)
                    }
                    Text(title)
                        .font(.headline)
                    Spacer()
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct StatusBadge: View {
    let status: MetricStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(status.title)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.15), in: Capsule())
    }

    private var color: Color {
        switch status {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        case .inactive: return .gray
        case .unavailable: return .secondary
        }
    }
}

struct ProvenanceBadge: View {
    let provenance: Provenance

    var body: some View {
        Text(provenance.shortLabel)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
    }
}

// MARK: - Sparkline & history chart

struct Sparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { proxy in
            let minValue = (values.min() ?? 0) - 1
            let maxValue = (values.max() ?? 1) + 1
            let range = max(maxValue - minValue, 1)
            Path { path in
                for (index, value) in values.enumerated() {
                    let x = proxy.size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
                    let y = proxy.size.height * (1 - CGFloat((value - minValue) / range))
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(.tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}

struct HistoryChartView: View {
    let samples: [(date: Date, value: Double)]
    var unit: String = ""

    var body: some View {
        Chart(samples, id: \.date) { sample in
            LineMark(
                x: .value("Time", sample.date),
                y: .value("Value", sample.value)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(.tint)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour().minute(), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3))
        }
        .frame(height: 120)
    }
}

// MARK: - Gauges

struct GaugeValueView: View {
    let value: Double
    let range: ClosedRange<Double>
    let label: String
    let tint: Color

    var body: some View {
        Gauge(value: value, in: range) {
            EmptyView()
        } currentValueLabel: {
            Text(label)
                .font(.caption2)
                .monospacedDigit()
        }
        .gaugeStyle(.accessoryCircular)
        .tint(tint)
    }
}

// MARK: - Share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Live indicator

struct LiveIndicator: View {
    var isLive: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isLive ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
                .shadow(color: isLive ? .green.opacity(0.6) : .clear, radius: 3)
            Text(isLive ? "Live" : "Stopped")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Rows

struct LabeledRow: View {
    let label: String
    let value: String
    var valueColor: Color? = nil

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(valueColor ?? .primary)
        }
        .font(.subheadline)
    }
}

struct DetailLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}