import Foundation
import AVFoundation
import Observation

/// Speaker tone engine (public AVAudioEngine APIs).
/// Test tones are not calibrated measurement instruments; they are
/// functional audio-output checks.
final class AudioToneEngine {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let sampleRate = 44_100.0

    var isPlaying: Bool { player.isPlaying }

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: nil)
    }

    private var bufferFormat: AVAudioFormat {
        engine.mainMixerNode.outputFormat(forBus: 0)
    }

    /// Continuous tone; pan -1 = left, +1 = right.
    func playTone(frequency: Double, pan: Float = 0) throws {
        try ensureRunning()
        player.stop()
        let buffer = generateBuffer(frequency: frequency, seconds: 1.0, sweepTo: nil)
        player.pan = pan
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        player.play()
    }

    func playSweep(from: Double, to: Double, seconds: Double) throws {
        try ensureRunning()
        player.stop()
        let buffer = generateBuffer(frequency: from, seconds: seconds, sweepTo: to)
        player.pan = 0
        player.scheduleBuffer(buffer, at: nil)
        player.play()
    }

    func stop() {
        player.stop()
        engine.stop()
    }

    private func ensureRunning() throws {
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
    }

    private func generateBuffer(frequency: Double, seconds: Double, sweepTo: Double?) -> AVAudioPCMBuffer {
        let count = Int(sampleRate * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: bufferFormat, frameCapacity: AVAudioFrameCount(count)),
              let channel = buffer.floatChannelData?[0] else {
            return AVAudioPCMBuffer(pcmFormat: bufferFormat, frameCapacity: 1)!
        }
        buffer.frameLength = AVAudioFrameCount(count)
        for i in 0..<count {
            let time = Double(i) / sampleRate
            let progress = count > 1 ? Double(i) / Double(count) : 0
            let freq = sweepTo.map { frequency + ($0 - frequency) * progress } ?? frequency
            let sample = sin(2 * Double.pi * freq * time) * 0.35
            channel[i] = Float(sample)
        }
        return buffer
    }
}

/// Microphone + speaker diagnostics. All measurements are DeviceLab-level
/// checks, explicitly not laboratory-calibrated.
@Observable
final class AudioDiagnosticsEngine: NSObject, AVAudioRecorderDelegate {
    private(set) var isRecording = false
    private(set) var currentLeveldB: Float = -160
    private(set) var peakLeveldB: Float = -160
    private(set) var noiseFloorEstimate: Float?
    private(set) var recordedDuration: TimeInterval = 0
    private(set) var permissionGranted = false
    private(set) var outputDescription: String?
    private(set) var outputChannelCount: Int = 0

    private var recorder: AVAudioRecorder?
    private var meterTask: Task<Void, Never>?
    private var levelSamples: [Float] = []
    let toneEngine = AudioToneEngine()

    func refreshSessionInfo() {
        let session = AVAudioSession.sharedInstance()
        let route = session.currentRoute
        outputDescription = route.outputs.first?.portType.rawValue ?? "None"
        outputChannelCount = route.outputs.first?.channels?.count ?? 0
    }

    func requestPermission() async -> Bool {
        permissionGranted = await AVAudioSession.sharedInstance().requestRecordPermission()
        return permissionGranted
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            // Session activation failure is non-fatal for metering attempts below.
        }
    }

    func startInputMonitoring() {
        guard permissionGranted else { return }
        configureSession()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("devicelab-mic.m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue,
        ]
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            recorder.delegate = self
            recorder.record()
            self.recorder = recorder
            isRecording = true
            levelSamples = []
            peakLeveldB = -160
            noiseFloorEstimate = nil
            meterTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    recorder.updateMeters()
                    let current = recorder.averagePower(forChannel: 0)
                    let peak = recorder.peakPower(forChannel: 0)
                    self.currentLeveldB = current
                    self.peakLeveldB = max(self.peakLeveldB, peak)
                    self.recordedDuration = recorder.currentTime
                    self.levelSamples.append(current)
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        } catch {
            // Metering unavailable; isRecording stays false.
        }
    }

    func stopInputMonitoring() {
        meterTask?.cancel()
        meterTask = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        if !levelSamples.isEmpty {
            let sorted = levelSamples.sorted()
            noiseFloorEstimate = sorted[max(0, sorted.count / 10 - 1)]
        }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {}

    // MARK: Speaker output

    func playTone(frequency: Double, pan: Float = 0) throws {
        try toneEngine.playTone(frequency: frequency, pan: pan)
    }

    func playSweep(from: Double, to: Double, seconds: Double) throws {
        try toneEngine.playSweep(from: from, to: to, seconds: seconds)
    }

    func stopTone() {
        toneEngine.stop()
    }

    var isPlayingTone: Bool { toneEngine.isPlaying }
}