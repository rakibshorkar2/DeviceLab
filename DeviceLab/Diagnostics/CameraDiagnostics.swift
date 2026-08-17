import Foundation
import AVFoundation
import UIKit
import Observation

struct CameraDeviceInfo: Identifiable, Sendable {
    let id: String
    let positionName: String
    let hasFlash: Bool
    let hasTorch: Bool
    let supportsAF: Bool
    let minZoom: CGFloat
    let maxZoom: CGFloat
    let supportsWideColor: Bool
    let formatsCount: Int
}

enum CameraError: LocalizedError {
    case configuration(String)
    case noTorch
    case notRunning
    case noRecording

    var errorDescription: String? {
        switch self {
        case .configuration(let message): return "Camera configuration failed: \(message)"
        case .noTorch: return "This camera has no torch."
        case .notRunning: return "The camera session is not running."
        case .noRecording: return "No active recording."
        }
    }
}

/// Camera diagnostics using AVFoundation. Cameras are discovered dynamically —
/// the device layout is never hardcoded.
@Observable
final class CameraDiagnosticsEngine: NSObject, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    private(set) var devices: [CameraDeviceInfo] = []
    private(set) var selectedDeviceInfo: CameraDeviceInfo?
    private(set) var isRunning = false
    private(set) var isRecording = false
    private(set) var recordedDuration: TimeInterval = 0
    private(set) var errorMessage: String?
    private(set) var lastPhotoData: Data?
    private(set) var lastRecordingURL: URL?

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private var currentDevice: AVCaptureDevice?
    private var photoCompletion: ((Data?, Error?) -> Void)?

    private static let videoQueue = DispatchQueue(label: "devicelab.video")
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var recordingAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var recordingStartDate: Date?
    private var recordingFrameCount = 0

    var previewLayer: AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        return layer
    }

    var currentZoom: CGFloat {
        currentDevice?.videoZoomFactor ?? 1
    }

    func discoverCameras() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera,
                .builtInTelephotoCamera,
                .builtInUltraWideCamera,
                .builtInTrueDepthCamera,
                .builtInDualCamera,
                .builtInDualWideCamera,
                .builtInTripleCamera,
            ],
            mediaType: .video,
            position: .unspecified
        )
        devices = discovery.devices.map { device in
            CameraDeviceInfo(
                id: device.uniqueID,
                positionName: Self.positionName(device.position),
                hasFlash: device.hasFlash,
                hasTorch: device.hasTorch,
                supportsAF: device.isFocusPointOfInterestSupported,
                minZoom: device.minAvailableVideoZoomFactor,
                maxZoom: device.maxAvailableVideoZoomFactor,
                supportsWideColor: device.formats.contains { $0.supportedColorSpaces.contains(.P3_D65) },
                formatsCount: device.formats.count
            )
        }
        if selectedDeviceInfo == nil {
            selectedDeviceInfo = devices.first { $0.positionName == "Back" } ?? devices.first
        }
    }

    func select(_ info: CameraDeviceInfo) {
        selectedDeviceInfo = info
        if isRunning {
            stop()
            start()
        }
    }

    func start() {
        guard let info = selectedDeviceInfo else {
            errorMessage = "No camera available."
            return
        }
        guard let device = AVCaptureDevice(uniqueID: info.id) else {
            errorMessage = "Camera not found."
            return
        }
        session.beginConfiguration()
        session.sessionPreset = .photo
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            } else {
                throw CameraError.configuration("input rejected")
            }
            if session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
            } else {
                throw CameraError.configuration("photo output rejected")
            }
            photoOutput.maxPhotoQualityPrioritization = .quality
        } catch {
            session.commitConfiguration()
            errorMessage = error.localizedDescription
            return
        }
        session.commitConfiguration()
        currentDevice = device
        session.startRunning()
        isRunning = session.isRunning
        errorMessage = nil
    }

    func stop() {
        if isRecording {
            try? stopRecording()
        }
        session.stopRunning()
        isRunning = false
        for input in session.inputs { session.removeInput(input) }
        for output in session.outputs { session.removeOutput(output) }
        videoDataOutput = nil
        currentDevice = nil
    }

    func capturePhoto(completion: @escaping (Data?, Error?) -> Void) {
        guard session.isRunning else {
            completion(nil, CameraError.notRunning)
            return
        }
        photoCompletion = completion
        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .balanced
        if currentDevice?.hasFlash == true {
            settings.flashMode = .auto
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = photo.fileDataRepresentation()
        let completion = self.photoCompletion
        DispatchQueue.main.async {
            self.photoCompletion = nil
            if let error {
                completion?(nil, error)
                return
            }
            guard let data else {
                completion?(nil, CameraError.configuration("no photo data"))
                return
            }
            self.lastPhotoData = data
            completion?(data, nil)
        }
    }

    // MARK: Torch & zoom

    func setTorch(on: Bool) throws {
        guard let device = currentDevice, device.hasTorch else {
            throw CameraError.noTorch
        }
        try device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    func setZoom(_ factor: CGFloat) throws {
        guard let device = currentDevice else { return }
        let clamped = min(max(factor, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
        try device.lockForConfiguration()
        device.videoZoomFactor = clamped
        device.unlockForConfiguration()
    }

    // MARK: Video recording

    func startRecording() throws {
        guard let device = currentDevice, session.isRunning else {
            throw CameraError.notRunning
        }
        if videoDataOutput == nil {
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            output.setSampleBufferDelegate(self, queue: Self.videoQueue)
            session.beginConfiguration()
            session.sessionPreset = .high
            guard session.canAddOutput(output) else {
                session.commitConfiguration()
                throw CameraError.configuration("video output rejected")
            }
            session.addOutput(output)
            session.commitConfiguration()
            videoDataOutput = output
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("devicelab-recording-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1280,
            AVVideoHeightKey: 720,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        )
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? CameraError.configuration("writer start failed")
        }
        writer.startSession(atSourceTime: .zero)
        self.writer = writer
        writerInput = input
        recordingAdaptor = adaptor
        recordingStartDate = Date()
        recordingFrameCount = 0
        isRecording = true
    }

    func stopRecording() throws {
        guard let writer, isRecording else { throw CameraError.noRecording }
        writerInput?.markAsFinished()
        writer.finishWriting { [weak self] in
            self?.writer = nil
            self?.writerInput = nil
            self?.recordingAdaptor = nil
            if let start = self?.recordingStartDate {
                self?.recordedDuration = Date().timeIntervalSince(start)
            }
            if let url = self?.lastRecordingURL { try? FileManager.default.removeItem(at: url) }
            self?.lastRecordingURL = writer.outputURL
            self?.isRecording = false
        }
    }

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard output === self.videoDataOutput else { return }
        guard let writer = self.writer, writer.status == .writing,
              let input = self.writerInput, input.isReadyForMoreMediaData else { return }
        input.append(sampleBuffer)
        self.recordingFrameCount += 1
    }

    // MARK: Capability reporting

    static func positionName(_ position: AVCaptureDevice.Position) -> String {
        switch position {
        case .front: return "Front"
        case .back: return "Back"
        case .unspecified: return "Unspecified"
        @unknown default: return "Unknown"
        }
    }

    func capabilitySummary() -> String {
        var lines: [String] = []
        for device in devices {
            lines.append("""
            \(device.positionName) camera
              Flash: \(device.hasFlash ? "yes" : "no") · Torch: \(device.hasTorch ? "yes" : "no")
              Autofocus: \(device.supportsAF ? "supported" : "not supported")
              Zoom range: ×\(String(format: "%.1f", device.minZoom))–×\(String(format: "%.1f", device.maxZoom))
              Wide color (P3): \(device.supportsWideColor ? "yes" : "no")
              Reported formats: \(device.formatsCount)
            """)
        }
        return lines.joined(separator: "\n")
    }
}