import Foundation
import BackgroundTasks
import Observation

/// Legitimate iOS background refresh using BGAppRefreshTask.
/// iOS controls when this runs; DeviceLab never loops in the background.
@MainActor
@Observable
final class BackgroundScheduler {
    private(set) var lastBackgroundRefresh: Date?
    private(set) var refreshCount = 0
    private(set) var statusMessage = "Background refresh scheduled by iOS"

    private let settings: SettingsStore
    var onBackgroundRefresh: (() -> Void)?

    init(settings: SettingsStore) {
        self.settings = settings
        BGTaskScheduler.shared.register(forTaskWithIdentifier: AppConstants.backgroundTaskIdentifier, using: nil) { [weak self] task in
            Task { @MainActor in
                self?.handleAppRefresh(task: task)
            }
        }
    }

    private func handleAppRefresh(task: BGAppRefreshTask) {
        lastBackgroundRefresh = Date()
        refreshCount += 1
        statusMessage = "Last system refresh: \(Formatters.timeShort(lastBackgroundRefresh))"

        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        onBackgroundRefresh?()
        scheduleAppRefresh()
        task.setTaskCompleted(success: true)
    }

    func scheduleAppRefresh() {
        guard settings.settings.backgroundRefreshEnabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: AppConstants.backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            statusMessage = "Refresh scheduling unavailable: \(error.localizedDescription)"
        }
    }

    func cancelScheduledRefresh() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: AppConstants.backgroundTaskIdentifier)
    }
}