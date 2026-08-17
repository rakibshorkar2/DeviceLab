import SwiftUI
import UIKit

/// Touch diagnostics: grid coverage, multi-touch capacity, drawing test.
struct TouchTestView: View {
    @Environment(AppState.self) private var appState
    var embeddedCompletion: ((String) -> Void)?
    @State private var selectedTest: TestKind = .grid
    @State private var grid = TouchGridState()
    @State private var multi = MultitouchState()
    @State private var drawing = DrawingState()

    enum TestKind: String, CaseIterable, Identifiable {
        case grid = "Touch grid"
        case multi = "Multi-touch"
        case drawing = "Drawing"
        var id: String { rawValue }
    }

    var body: some View {
        List {
            Section {
                Picker("Test", selection: $selectedTest) {
                    ForEach(TestKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }

            switch selectedTest {
            case .grid:
                gridSection
            case .multi:
                multiSection
            case .drawing:
                drawingSection
            }

            if embeddedCompletion != nil {
                Section {
                    Button("Finish touch test") {
                        let gridResult = "Grid \(grid.completedCount)/\(grid.totalCells) cells"
                        let multiResult = "Max \(multi.maxConcurrentTouches) simultaneous touches"
                        embeddedCompletion?("\(gridResult) · \(multiResult)")
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Touch Test")
    }

    // MARK: Grid

    private var gridSection: some View {
        Section {
            VStack(spacing: 8) {
                HStack {
                    Text("Touch every cell")
                        .font(.headline)
                    Spacer()
                    Text("\(grid.completedCount)/\(grid.totalCells)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: grid.progress)
                gridCanvas
                    .frame(height: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                HStack {
                    if grid.isComplete {
                        Text("Grid complete — all cells responded")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else if let elapsed = grid.elapsedSeconds {
                        Text("Elapsed \(Int(elapsed)) s")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reset") { grid.reset() }
                        .font(.caption)
                }
            }
        }
        .onAppear { grid.begin() }
    }

    private var gridCanvas: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 2
            let columns = grid.columns
            let rows = grid.rows
            let cellWidth = (proxy.size.width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
            let cellHeight = (proxy.size.height - CGFloat(rows - 1) * spacing) / CGFloat(rows)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(cellWidth), spacing: spacing), count: columns), spacing: spacing) {
                ForEach(0..<grid.totalCells, id: \.self) { index in
                    Rectangle()
                        .fill(grid.touchedCells.contains(index) ? Color.green.opacity(0.75) : Color.gray.opacity(0.25))
                        .frame(width: cellWidth, height: cellHeight)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            grid.touchCell(index: index)
                            if grid.isComplete {
                                grid.finish()
                            }
                        }
                }
            }
        }
    }

    // MARK: Multi-touch

    private var multiSection: some View {
        Section {
            MultiTouchSurface { count in
                multi.update(currentCount: count)
            }
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .listRowInsets(EdgeInsets())

            LabeledRow(label: "Current touches", value: "\(multi.currentTouches)")
            LabeledRow(label: "Max simultaneous", value: "\(multi.maxConcurrentTouches)")
            LabeledRow(label: "Touch events", value: "\(multi.touchCount)")
            Text("Place multiple fingers on the surface. DeviceLab counts the maximum number of simultaneous touches it can observe.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Reset") { multi.reset() }
                .font(.caption)
        } header: {
            Text("Multi-touch")
        }
    }

    // MARK: Drawing

    private var drawingSection: some View {
        Section {
            DrawingSurface { phase in
                switch phase {
                case .began:
                    drawing.strokeBegan()
                case .moved(let count):
                    drawing.pointsAdded(count)
                case .ended:
                    drawing.strokeEnded()
                }
            }
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .listRowInsets(EdgeInsets())

            LabeledRow(label: "Strokes", value: "\(drawing.strokeCount)")
            LabeledRow(label: "Points drawn", value: "\(drawing.pointCount)")
            Text("Draw lines across the entire screen to check for touch-path accuracy and dead zones.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Clear") { drawing.reset() }
                .font(.caption)
        } header: {
            Text("Drawing test")
        }
    }
}

// MARK: - UIKit touch surfaces

final class TouchTrackingUIView: UIView {
    var onTouchesChanged: ((Int) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .systemFill
    }

    required init?(coder: NSCoder) { fatalError() }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        onTouchesChanged?(touches.count)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        onTouchesChanged?(touches.count)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        onTouchesChanged?(0)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        onTouchesChanged?(0)
    }
}

struct MultiTouchSurface: UIViewRepresentable {
    let onTouchesChanged: (Int) -> Void

    func makeUIView(context: Context) -> TouchTrackingUIView {
        let view = TouchTrackingUIView()
        view.onTouchesChanged = onTouchesChanged
        return view
    }

    func updateUIView(_ uiView: TouchTrackingUIView, context: Context) {}
}

enum DrawingPhase {
    case began
    case moved(Int)
    case ended
}

final class DrawingUIView: UIView {
    var onPhase: ((DrawingPhase) -> Void)?

    private var currentPath: UIBezierPath?
    private var currentLayer: CAShapeLayer?
    private var pointsInStroke = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        backgroundColor = .secondarySystemBackground
    }

    required init?(coder: NSCoder) { fatalError() }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        let path = UIBezierPath()
        path.move(to: point)
        let layer = CAShapeLayer()
        layer.strokeColor = UIColor.systemBlue.cgColor
        layer.fillColor = nil
        layer.lineWidth = 3
        layer.lineCap = .round
        layer.path = path.cgPath
        self.layer.addSublayer(layer)
        currentPath = path
        currentLayer = layer
        pointsInStroke = 1
        onPhase?(.began)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let path = currentPath else { return }
        path.addLine(to: touch.location(in: self))
        currentLayer?.path = path.cgPath
        pointsInStroke += 1
        onPhase?(.moved(1))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        _ = pointsInStroke
        currentPath = nil
        currentLayer = nil
        onPhase?(.ended)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        currentPath = nil
        currentLayer = nil
        onPhase?(.ended)
    }
}

struct DrawingSurface: UIViewRepresentable {
    let onPhase: (DrawingPhase) -> Void

    func makeUIView(context: Context) -> DrawingUIView {
        let view = DrawingUIView()
        view.onPhase = onPhase
        return view
    }

    func updateUIView(_ uiView: DrawingUIView, context: Context) {}
}