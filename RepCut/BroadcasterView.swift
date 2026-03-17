import SwiftUI
import AVFoundation
import Photos

struct BroadcasterView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var multipeerService = MultipeerService()

    @State private var captureSession: AVCaptureSession?
    @State private var isRecording = false
    @State private var showPreview = true
    @State private var showModeSheet = false
    @State private var isBroadcasting = false
    @State private var elapsedSeconds: Int = 0
    @State private var timer: Timer?
    @State private var recordingMode = false // true = broadcast+record, false = broadcast only

    // Recording
    @State private var assetWriter: AVAssetWriter?
    @State private var videoWriterInput: AVAssetWriterInput?
    @State private var audioWriterInput: AVAssetWriterInput?
    @State private var writerStarted = false
    @State private var recordingURL: URL?

    // Capture delegate
    @State private var captureDelegate: CaptureDelegate?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let session = captureSession, showPreview {
                CameraPreviewView(session: session)
                    .ignoresSafeArea()
            } else if isBroadcasting {
                minimalStatusView
            }

            // Overlay controls
            VStack {
                // Top status bar
                if isBroadcasting {
                    statusBar
                        .padding(.top, 8)
                }

                Spacer()

                // Bottom controls
                if isBroadcasting {
                    bottomControls
                        .padding(.bottom, 40)
                }
            }

            // Pre-broadcast state
            if !isBroadcasting && captureSession == nil {
                preBroadcastView
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    stopBroadcast()
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 16, weight: .regular))
                    }
                    .foregroundStyle(.white)
                }
            }
        }
        .onDisappear {
            stopBroadcast()
        }
        .confirmationDialog("Broadcast Mode", isPresented: $showModeSheet, titleVisibility: .visible) {
            Button("Broadcast Only") {
                recordingMode = false
                startBroadcast()
            }
            Button("Broadcast & Record") {
                recordingMode = true
                startBroadcast()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Choose whether to also save a recording to your photo library.")
        }
    }

    // MARK: - Pre-broadcast View

    private var preBroadcastView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.accent.opacity(0.15), .accent.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)

                Image(systemName: "video.fill")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.accent)
            }

            VStack(spacing: 6) {
                Text("Broadcast")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Stream your camera for instant replay")
                    .font(.system(.subheadline, weight: .regular))
                    .foregroundStyle(.gray)
            }

            Button {
                showModeSheet = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 16, weight: .medium))
                    Text("Start Broadcasting")
                        .font(.system(.body, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(width: 240, height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.accent, .accentLight],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .shadow(color: .accent.opacity(0.3), radius: 12, y: 6)
            }

            Spacer()
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 12) {
            // Recording indicator
            if recordingMode {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.red)
                        .frame(width: 10, height: 10)
                    Text("REC")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(.red)
                }
            } else {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.green)
                        .frame(width: 10, height: 10)
                    Text("LIVE")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(.green)
                }
            }

            Spacer()

            // Elapsed time
            Text(formatTime(elapsedSeconds))
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)

            Spacer()

            // Connected viewers
            HStack(spacing: 4) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 12))
                Text("\(multipeerService.connectedPeers.count)")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial.opacity(0.6))
    }

    // MARK: - Minimal Status View

    private var minimalStatusView: some View {
        VStack(spacing: 20) {
            if recordingMode {
                Circle()
                    .fill(.red)
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle()
                            .stroke(.red.opacity(0.4), lineWidth: 4)
                            .frame(width: 36, height: 36)
                    )

                Text("Recording & Broadcasting")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.accent)

                Text("Broadcasting")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text(formatTime(elapsedSeconds))
                .font(.system(size: 48, weight: .thin, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))

            Text("\(multipeerService.connectedPeers.count) viewer\(multipeerService.connectedPeers.count == 1 ? "" : "s") connected")
                .font(.system(.subheadline))
                .foregroundStyle(.gray)
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack(spacing: 40) {
            // Toggle preview
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showPreview.toggle()
                }
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: showPreview ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 22))
                    Text(showPreview ? "Hide" : "Show")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.white)
                .frame(width: 60)
            }

            // Stop button
            Button {
                stopBroadcast()
                dismiss()
            } label: {
                ZStack {
                    Circle()
                        .fill(.red)
                        .frame(width: 64, height: 64)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.white)
                        .frame(width: 22, height: 22)
                }
            }

            // Spacer for symmetry
            Color.clear.frame(width: 60, height: 1)
        }
    }

    // MARK: - Broadcast Logic

    private func startBroadcast() {
        let session = AVCaptureSession()
        session.sessionPreset = .hd1280x720

        // Video input
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoInput = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(videoInput) else {
            return
        }
        session.addInput(videoInput)

        // Audio input
        if let mic = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        // Video output
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        // Audio output
        let audioOutput = AVCaptureAudioDataOutput()

        let delegate = CaptureDelegate(
            multipeerService: multipeerService,
            onVideoSample: { [self] sampleBuffer in
                self.writeVideoSample(sampleBuffer)
            },
            onAudioSample: { [self] sampleBuffer in
                self.writeAudioSample(sampleBuffer)
            }
        )
        self.captureDelegate = delegate

        let captureQueue = DispatchQueue(label: "com.repcut.capture", qos: .userInitiated)
        videoOutput.setSampleBufferDelegate(delegate, queue: captureQueue)
        audioOutput.setSampleBufferDelegate(delegate, queue: captureQueue)

        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        if session.canAddOutput(audioOutput) { session.addOutput(audioOutput) }

        // Set video orientation to portrait
        if let videoConnection = videoOutput.connection(with: .video) {
            if videoConnection.isVideoOrientationSupported {
                videoConnection.videoOrientation = .portrait
            }
        }

        // Set up encoder with portrait dimensions (720 wide x 1280 tall)
        multipeerService.setupEncoder(width: 720, height: 1280)

        // Start capture
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }

        self.captureSession = session
        self.isBroadcasting = true
        self.elapsedSeconds = 0
        UIApplication.shared.isIdleTimerDisabled = true

        // Start advertising
        multipeerService.startAdvertising()

        // Start timer
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsedSeconds += 1
        }

        // Set up recording if needed
        if recordingMode {
            setupRecording()
        }
    }

    private func stopBroadcast() {
        timer?.invalidate()
        timer = nil

        // Tear down encoder first so no new frames are sent
        multipeerService.teardownEncoder()

        // Remove delegate references before stopping to prevent callbacks during teardown
        let sessionToStop = captureSession
        let delegateToRelease = captureDelegate
        captureSession = nil
        captureDelegate = nil

        // Stop capture session on a background thread — stopRunning() is synchronous
        // and can deadlock the main thread
        DispatchQueue.global(qos: .userInitiated).async {
            // Remove sample buffer delegates to stop callbacks
            if let outputs = sessionToStop?.outputs {
                for output in outputs {
                    if let videoOut = output as? AVCaptureVideoDataOutput {
                        videoOut.setSampleBufferDelegate(nil, queue: nil)
                    }
                    if let audioOut = output as? AVCaptureAudioDataOutput {
                        audioOut.setSampleBufferDelegate(nil, queue: nil)
                    }
                }
            }
            sessionToStop?.stopRunning()
            _ = delegateToRelease // prevent premature dealloc until stopRunning completes
        }

        multipeerService.stopAdvertising()
        multipeerService.disconnect()

        UIApplication.shared.isIdleTimerDisabled = false
        isBroadcasting = false

        // Finalize recording
        if recordingMode, let writer = assetWriter, writer.status == .writing {
            videoWriterInput?.markAsFinished()
            audioWriterInput?.markAsFinished()
            writer.finishWriting { [self] in
                if let url = self.recordingURL {
                    self.saveToPhotos(url: url)
                }
            }
        }
        assetWriter = nil
        videoWriterInput = nil
        audioWriterInput = nil
        writerStarted = false
    }

    // MARK: - Recording

    private func setupRecording() {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("repcut_broadcast_\(Date().timeIntervalSince1970).mov")
        recordingURL = url

        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 1280,
                AVVideoHeightKey: 720,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 4_000_000
                ]
            ]
            let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            vInput.expectsMediaDataInRealTime = true

            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64000
            ]
            let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            aInput.expectsMediaDataInRealTime = true

            if writer.canAdd(vInput) { writer.add(vInput) }
            if writer.canAdd(aInput) { writer.add(aInput) }

            self.assetWriter = writer
            self.videoWriterInput = vInput
            self.audioWriterInput = aInput
            self.writerStarted = false
        } catch {
            print("Failed to create asset writer: \(error)")
        }
    }

    private func writeVideoSample(_ sampleBuffer: CMSampleBuffer) {
        guard recordingMode, let writer = assetWriter, let input = videoWriterInput else { return }

        if !writerStarted {
            let startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startWriting()
            writer.startSession(atSourceTime: startTime)
            writerStarted = true
        }

        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }

    private func writeAudioSample(_ sampleBuffer: CMSampleBuffer) {
        guard recordingMode, writerStarted, let input = audioWriterInput else { return }
        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }

    private func saveToPhotos(url: URL) {
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        } completionHandler: { success, error in
            try? FileManager.default.removeItem(at: url)
            if let error = error {
                print("Failed to save recording: \(error)")
            }
        }
    }

    // MARK: - Helpers

    private func formatTime(_ totalSeconds: Int) -> String {
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Capture Delegate

class CaptureDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    let multipeerService: MultipeerService
    let onVideoSample: (CMSampleBuffer) -> Void
    let onAudioSample: (CMSampleBuffer) -> Void

    init(multipeerService: MultipeerService, onVideoSample: @escaping (CMSampleBuffer) -> Void, onAudioSample: @escaping (CMSampleBuffer) -> Void) {
        self.multipeerService = multipeerService
        self.onVideoSample = onVideoSample
        self.onAudioSample = onAudioSample
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output is AVCaptureVideoDataOutput {
            multipeerService.sendVideoFrame(sampleBuffer)
            onVideoSample(sampleBuffer)
        } else if output is AVCaptureAudioDataOutput {
            // Audio not streamed — only write to local recording if active
            onAudioSample(sampleBuffer)
        }
    }
}
