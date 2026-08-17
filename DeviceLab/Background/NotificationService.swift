import Foundation
import UserNotifications
import Observation

/// Local notifications for battery threshold, thermal warnings,
/// charging complete, and diagnostic/benchmark completion.
@MainActor
@Observable
final class NotificationService {
    private(set) var authorizationGranted = false
    private var lastBatteryNotifyLevel: Double?
    private var didNotifyThermal = false
    private var didNotifyChargingComplete = false

    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        authorizationGranted = granted
        return granted
    }

    private func send(id: String, title: String, body: String) {
        guard authorizationGranted else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Called on every monitor tick with fresh data.
    func check(deviceData: DeviceData, settings: AppSettings) {
        // Battery threshold
        if settings.notifyBatteryThresholdEnabled,
           let level = deviceData.batteryLevel {
            let threshold = Double(settings.batteryThresholdPercent)
            if level <= threshold,
               lastBatteryNotifyLevel == nil || (lastBatteryNotifyLevel ?? 100) > threshold + 5 {
                send(id: AppConstants.Notifications.batteryThreshold, title: "Battery low", body: "Battery is at \(Int(level))%.")
                lastBatteryNotifyLevel = level
            } else if level > threshold + 10 {
                lastBatteryNotifyLevel = nil
            }
        }

        // Thermal warning
        if settings.notifyThermalWarning,
           let state = deviceData.thermalState {
            let isSerious = state == "Serious" || state == "Critical"
            if isSerious, !didNotifyThermal {
                send(id: AppConstants.Notifications.thermalWarning, title: "Thermal warning", body: "Device thermal state is \(state). Consider cooling down.")
                didNotifyThermal = true
            } else if !isSerious {
                didNotifyThermal = false
            }
        }

        // Charging complete
        if settings.notifyChargingComplete,
           deviceData.isCharging == true,
           let level = deviceData.batteryLevel, level >= 99,
           !didNotifyChargingComplete {
            send(id: AppConstants.Notifications.chargingComplete, title: "Charging complete", body: "Battery reached \(Int(level))%.")
            didNotifyChargingComplete = true
        } else if deviceData.isCharging == false || (deviceData.batteryLevel ?? 0) < 95 {
            didNotifyChargingComplete = false
        }
    }

    func notifyDiagnosticComplete(summary: String) {
        send(id: AppConstants.Notifications.diagnosticComplete, title: "Diagnostic complete", body: summary)
    }

    func notifyBenchmarkComplete(name: String, score: Double) {
        send(id: AppConstants.Notifications.benchmarkComplete, title: "Benchmark complete", body: "\(name) finished with score \(Int(score)).")
    }
}