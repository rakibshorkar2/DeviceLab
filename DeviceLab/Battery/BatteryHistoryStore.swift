import Foundation
import SwiftData
import UIKit

// MARK: - SwiftData models

@Model
final class MeasurementRecord {
    var kindRaw: String
    var value: Double
    var unit: String
    var detail: String
    var timestamp: Date

    init(kindRaw: String, value: Double, unit: String, detail: String, timestamp: Date) {
        self.kindRaw = kindRaw
        self.value = value
        self.unit = unit
        self.detail = detail
        self.timestamp = timestamp
    }
}

@Model
final class BatterySample {
    var level: Double
    var stateRaw: String
    var thermalRaw: String
    var timestamp: Date

    init(level: Double, stateRaw: String, thermalRaw: String, timestamp: Date) {
        self.level = level
        self.stateRaw = stateRaw
        self.thermalRaw = thermalRaw
        self.timestamp = timestamp
    }
}

@Model
final class ChargingSession {
    var start: Date
    var end: Date?
    var startLevel: Double?
    var endLevel: Double?
    var peakLevel: Double?
    var thermalRaw: String?

    init(start: Date, end: Date?, startLevel: Double?, endLevel: Double?, peakLevel: Double?, thermalRaw: String?) {
        self.start = start
        self.end = end
        self.startLevel = startLevel
        self.endLevel = endLevel
        self.peakLevel = peakLevel
        self.thermalRaw = thermalRaw
    }
}

@Model
final class BenchmarkResult {
    var category: String
    var name: String
    var score: Double
    var metricsJSON: String
    var deviceModel: String
    var timestamp: Date

    init(category: String, name: String, score: Double, metricsJSON: String, deviceModel: String, timestamp: Date) {
        self.category = category
        self.name = name
        self.score = score
        self.metricsJSON = metricsJSON
        self.deviceModel = deviceModel
        self.timestamp = timestamp
    }
}

// MARK: - Store

/// Local-first persistence for history, charging sessions and benchmark results.
/// All data stays on device. No cloud, no telemetry.
@MainActor
final class BatteryHistoryStore {
    let modelContainer: ModelContainer?

    init(container: ModelContainer? = nil) {
        if let container {
            modelContainer = container
        } else {
            let schema = Schema([
                MeasurementRecord.self,
                BatterySample.self,
                ChargingSession.self,
                BenchmarkResult.self,
            ])
            modelContainer = try? ModelContainer(for: schema)
        }
    }

    /// In-memory container for tests.
    static func makeInMemory() -> BatteryHistoryStore? {
        let schema = Schema([
            MeasurementRecord.self,
            BatterySample.self,
            ChargingSession.self,
            BenchmarkResult.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        guard let container = try? ModelContainer(for: schema, configurations: [configuration]) else { return nil }
        return BatteryHistoryStore(container: container)
    }

    private var context: ModelContext? {
        modelContainer?.mainContext
    }

    // MARK: Recording

    func record(kind: MetricKind, value: Double?, unit: String, detail: String, timestamp: Date = Date()) {
        guard let value, let context else { return }
        let record = MeasurementRecord(kindRaw: kind.rawValue, value: value, unit: unit, detail: detail, timestamp: timestamp)
        context.insert(record)
        try? context.save()
        trimMeasurements(kind: kind)
    }

    func recordBattery(level: Double, state: UIDevice.BatteryState, thermalRaw: String, at: Date = Date()) {
        guard let context else { return }
        let stateText: String
        switch state {
        case .unknown: stateText = "unknown"
        case .unplugged: stateText = "unplugged"
        case .charging: stateText = "charging"
        case .full: stateText = "full"
        @unknown default: stateText = "unknown"
        }
        let sample = BatterySample(level: level, stateRaw: stateText, thermalRaw: thermalRaw, timestamp: at)
        context.insert(sample)
        try? context.save()
    }

    func addChargingSession(_ record: ChargingSessionRecord) {
        guard let context else { return }
        let session = ChargingSession(
            start: record.start,
            end: record.end,
            startLevel: record.startLevel,
            endLevel: record.endLevel,
            peakLevel: record.peakLevel,
            thermalRaw: nil
        )
        context.insert(session)
        try? context.save()
    }

    func addBenchmarkResult(category: String, name: String, score: Double, metricsJSON: String, timestamp: Date = Date()) {
        guard let context else { return }
        let result = BenchmarkResult(
            category: category,
            name: name,
            score: score,
            metricsJSON: metricsJSON,
            deviceModel: DeviceInfo.current.marketingName,
            timestamp: timestamp
        )
        context.insert(result)
        try? context.save()
    }

    // MARK: Querying

    func measurements(kind: MetricKind, since: Date) -> [MeasurementRecord] {
        guard let context else { return [] }
        let predicate = #Predicate<MeasurementRecord> {
            $0.kindRaw == kind.rawValue && $0.timestamp >= since
        }
        var descriptor = FetchDescriptor<MeasurementRecord>(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.timestamp)]
        return (try? context.fetch(descriptor)) ?? []
    }

    func batterySamples(since: Date) -> [BatterySample] {
        guard let context else { return [] }
        let predicate = #Predicate<BatterySample> { $0.timestamp >= since }
        var descriptor = FetchDescriptor<BatterySample>(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.timestamp)]
        return (try? context.fetch(descriptor)) ?? []
    }

    func chargingSessions() -> [ChargingSession] {
        guard let context else { return [] }
        var descriptor = FetchDescriptor<ChargingSession>()
        descriptor.sortBy = [SortDescriptor(\.start, order: .reverse)]
        return (try? context.fetch(descriptor)) ?? []
    }

    func benchmarkResults(category: String? = nil) -> [BenchmarkResult] {
        guard let context else { return [] }
        var descriptor = FetchDescriptor<BenchmarkResult>()
        if let category {
            descriptor.predicate = #Predicate { $0.category == category }
        }
        descriptor.sortBy = [SortDescriptor(\.timestamp, order: .reverse)]
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: Maintenance

    private func trimMeasurements(kind: MetricKind) {
        guard let context else { return }
        let all = measurements(kind: kind, since: Date.distantPast)
        let limit = AppConstants.History.maxSamplesPerKind
        guard all.count > limit else { return }
        for record in all.prefix(all.count - limit) {
            context.delete(record)
        }
        try? context.save()
    }

    func trimOldSamples(retentionDays: Int = AppConstants.History.sampleRetentionDays) {
        guard let context else { return }
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86_400)

        let mPredicate = #Predicate<MeasurementRecord> { $0.timestamp < cutoff }
        let mDescriptor = FetchDescriptor<MeasurementRecord>(predicate: mPredicate)
        if let records = try? context.fetch(mDescriptor) {
            records.forEach { context.delete($0) }
        }

        let bPredicate = #Predicate<BatterySample> { $0.timestamp < cutoff }
        let bDescriptor = FetchDescriptor<BatterySample>(predicate: bPredicate)
        if let samples = try? context.fetch(bDescriptor) {
            samples.forEach { context.delete($0) }
        }

        try? context.save()
    }
}