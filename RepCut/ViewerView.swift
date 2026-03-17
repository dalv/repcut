import SwiftUI
import AVFoundation
import Photos

struct ViewerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var multipeerService = MultipeerService()
    @StateObject private var playbackManager = PlaybackManager()

    @State private var delaySeconds: Double = 10.0

    // Slow motion
    @State private var isSlowMotion = false

    // Save to photos
    @State private var isSaving = false
    @State private var saveSuccess: Bool?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch multipeerService.connectionState {
            case .connected:
                connectedView
            case .connecting:
                connectingView
            default:
                browserView
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    playbackManager.stop()
                    multipeerService.disconnect()
                    multipeerService.stopBrowsing()
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
        .onAppear {
            multipeerService.startBrowsing()
            setupCallbacks()
        }
        .onDisappear {
            playbackManager.stop()
            multipeerService.disconnect()
            multipeerService.stopBrowsing()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    // MARK: - Browser View

    private var browserView: some View {
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

                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.accent)
            }

            VStack(spacing: 6) {
                Text("Looking for Broadcasters")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Make sure the other device is broadcasting")
                    .font(.system(.subheadline, weight: .regular))
                    .foregroundStyle(.gray)
            }

            if multipeerService.availablePeers.isEmpty {
                ProgressView()
                    .tint(.accent)
                    .padding(.top, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(multipeerService.availablePeers, id: \.displayName) { peer in
                        Button {
                            multipeerService.connectToPeer(peer)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "video.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.accent)

                                Text(peer.displayName)
                                    .font(.system(.body, weight: .medium))
                                    .foregroundStyle(.white)

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.gray)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            )
                        }
                    }
                }
                .padding(.horizontal, 24)
            }

            // Delay slider
            VStack(spacing: 8) {
                Text("Stream Delay: \(delaySeconds, specifier: "%.1f")s")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)

                HStack(spacing: 12) {
                    Text("1s")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.gray)

                    Slider(value: $delaySeconds, in: 1...30, step: 0.5)
                        .tint(.accent)

                    Text("30s")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.gray)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    // MARK: - Connecting View

    private var connectingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.accent)
                .scaleEffect(1.5)

            Text("Connecting...")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Connected View

    private var connectedView: some View {
        ZStack {
            // Video display with pinch-to-zoom + long press
            ZoomableVideoView(
                displayLayer: playbackManager.frameDisplayManager.displayLayer,
                onLongPressChanged: { pressing in
                    if playbackManager.mode == .liveStream {
                        // Long press → enter analysis mode
                        if pressing {
                            let impact = UIImpactFeedbackGenerator(style: .heavy)
                            impact.impactOccurred()
                            playbackManager.enterAnalysisMode()
                        }
                    } else {
                        // Analysis: long press for slow-mo
                        if pressing {
                            isSlowMotion = true
                            playbackManager.playbackRate = 0.25
                            playbackManager.isPlaying = true
                            let impact = UIImpactFeedbackGenerator(style: .medium)
                            impact.impactOccurred()
                        } else {
                            if isSlowMotion {
                                isSlowMotion = false
                                playbackManager.playbackRate = 1.0
                            }
                        }
                    }
                }
            )
            .ignoresSafeArea()

            // Top status indicator
            VStack {
                modeIndicator
                    .padding(.top, 56)
                Spacer()
            }
            .allowsHitTesting(false)

            // Slow motion indicator (analysis mode only)
            if isSlowMotion && playbackManager.mode == .analysis {
                VStack {
                    Spacer().frame(height: 92)
                    HStack(spacing: 6) {
                        Image(systemName: "tortoise.fill")
                            .font(.system(size: 14))
                        Text("0.25x SLOW")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.orange.opacity(0.85))
                    )
                    Spacer()
                }
                .allowsHitTesting(false)
            }

            // Bottom controls
            VStack {
                Spacer()
                bottomControls
            }

            // Buffer status (live mode only)
            if playbackManager.buffering && playbackManager.mode == .liveStream {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.2)
                    Text("Buffering \(delaySeconds, specifier: "%.0f")s delay...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            playbackManager.delaySeconds = delaySeconds
            playbackManager.start()
        }
    }

    // MARK: - Mode Indicator

    private var modeIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(playbackManager.mode == .liveStream ? Color.green : Color.yellow)
                .frame(width: 10, height: 10)

            Text(playbackManager.mode == .liveStream ? "LIVE STREAM" : "ANALYSIS MODE")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill((playbackManager.mode == .liveStream ? Color.green : Color.yellow).opacity(0.2))
                .overlay(
                    Capsule()
                        .strokeBorder((playbackManager.mode == .liveStream ? Color.green : Color.yellow).opacity(0.5), lineWidth: 1)
                )
        )
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        Group {
            if playbackManager.mode == .liveStream {
                liveBottomControls
            } else {
                analysisBottomControls
            }
        }
    }

    private var liveBottomControls: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.system(size: 12, weight: .medium))
            Text("\(delaySeconds, specifier: "%.1f")s delay")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(.white.opacity(0.7))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.black.opacity(0.5))
        )
        .padding(.bottom, 40)
    }

    private var analysisBottomControls: some View {
        VStack(spacing: 12) {
            // Scrub bar
            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { playbackManager.analysisPlayhead },
                        set: { playbackManager.seekTo($0) }
                    ),
                    in: 0...max(playbackManager.analysisClipDuration, 0.1)
                )
                .tint(.yellow)

                // Time labels
                HStack {
                    Text(formatTime(playbackManager.analysisPlayhead))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text(formatTime(playbackManager.analysisClipDuration))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            // Play/Pause + Save + Return to Live
            HStack(spacing: 12) {
                // Play/Pause
                Button {
                    playbackManager.togglePlayPause()
                } label: {
                    Image(systemName: playbackManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(.white.opacity(0.15)))
                }

                // Save to Photos
                Button {
                    saveClipToPhotos()
                } label: {
                    Group {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                                .frame(width: 22, height: 22)
                        } else if let success = saveSuccess {
                            Image(systemName: success ? "checkmark" : "xmark")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(success ? .green : .red)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.white.opacity(0.15)))
                }
                .disabled(isSaving)

                Spacer()

                // Return to Live Stream
                Button {
                    isSlowMotion = false
                    saveSuccess = nil
                    playbackManager.returnToLiveStream()
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Return to Live")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.green.opacity(0.25))
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.green.opacity(0.5), lineWidth: 1)
                            )
                    )
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.8))
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 40)
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Double) -> String {
        let s = max(0, seconds)
        let mins = Int(s) / 60
        let secs = Int(s) % 60
        let frac = Int((s - Double(Int(s))) * 10)
        if mins > 0 {
            return String(format: "%d:%02d.%d", mins, secs, frac)
        }
        return String(format: "%d.%d", secs, frac)
    }

    // MARK: - Save Clip

    private func saveClipToPhotos() {
        guard !isSaving else { return }
        isSaving = true
        saveSuccess = nil

        playbackManager.exportAnalysisClip { url in
            guard let url = url else {
                DispatchQueue.main.async {
                    self.isSaving = false
                    self.saveSuccess = false
                    self.clearSaveStatus()
                }
                return
            }

            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                guard status == .authorized else {
                    DispatchQueue.main.async {
                        self.isSaving = false
                        self.saveSuccess = false
                        self.clearSaveStatus()
                    }
                    return
                }

                PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                } completionHandler: { success, error in
                    try? FileManager.default.removeItem(at: url)
                    if let error = error {
                        print("[Save] Failed: \(error)")
                    }
                    DispatchQueue.main.async {
                        self.isSaving = false
                        self.saveSuccess = success
                        self.clearSaveStatus()
                    }
                }
            }
        }
    }

    private func clearSaveStatus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation { self.saveSuccess = nil }
        }
    }

    // MARK: - Setup

    private func setupCallbacks() {
        multipeerService.onCompressedFrameReceived = { frame in
            playbackManager.receivedFrameCount += 1
            let count = playbackManager.receivedFrameCount
            if count <= 5 || count % 100 == 0 {
                print("[Viewer] Received compressed frame #\(count), keyframe: \(frame.isKeyframe), size: \(frame.compressedData.count)")
            }
            playbackManager.appendFrame(frame)
        }
    }
}

// MARK: - Playback Mode

enum PlaybackMode {
    case liveStream
    case analysis
}

// MARK: - Playback Manager
//
// Memory-efficient design:
// - Stores only COMPRESSED H.264 frames (~8KB each vs ~3.7MB decoded)
// - 1800 compressed frames ≈ 14MB (vs 6.6GB if decoded)
// - Decodes on-demand: 1-15 frames per display tick via hardware VT decoder
// - All state accessed from main thread only (no locks needed)

class PlaybackManager: ObservableObject {
    let frameDisplayManager = FrameDisplayManager()
    let multipeerService = MultipeerService() // decoder instance

    @Published var buffering = true
    @Published var mode: PlaybackMode = .liveStream
    @Published var isPlaying = true
    @Published var analysisPlayhead: Double = 0.0
    @Published var analysisClipDuration: Double = 0.0

    var delaySeconds: Double = 5.0
    var receivedFrameCount = 0
    var playbackRate: Double = 1.0

    // Compressed frame storage (~8KB per frame, ~14MB for 60 seconds)
    private var compressedFrames: [TimestampedFrame] = []
    private let maxCompressedFrames = 1800 // 60 seconds at 30fps

    // Timing
    private var broadcastStartTime: TimeInterval?
    private var localStartTime: TimeInterval?
    private var latestTimestamp: TimeInterval = 0
    private var hasReceivedKeyframe = false

    // Decode cursor: index of last decoded frame in compressedFrames
    // Decoding must be sequential (H.264 P-frames depend on prior frames)
    private var decodeIndex: Int = -1

    // Latest decoded pixel buffer (only 1 in memory at a time = ~3.7MB)
    private var currentPixelBuffer: CVPixelBuffer?
    private var currentPixelTimestamp: TimeInterval = 0
    private var decodedCount = 0

    // Display link
    private var displayLink: CADisplayLink?

    // Live mode state
    private var playbackBroadcastTime: TimeInterval?
    private var lastDisplayLinkTime: TimeInterval?

    // Analysis mode state — uses a separate snapshot of frames
    private var analysisFrames: [TimestampedFrame] = []
    private var analysisClipStartTime: TimeInterval = 0
    private var analysisDecodeIndex: Int = -1
    private var analysisLastDisplayLinkTime: TimeInterval?
    private var lastAnalysisTargetIdx: Int = -1

    // MARK: - Lifecycle

    func start() {
        // Decoder callback captures the latest decoded pixel buffer
        multipeerService.onFrameReceived = { [weak self] pixelBuffer, timestamp in
            guard let self = self else { return }
            self.currentPixelBuffer = pixelBuffer
            self.currentPixelTimestamp = timestamp
            self.decodedCount += 1
            if self.decodedCount <= 3 || self.decodedCount % 200 == 0 {
                print("[Viewer] Decoded frame #\(self.decodedCount) at \(timestamp)")
            }
        }

        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkFired))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 30, preferred: 30)
        displayLink?.add(to: .main, forMode: .common)
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        compressedFrames.removeAll()
        analysisFrames.removeAll()
        decodeIndex = -1
        currentPixelBuffer = nil
        broadcastStartTime = nil
        localStartTime = nil
        hasReceivedKeyframe = false
        decodedCount = 0
        playbackBroadcastTime = nil
        lastDisplayLinkTime = nil
        analysisLastDisplayLinkTime = nil
        lastAnalysisTargetIdx = -1
    }

    // MARK: - Frame Ingestion (called from stream thread, dispatched to main)

    func appendFrame(_ frame: TimestampedFrame) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // In analysis mode, stop ingesting new frames entirely
            if self.mode == .analysis { return }

            // Skip P-frames before first keyframe
            if !self.hasReceivedKeyframe {
                if frame.isKeyframe {
                    self.hasReceivedKeyframe = true
                } else {
                    return
                }
            }

            self.compressedFrames.append(frame)
            self.latestTimestamp = max(self.latestTimestamp, frame.timestamp)
            if self.broadcastStartTime == nil {
                self.broadcastStartTime = frame.timestamp
                self.localStartTime = CACurrentMediaTime()
            }

            // Evict old frames if over capacity
            if self.compressedFrames.count > self.maxCompressedFrames {
                let excess = self.compressedFrames.count - self.maxCompressedFrames
                self.compressedFrames.removeFirst(excess)
                self.decodeIndex = max(-1, self.decodeIndex - excess)
            }
        }
    }

    // MARK: - On-Demand Decode

    /// Decode from current position up to targetIndex. If seeking backward, resets decoder
    /// and starts from nearest keyframe. Typically decodes 1 frame (sequential playback)
    /// or up to 15 frames (seek within one GOP at 0.5s keyframe interval).
    private func decodeUpTo(_ targetIndex: Int, in frames: [TimestampedFrame], cursor: inout Int) {
        guard targetIndex >= 0 && targetIndex < frames.count else { return }

        // Need to seek? (backward, fresh start, or big gap)
        if targetIndex < cursor || cursor < 0 || (targetIndex - cursor) > 45 {
            multipeerService.resetDecoder()
            // Find nearest keyframe at or before target
            var keyIdx = targetIndex
            while keyIdx > 0 && !frames[keyIdx].isKeyframe {
                keyIdx -= 1
            }
            cursor = keyIdx - 1
        }

        // Decode forward sequentially to target
        while cursor < targetIndex {
            cursor += 1
            if cursor >= 0 && cursor < frames.count {
                _ = multipeerService.decodeFrame(frames[cursor])
            }
        }
    }

    /// Binary search for frame closest to target timestamp
    private func findFrameIndex(for timestamp: TimeInterval, in frames: ArraySlice<TimestampedFrame>) -> Int? {
        guard !frames.isEmpty else { return nil }

        let startIdx = frames.startIndex
        let endIdx = frames.endIndex

        var lo = startIdx
        var hi = endIdx - 1

        while lo < hi {
            let mid = (lo + hi) / 2
            if frames[mid].timestamp < timestamp {
                lo = mid + 1
            } else {
                hi = mid
            }
        }

        // Check neighbor for closest match
        if lo > startIdx {
            let dLo = abs(frames[lo].timestamp - timestamp)
            let dPrev = abs(frames[lo - 1].timestamp - timestamp)
            if dPrev < dLo { return lo - 1 }
        }
        return lo
    }

    // MARK: - Mode Switching

    func enterAnalysisMode() {
        guard mode == .liveStream else { return }
        guard !compressedFrames.isEmpty else { return }
        guard let broadcastStart = broadcastStartTime,
              let localStart = localStartTime else { return }

        // Current delayed playback position (what the user is seeing right now)
        let now = CACurrentMediaTime()
        let currentDelayedTime = broadcastStart + (now - localStart) - delaySeconds

        // Clip range: 10s before current position + up to 5s of unseen footage after
        let pastSeconds: TimeInterval = 10.0
        let futureSeconds: TimeInterval = min(5.0, delaySeconds)

        let clipStartTime = currentDelayedTime - pastSeconds
        let clipEndTime = currentDelayedTime + futureSeconds

        // Find clip start index
        var clipStartIdx = 0
        for (i, frame) in compressedFrames.enumerated() {
            if frame.timestamp >= clipStartTime {
                clipStartIdx = i
                break
            }
        }

        // Find clip end index (last frame at or before clipEndTime)
        var clipEndIdx = compressedFrames.count - 1
        for i in stride(from: compressedFrames.count - 1, through: 0, by: -1) {
            if compressedFrames[i].timestamp <= clipEndTime {
                clipEndIdx = i
                break
            }
        }

        guard clipStartIdx <= clipEndIdx else { return }

        // Walk back to nearest keyframe so the decoder can initialize
        var keyframeIdx = clipStartIdx
        while keyframeIdx > 0 && !compressedFrames[keyframeIdx].isKeyframe {
            keyframeIdx -= 1
        }

        // Snapshot clip frames into a separate array (isolated from live buffer)
        analysisFrames = Array(compressedFrames[keyframeIdx...clipEndIdx])

        // The actual clip content starts at this offset within analysisFrames
        let contentOffset = clipStartIdx - keyframeIdx
        analysisClipStartTime = analysisFrames[contentOffset].timestamp
        let actualClipEndTime = analysisFrames.last!.timestamp
        analysisClipDuration = actualClipEndTime - analysisClipStartTime

        // Reset decoder for analysis
        multipeerService.resetDecoder()
        analysisDecodeIndex = -1
        lastAnalysisTargetIdx = -1

        // Flush display layer so it accepts frames at new timestamps
        frameDisplayManager.flush()

        // Start at beginning and auto-play through the full clip
        analysisPlayhead = 0
        isPlaying = true
        playbackRate = 1.0
        analysisLastDisplayLinkTime = nil
        mode = .analysis
    }

    func returnToLiveStream() {
        // Free analysis snapshot
        analysisFrames.removeAll()
        lastAnalysisTargetIdx = -1

        // Reset decoder — live will re-seek from keyframe
        multipeerService.resetDecoder()
        decodeIndex = -1
        playbackBroadcastTime = nil
        lastDisplayLinkTime = nil
        playbackRate = 1.0
        isPlaying = true
        analysisLastDisplayLinkTime = nil
        frameDisplayManager.flush()
        mode = .liveStream
    }

    // MARK: - Controls

    func jump(by seconds: TimeInterval) {
        let oldPlayhead = analysisPlayhead
        analysisPlayhead = max(0, min(analysisClipDuration, analysisPlayhead + seconds))
        lastAnalysisTargetIdx = -1  // Force re-render after jump
        if analysisPlayhead < oldPlayhead {
            frameDisplayManager.flush()
        }
    }

    func togglePlayPause() {
        if !isPlaying && analysisPlayhead >= analysisClipDuration - 0.05 {
            // At end of clip — restart from beginning
            multipeerService.resetDecoder()
            analysisDecodeIndex = -1
            lastAnalysisTargetIdx = -1
            frameDisplayManager.flush()
            analysisPlayhead = 0
            analysisLastDisplayLinkTime = nil
            isPlaying = true
        } else {
            isPlaying.toggle()
            if isPlaying {
                analysisLastDisplayLinkTime = nil
            }
        }
    }

    func seekTo(_ position: Double) {
        let oldPlayhead = analysisPlayhead
        analysisPlayhead = max(0, min(analysisClipDuration, position))
        lastAnalysisTargetIdx = -1  // Force re-render after seek
        // Flush display layer if seeking backward
        if analysisPlayhead < oldPlayhead - 0.05 {
            frameDisplayManager.flush()
        }
    }

    // MARK: - Export Clip

    func exportAnalysisClip(completion: @escaping (URL?) -> Void) {
        guard mode == .analysis, !analysisFrames.isEmpty else {
            completion(nil)
            return
        }

        // analysisFrames already includes preamble keyframes from enterAnalysisMode
        let allFrames = analysisFrames
        // Preamble = frames before analysisClipStartTime
        let preambleCount = allFrames.firstIndex(where: { $0.timestamp >= analysisClipStartTime }) ?? 0
        let clipStartTime = analysisClipStartTime

        print("[Export] Exporting \(allFrames.count) frames (\(preambleCount) preamble + \(allFrames.count - preambleCount) clip)")

        DispatchQueue.global(qos: .userInitiated).async {
            // Create a separate decoder for export
            let exportDecoder = MultipeerService()
            var exportedPixelBuffer: CVPixelBuffer?
            exportDecoder.onFrameReceived = { pixelBuffer, _ in
                exportedPixelBuffer = pixelBuffer
            }

            // Decode preamble frames to prime the decoder (don't write these)
            for i in 0..<preambleCount {
                _ = exportDecoder.decodeFrame(allFrames[i])
            }

            // Decode first clip frame to get dimensions
            _ = exportDecoder.decodeFrame(allFrames[preambleCount])
            guard let firstBuffer = exportedPixelBuffer else {
                print("[Export] Failed to decode first clip frame")
                completion(nil)
                return
            }

            let tempDir = FileManager.default.temporaryDirectory
            let url = tempDir.appendingPathComponent("repcut_clip_\(Date().timeIntervalSince1970).mov")

            guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else {
                print("[Export] Failed to create AVAssetWriter")
                completion(nil)
                return
            }

            let width = CVPixelBufferGetWidth(firstBuffer)
            let height = CVPixelBufferGetHeight(firstBuffer)

            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 4_000_000
                ]
            ]

            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoInput,
                sourcePixelBufferAttributes: nil
            )
            videoInput.expectsMediaDataInRealTime = false

            guard writer.canAdd(videoInput) else {
                print("[Export] Cannot add video input")
                completion(nil)
                return
            }
            writer.add(videoInput)
            writer.startWriting()
            writer.startSession(atSourceTime: .zero)

            // Write first clip frame
            let firstPTS = CMTime(seconds: 0, preferredTimescale: 600)
            adaptor.append(firstBuffer, withPresentationTime: firstPTS)

            // Decode and write remaining clip frames
            for i in (preambleCount + 1)..<allFrames.count {
                _ = exportDecoder.decodeFrame(allFrames[i])
                guard let pb = exportedPixelBuffer else { continue }

                let pts = CMTime(seconds: allFrames[i].timestamp - clipStartTime, preferredTimescale: 600)

                while !videoInput.isReadyForMoreMediaData {
                    Thread.sleep(forTimeInterval: 0.01)
                }
                adaptor.append(pb, withPresentationTime: pts)
            }

            videoInput.markAsFinished()
            let semaphore = DispatchSemaphore(value: 0)
            writer.finishWriting {
                semaphore.signal()
            }
            semaphore.wait()

            if writer.status == .completed {
                print("[Export] Saved clip to \(url.lastPathComponent) (\(allFrames.count - preambleCount) frames)")
                completion(url)
            } else {
                print("[Export] Failed: \(writer.error?.localizedDescription ?? "unknown")")
                try? FileManager.default.removeItem(at: url)
                completion(nil)
            }
        }
    }

    // MARK: - Display Link

    @objc private func displayLinkFired() {
        switch mode {
        case .liveStream:
            displayLinkLive()
        case .analysis:
            displayLinkAnalysis()
        }
    }

    private func displayLinkLive() {
        let now = CACurrentMediaTime()

        guard let broadcastStart = broadcastStartTime,
              let localStart = localStartTime else { return }

        let baseTargetTime = broadcastStart + (now - localStart) - delaySeconds

        // Check if we have enough buffer
        if latestTimestamp - broadcastStart < delaySeconds {
            buffering = true
            lastDisplayLinkTime = now
            return
        }
        buffering = false

        // Advance playback position
        if let lastTime = lastDisplayLinkTime, let currentPlayback = playbackBroadcastTime {
            let wallDelta = now - lastTime
            var newPlayback = currentPlayback + wallDelta * playbackRate
            newPlayback = min(newPlayback, baseTargetTime + 1.0)
            playbackBroadcastTime = newPlayback
        } else {
            playbackBroadcastTime = baseTargetTime
        }
        lastDisplayLinkTime = now

        guard let targetTime = playbackBroadcastTime else { return }

        // Find and decode target frame
        let allFrames = compressedFrames[...]
        guard let targetIdx = findFrameIndex(for: targetTime, in: allFrames) else { return }

        decodeUpTo(targetIdx, in: compressedFrames, cursor: &decodeIndex)

        if let pb = currentPixelBuffer {
            frameDisplayManager.enqueuePixelBuffer(pb, at: currentPixelTimestamp)
        }
    }

    private func displayLinkAnalysis() {
        guard !analysisFrames.isEmpty else { return }

        let now = CACurrentMediaTime()

        // Advance playhead if playing
        if isPlaying {
            if let lastTime = analysisLastDisplayLinkTime {
                let advance = (now - lastTime) * playbackRate
                var newPlayhead = analysisPlayhead + advance
                if newPlayhead >= analysisClipDuration {
                    newPlayhead = analysisClipDuration
                    isPlaying = false
                }
                analysisPlayhead = newPlayhead
            }
            analysisLastDisplayLinkTime = now
        } else {
            analysisLastDisplayLinkTime = nil
        }

        // Find target frame in the snapshot
        let targetTime = analysisClipStartTime + analysisPlayhead
        let allSlice = analysisFrames[...]
        guard let targetIdx = findFrameIndex(for: targetTime, in: allSlice) else { return }

        // Skip if we already displayed this exact frame (avoids flooding the display layer)
        if targetIdx == lastAnalysisTargetIdx { return }
        lastAnalysisTargetIdx = targetIdx

        // Decode to target
        decodeUpTo(targetIdx, in: analysisFrames, cursor: &analysisDecodeIndex)

        if let pb = currentPixelBuffer {
            frameDisplayManager.enqueuePixelBuffer(pb, at: currentPixelTimestamp)
        }
    }
}
