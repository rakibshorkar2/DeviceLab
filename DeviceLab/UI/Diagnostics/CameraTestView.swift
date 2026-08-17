import SwiftUI
import AVFoundation

/// Camera diagnostics: dynamic camera discovery, preview, capture,
/// torch, zoom, video recording, capability reporting.
struct CameraTestView: View {
    @Environment(AppState.self) private var appState
    var embeddedCompletion: ((String) -> Void)?
    @State private var permissionGranted = false
    @State private var capturedImage: UIImage?
    @State private var zoom: Double = 1
    @State private var isRecording = false
    @State private var recordingTask: Task<Void, Never>?

    private var engine: CameraDiagnosticsEngine {
        appState.cameraEngine
    }

    var body: some View {
        List {
            if !permissionGranted {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Camera permission required for camera diagnostics.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Grant camera access") {
                            Task { await requestPermission() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                Section {
                    CameraPreviewView(session: engine.session)
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .listRowInsets(EdgeInsets())

                    Picker("Camera", selection: cameraSelection) {
                        ForEach(engine.devices) { device in
                            Text("\(device.positionName) — \(device.id.prefix(8))").tag(Optional(device.id))
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Controls") {
                    HStack {
                        Button {
                            capturePhoto()
                        } label: {
                            Label("Capture", systemImage: "camera.fill")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            toggleTorch()
                        } label: {
                            Label("Torch", systemImage: "flashlight.on.fill")
                        }
                        .buttonStyle(.bordered)
                    }

                    VStack(alignment: .leading) {
                        Text("Zoom ×\(String(format: "%.1f", zoom))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $zoom, in: zoomRange, step: 0.1) {
                            Text("Zoom")
                        } onEditingChanged: { _ in
                            try? engine.setZoom(CGFloat(zoom))
                        }
                    }

                    Button {
                        toggleRecording()
                    } label: {
                        Label(isRecording ? "Stop recording" : "Record video", systemImage: isRecording ? "stop.circle.fill" : "record.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(isRecording ? .red : .blue)

                    if let duration = engine.recordedDuration, duration > 0, !isRecording {
                        Text("Last recording: \(duration.durationLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Capabilities") {
                    Text(engine.capabilitySummary())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let image = capturedImage {
                    Section("Last capture") {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                    }
                }

                if let error = engine.errorMessage {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                if embeddedCompletion != nil {
                    Section {
                        Button("Finish camera test") {
                            engine.stop()
                            let summary = "\(engine.devices.count) camera(s); capture \(engine.lastPhotoData == nil ? "not performed" : "performed")"
                            embeddedCompletion?(summary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle("Camera Test")
        .onAppear {
            engine.discoverCameras()
            Task { await requestPermission() }
        }
        .onDisappear {
            engine.stop()
        }
    }

    private var zoomRange: ClosedRange<Double> {
        guard let info = engine.selectedDeviceInfo else { return 1...5 }
        return Double(info.minZoom)...Double(min(info.maxZoom, 10))
    }

    private var cameraSelection: Binding<String?> {
        Binding(
            get: { engine.selectedDeviceInfo?.id },
            set: { newID in
                if let newID, let device = engine.devices.first(where: { $0.id == newID }) {
                    engine.select(device)
                }
            }
        )
    }

    private func requestPermission() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        permissionGranted = granted
        if granted {
            engine.start()
        }
    }

    private func capturePhoto() {
        engine.capturePhoto { data, error in
            if let data, let image = UIImage(data: data) {
                capturedImage = image
            }
        }
    }

    private func toggleTorch() {
        do {
            let device = AVCaptureDevice.default(for: .video)
            let targetOn = device?.torchMode != .on
            try engine.setTorch(on: targetOn)
        } catch {
            // Torch unsupported on this camera — silently ignore.
        }
    }

    private func toggleRecording() {
        if isRecording {
            try? engine.stopRecording()
            isRecording = false
            recordingTask?.cancel()
        } else {
            do {
                try engine.startRecording()
                isRecording = true
                recordingTask = Task { [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(1))
                    }
                }
            } catch {
                // Surface via engine.errorMessage on next layout pass.
            }
        }
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.session = session
    }
}

final class PreviewUIView: UIView {
    var session: AVCaptureSession? {
        get { previewLayer.session }
        set { previewLayer.session = newValue }
    }

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }
}