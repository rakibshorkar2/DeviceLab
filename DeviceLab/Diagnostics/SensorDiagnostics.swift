import Foundation
import Observation
import CoreMotion
import UIKit

/// Sensor engine backed by Core Motion (public API).
/// Detects available sensors dynamically; never assumes a fixed layout.
@Observable
final class SensorDiagnosticsEngine {
    private let motion = CMMotionManager()
    private let altimeter = CMAltimeter()
    private let pedometer = CMPedometer()
    private var proximityToken: NSObjectProtocol?

    // Capabilities
    private(set) var accelerometerAvailable = false
    private(set) var gyroscopeAvailable = false
    private(set) var magnetometerAvailable = false
    private(set) var deviceMotionAvailable = false
    private(set) var barometerAvailable = false
    private(set) var pedometerAvailable = false
    private(set) var proximitySensorAvailable = false

    // Live data
    private(set) var accelX = 0.0
    private(set) var accelY = 0.0
    private(set) var accelZ = 0.0
    private(set) var gyroX = 0.0
    private(set) var gyroY = 0.0
    private(set) var gyroZ = 0.0
    private(set) var magX = 0.0
    private(set) var magY = 0.0
    private(set) var magZ = 0.0
    private(set) var roll = 0.0
    private(set) var pitch = 0.0
    private(set) var yaw = 0.0
    private(set) var userAccelX = 0.0
    private(set) var userAccelY = 0.0
    private(set) var userAccelZ = 0.0
    private(set) var altitudeMeters: Double?
    private(set) var pressurekPa: Double?
    private(set) var stepCount: Int?
    private(set) var distanceMeters: Double?
    private(set) var proximity: Bool?
    private(set) var orientationLabel: String?
    private(set) var isRunning = false
    private(set) var lastUpdate: Date?

    private let updateInterval = 1.0 / 30.0

    func refreshCapabilities() {
        accelerometerAvailable = motion.isAccelerometerAvailable
        gyroscopeAvailable = motion.isGyroAvailable
        magnetometerAvailable = motion.isMagnetometerAvailable
        deviceMotionAvailable = motion.isDeviceMotionAvailable
        barometerAvailable = CMAltimeter.isRelativeAltitudeAvailable()
        pedometerAvailable = CMPedometer.isStepCountingAvailable()
        proximitySensorAvailable = UIDevice.current.isProximityMonitoringEnabled
        if proximitySensorAvailable {
            UIDevice.current.isProximityMonitoringEnabled = true
            proximity = UIDevice.current.proximityState
        }
        orientationLabel = Self.orientationName(UIDevice.current.orientation)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        refreshCapabilities()

        if accelerometerAvailable {
            motion.accelerometerUpdateInterval = updateInterval
            motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
                guard let data else { return }
                self?.accelX = data.acceleration.x
                self?.accelY = data.acceleration.y
                self?.accelZ = data.acceleration.z
                self?.lastUpdate = Date()
            }
        }
        if gyroscopeAvailable {
            motion.gyroUpdateInterval = updateInterval
            motion.startGyroUpdates(to: .main) { [weak self] data, _ in
                guard let data else { return }
                self?.gyroX = data.rotationRate.x
                self?.gyroY = data.rotationRate.y
                self?.gyroZ = data.rotationRate.z
            }
        }
        if magnetometerAvailable {
            motion.magnetometerUpdateInterval = updateInterval
            motion.startMagnetometerUpdates(to: .main) { [weak self] data, _ in
                guard let data else { return }
                self?.magX = data.magneticField.x
                self?.magY = data.magneticField.y
                self?.magZ = data.magneticField.z
            }
        }
        if deviceMotionAvailable {
            motion.deviceMotionUpdateInterval = updateInterval
            motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
                guard let data else { return }
                self?.roll = data.attitude.roll
                self?.pitch = data.attitude.pitch
                self?.yaw = data.attitude.yaw
                self?.userAccelX = data.userAcceleration.x
                self?.userAccelY = data.userAcceleration.y
                self?.userAccelZ = data.userAcceleration.z
            }
        }
        if barometerAvailable {
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
                guard let data else { return }
                self?.altitudeMeters = data.relativeAltitude.doubleValue
                self?.pressurekPa = data.pressure.doubleValue
            }
        }
        if pedometerAvailable {
            pedometer.startUpdates(from: Date()) { [weak self] data, _ in
                guard let data else { return }
                DispatchQueue.main.async {
                    self?.stepCount = data.numberOfSteps.intValue
                    self?.distanceMeters = data.distance?.doubleValue
                }
            }
        }
        if proximitySensorAvailable {
            proximityToken = NotificationCenter.default.addObserver(
                forName: UIDevice.proximityStateDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.proximity = UIDevice.current.proximityState
            }
        }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        motion.stopAccelerometerUpdates()
        motion.stopGyroUpdates()
        motion.stopMagnetometerUpdates()
        motion.stopDeviceMotionUpdates()
        altimeter.stopRelativeAltitudeUpdates()
        pedometer.stopUpdates()
        if let proximityToken {
            NotificationCenter.default.removeObserver(proximityToken)
            self.proximityToken = nil
        }
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    static func orientationName(_ orientation: UIDeviceOrientation) -> String {
        switch orientation {
        case .portrait: return "Portrait"
        case .portraitUpsideDown: return "Portrait upside down"
        case .landscapeLeft: return "Landscape left"
        case .landscapeRight: return "Landscape right"
        case .faceUp: return "Face up"
        case .faceDown: return "Face down"
        default: return "Unknown"
        }
    }

    deinit {
        stop()
    }
}