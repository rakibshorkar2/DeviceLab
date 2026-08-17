import Foundation
import ActivityKit
import Observation

/// Maps a Live Activity kind to the monitored metric kind.
/// Kept in the app target because MetricKind lives in the app module only.
extension DeviceLabActivityKind {
    var metricKind: MetricKind {
        switch self {
        case .cpu: return .cpu
        case .memory: return .memory
        case .gpu: return .gpu
        case .battery: return .battery
        case .charging: return .charging
        case .thermal: return .thermal
        case .network: return .network
        case .device: return .device
        }
    }
}

/// Manages Live Activities with efficient updates:
/// - minimum push interval (throttling)
/// - meaningful-value thresholds (no update for 41 → 42)
/// - stale dates
/// - relevance scores (system decides Dynamic Island presentation)
@MainActor
@Observable
final class LiveActivityManager {
    private let settings: SettingsStore
    private var activities: [DeviceLabActivityKind: Activity<DeviceLabLiveActivityAttributes>] = [:]
    private var lastPush: [DeviceLabActivityKind: Date] = [:]
    private var lastState: [DeviceLabActivityKind: DeviceLabLiveActivityContentState] = [:]

    private(set) var lastUpdate: Date?
    private(set) var lastUpdateReason: String?
    private(set) var rejectedUpdateCount = 0

    init(settings: SettingsStore) {
        self.settings = settings
        for activity in Activity<DeviceLabLiveActivityAttributes>.activities {
            activities[activity.attributes.kind] = activity
        }
    }

    var activitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    var activeKinds: [DeviceLabActivityKind] {
        activities.keys.sorted { $0.rawValue < $1.rawValue }
    }

    var isActive: (_ kind: DeviceLabActivityKind) -> Bool { { kind in self.activities[kind] != nil } }

    // MARK: Start / stop

    func start(kind: DeviceLabActivityKind, values: LiveMetricValues) {
        guard settings.isLiveActivityEnabled(kind.metricKind), ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastUpdateReason = "Live Activity for \(kind.displayName) not enabled (check Settings → Live Activities) or unavailable."
            return
        }
        let state = values.contentState(for: kind)
        do {
            if let existing = activities[kind] {
                let content = ActivityContent(state: state, staleDate: staleDate(), relevanceScore: relevance(for: kind))
                Task { try? await existing.update(content) }
                activities[kind] = existing
            } else {
                let activity = try Activity.request(
                    attributes: DeviceLabLiveActivityAttributes(kind: kind),
                    content: ActivityContent(state: state, staleDate: staleDate(), relevanceScore: relevance(for: kind)),
                    pushType: nil
                )
                activities[kind] = activity
            }
            lastPush[kind] = Date()
            lastState[kind] = state
            lastUpdate = Date()
            lastUpdateReason = "Started \(kind.displayName)"
        } catch {
            lastUpdateReason = "Could not start \(kind.displayName): \(error.localizedDescription)"
        }
    }

    func startAll(values: LiveMetricValues) {
        for kind in DeviceLabActivityKind.allCases {
            if settings.isLiveActivityEnabled(kind.metricKind) {
                start(kind: kind, values: values)
            }
        }
    }

    func stop(kind: DeviceLabActivityKind) {
        for activity in Activity<DeviceLabLiveActivityAttributes>.activities
        where activity.attributes.kind == kind {
            Task { try? await activity.end(nil, dismissalPolicy: .immediate) }
        }
        activities[kind] = nil
        lastPush[kind] = nil
        lastState[kind] = nil
        lastUpdate = Date()
        lastUpdateReason = "Ended \(kind.displayName)"
    }

    func stopAll() {
        for activity in Activity<DeviceLabLiveActivityAttributes>.activities {
            Task { try? await activity.end(nil, dismissalPolicy: .immediate) }
        }
        activities = [:]
        lastPush = [:]
        lastState = [:]
        lastUpdate = Date()
        lastUpdateReason = "Ended all activities"
    }

    // MARK: Update with coalescing

    func update(values: LiveMetricValues) {
        guard !activities.isEmpty else { return }
        for (kind, activity) in activities {
            let state = values.contentState(for: kind)
            guard shouldPush(kind: kind, newState: state) else { continue }
            let content = ActivityContent(state: state, staleDate: staleDate(), relevanceScore: relevance(for: kind))
            Task {
                do {
                    try await activity.update(content)
                    lastPush[kind] = Date()
                    lastState[kind] = state
                    lastUpdate = Date()
                    lastUpdateReason = "Updated \(kind.displayName)"
                } catch {
                    rejectedUpdateCount += 1
                }
            }
        }
    }

    private func shouldPush(kind: DeviceLabActivityKind, newState: DeviceLabLiveActivityContentState) -> Bool {
        let now = Date()
        if let last = lastPush[kind], now.timeIntervalSince(last) < AppConstants.LiveActivity.minimumUpdateInterval {
            return false
        }
        guard let previous = lastState[kind] else { return true }

        switch kind {
        case .cpu:
            return changed(newState.cpuPercent, previous.cpuPercent, threshold: AppConstants.LiveActivity.cpuThreshold)
        case .battery:
            return changed(newState.batteryLevel, previous.batteryLevel, threshold: AppConstants.LiveActivity.batteryThreshold)
        case .memory:
            return changed(newState.memoryAvailableGB, previous.memoryAvailableGB, threshold: AppConstants.LiveActivity.memoryThresholdGB)
        case .charging:
            if newState.isCharging != previous.isCharging { return true }
            return changed(newState.batteryLevel, previous.batteryLevel, threshold: AppConstants.LiveActivity.batteryThreshold)
        case .thermal:
            return newState.thermalState != previous.thermalState
        case .network:
            return changed(newState.networkLatencyMs, previous.networkLatencyMs, threshold: 5)
        case .gpu:
            return newState.gpuLabel != previous.gpuLabel
        case .device:
            return true
        }
    }

    private func changed(_ a: Double?, _ b: Double?, threshold: Double) -> Bool {
        guard let a, let b else { return a != b }
        return abs(a - b) >= threshold
    }

    private func staleDate() -> Date {
        Date().addingTimeInterval(AppConstants.LiveActivity.staleAfter)
    }

    /// Higher relevance = more likely to appear in the Dynamic Island.
    /// Priority is user-configurable in Settings → Live Activities.
    private func relevance(for kind: DeviceLabActivityKind) -> Double {
        let priority = settings.settings.liveActivityPriority
        guard let index = priority.firstIndex(of: kind.metricKind) else { return 0.2 }
        let count = max(1, priority.count)
        return Double(count - index) / Double(count)
    }
}