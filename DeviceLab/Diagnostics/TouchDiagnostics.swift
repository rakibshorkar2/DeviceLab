import Foundation
import Observation

/// State for the touch grid test. The user must touch every cell;
/// DeviceLab records which cells were reached and how long it took.
@MainActor
@Observable
final class TouchGridState {
    let columns: Int
    let rows: Int
    private(set) var touchedCells: Set<Int> = []
    private(set) var startedAt: Date?
    private(set) var completedAt: Date?
    private(set) var missedCells: [Int] = []

    init(columns: Int = 6, rows: Int = 13) {
        self.columns = columns
        self.rows = rows
    }

    var totalCells: Int { columns * rows }
    var completedCount: Int { touchedCells.count }
    var isComplete: Bool { touchedCells.count == totalCells }
    var progress: Double {
        guard totalCells > 0 else { return 0 }
        return Double(touchedCells.count) / Double(totalCells)
    }

    var elapsedSeconds: TimeInterval? {
        guard let startedAt else { return nil }
        return (completedAt ?? Date()).timeIntervalSince(startedAt)
    }

    func begin() {
        startedAt = Date()
        completedAt = nil
        touchedCells = []
        missedCells = []
    }

    func touchCell(index: Int) {
        touchedCells.insert(index)
    }

    func finish() {
        completedAt = Date()
        let all = Set(0..<totalCells)
        missedCells = Array(all.subtracting(touchedCells)).sorted()
    }

    func reset() {
        touchedCells = []
        startedAt = nil
        completedAt = nil
        missedCells = []
    }
}

/// Records multi-touch capacity and raw touch events.
@MainActor
@Observable
final class MultitouchState {
    private(set) var maxConcurrentTouches = 0
    private(set) var currentTouches = 0
    private(set) var touchCount = 0
    private(set) var isActive = false

    func update(currentCount: Int) {
        currentTouches = currentCount
        maxConcurrentTouches = max(maxConcurrentTouches, currentCount)
        touchCount += 1
        isActive = true
    }

    func reset() {
        maxConcurrentTouches = 0
        currentTouches = 0
        touchCount = 0
        isActive = false
    }
}

/// Drawing-test state: number of strokes and points drawn.
@MainActor
@Observable
final class DrawingState {
    private(set) var strokeCount = 0
    private(set) var pointCount = 0
    private(set) var isDrawing = false

    func strokeBegan() {
        strokeCount += 1
        isDrawing = true
    }

    func pointsAdded(_ count: Int) {
        pointCount += count
    }

    func strokeEnded() {
        isDrawing = false
    }

    func reset() {
        strokeCount = 0
        pointCount = 0
        isDrawing = false
    }
}