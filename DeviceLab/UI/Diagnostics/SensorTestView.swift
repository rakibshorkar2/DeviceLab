import SwiftUI

/// Sensor diagnostics: live graphs from Core Motion plus proximity,
/// orientation, barometer and pedometer.
struct SensorTestView: View {
    @Environment(AppState.self) private var appState

    private var engine: SensorDiagnosticsEngine {
        appState.sensorEngine
    }

    var body: some View {
        List {
            Section {
                HStack {
                    LiveIndicator(isLive: engine.isRunning)
                    Spacer()
                    Button(engine.isRunning ? "Stop" : "Start") {
                        if engine.isRunning {
                            engine.stop()
                        } else {
                            engine.start()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(engine.isRunning ? .red : .blue)
                }
            }

            Section("Available sensors") {
                capabilityRow("Accelerometer", engine.accelerometerAvailable)
                capabilityRow("Gyroscope", engine.gyroscopeAvailable)
                capabilityRow("Magnetometer", engine.magnetometerAvailable)
                capabilityRow("Device motion", engine.deviceMotionAvailable)
                capabilityRow("Barometer", engine.barometerAvailable)
                capabilityRow("Pedometer", engine.pedometerAvailable)
                capabilityRow("Proximity", engine.proximitySensorAvailable)
            }

            if engine.isRunning {
                if engine.accelerometerAvailable {
                    Section("Accelerometer (g)") {
                        axisRow("X", engine.accelX)
                        axisRow("Y", engine.accelY)
                        axisRow("Z", engine.accelZ)
                    }
                }
                if engine.gyroscopeAvailable {
                    Section("Gyroscope (rad/s)") {
                        axisRow("X", engine.gyroX)
                        axisRow("Y", engine.gyroY)
                        axisRow("Z", engine.gyroZ)
                    }
                }
                if engine.magnetometerAvailable {
                    Section("Magnetometer (µT)") {
                        axisRow("X", engine.magX)
                        axisRow("Y", engine.magY)
                        axisRow("Z", engine.magZ)
                        Text("Heading requires location permission, which DeviceLab does not request.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                if engine.deviceMotionAvailable {
                    Section("Device motion") {
                        axisRow("Roll", engine.roll, unit: "rad")
                        axisRow("Pitch", engine.pitch, unit: "rad")
                        axisRow("Yaw", engine.yaw, unit: "rad")
                    }
                }
                if engine.barometerAvailable {
                    Section("Barometer") {
                        LabeledRow(label: "Relative altitude", value: engine.altitudeMeters.map { String(format: "%.1f m", $0) } ?? "—")
                        LabeledRow(label: "Pressure", value: engine.pressurekPa.map { String(format: "%.3f kPa", $0) } ?? "—")
                    }
                }
                if engine.pedometerAvailable {
                    Section("Pedometer") {
                        LabeledRow(label: "Steps", value: "\(engine.stepCount ?? 0)")
                        LabeledRow(label: "Distance", value: engine.distanceMeters.map { String(format: "%.0f m", $0) } ?? "—")
                    }
                }
                Section("Device") {
                    LabeledRow(label: "Orientation", value: engine.orientationLabel ?? "—")
                    LabeledRow(label: "Proximity", value: engine.proximity.map { $0 ? "Covered" : "Clear" } ?? "—")
                }
            }
        }
        .navigationTitle("Sensor Test")
        .onAppear {
            engine.refreshCapabilities()
        }
        .onDisappear {
            engine.stop()
        }
    }

    private func capabilityRow(_ name: String, _ available: Bool) -> some View {
        HStack {
            Text(name)
            Spacer()
            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(available ? .green : .secondary)
            Text(available ? "Available" : "Not available")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func axisRow(_ label: String, _ value: Double, unit: String = "g") -> some View {
        HStack {
            Text(label)
                .frame(width: 24, alignment: .leading)
            Spacer()
            Text(String(format: "%+.3f \(unit)", value))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}