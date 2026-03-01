import SwiftUI
import PhotosUI
import AVKit
import Photos

// MARK: - Alert Model

enum AppAlert: Identifiable {
    case success(clipCount: Int)
    case successKept(clipCount: Int)   // clips saved, user declined to delete original
    case error(title: String, message: String)

    var id: String {
        switch self {
        case .success(let n):        return "success-\(n)"
        case .successKept(let n):    return "successKept-\(n)"
        case .error(let t, _):       return "error-\(t)"
        }
    }
    var title: String {
        switch self {
        case .success, .successKept: return "Clips saved! 🎉"
        case .error(let t, _):       return t
        }
    }
}

// MARK: - Accent Color
// Using ShapeStyle where Self == Color so .accent resolves in all SwiftUI style contexts

extension ShapeStyle where Self == Color {
    static var accent: Color { Color(red: 0.38, green: 0.40, blue: 0.95) }
    static var accentLight: Color { Color(red: 0.55, green: 0.56, blue: 1.0) }
}

struct ContentView: View {
    @State private var videoAsset: AVAsset?
    @State private var player: AVPlayer?
    @State private var duration: Double = 0
    @State private var currentTime: Double = 0
    @State private var markers: [ClipMarker] = []
    @State private var timeObserver: Any?
    @State private var thumbnails: [UIImage] = []
    @State private var videoAspectRatio: CGFloat = 16.0 / 9.0

    @State private var sourcePhAssets: [PHAsset] = []
    @State private var videoBreakpoints: [Double] = []

    @State private var isLoadingVideo = false
    @State private var showPicker = false
    @State private var isExporting = false
    @State private var exportProgress: String = ""
    @State private var activeAlert: AppAlert?
    @State private var savedIdentifiers: [String] = []
    @State private var showSettings = false
    @State private var clipPanelExpanded = false

    @AppStorage("alwaysDeleteOriginal") private var alwaysDeleteOriginal = false

    var body: some View {
        NavigationStack {
            if let player = player {
                editorView(player: player)
                    .background(Color(.systemGroupedBackground))
                    .onChange(of: markers.count) { newCount in
                        if newCount == 0 && clipPanelExpanded {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                clipPanelExpanded = false
                            }
                        }
                    }
                    .navigationTitle("RepCut")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                resetState()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Back")
                                        .font(.system(size: 16, weight: .regular))
                                }
                                .foregroundStyle(.accent)
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { showSettings = true } label: {
                                Image(systemName: "gearshape")
                                    .foregroundStyle(.accent)
                            }
                        }
                    }
            } else {
                pickerView
                    .navigationTitle("")
                    .navigationBarHidden(true)
            }
        }
        .tint(.accent)
        .sheet(isPresented: $showPicker) {
            VideoPicker { identifiers in
                if !identifiers.isEmpty {
                    loadVideos(assetIdentifiers: identifiers)
                }
            }
        }
        .alert(
            Text(verbatim: activeAlert?.title ?? ""),
            isPresented: Binding(get: { activeAlert != nil }, set: { if !$0 { activeAlert = nil } }),
            presenting: activeAlert
        ) { alert in
            switch alert {
            case .success, .successKept:
                Button("Open Photos") {
                    if let url = URL(string: "photos-redirect://") {
                        UIApplication.shared.open(url)
                    }
                }
                Button("OK", role: .cancel) { }
            case .error:
                Button("OK") { }
            }
        } message: { alert in
            switch alert {
            case .success(let count):
                Text("\(count) clip\(count == 1 ? "" : "s") saved to your photo library.")
            case .successKept(let count):
                Text("\(count) clip\(count == 1 ? "" : "s") saved. Original video was kept.")
            case .error(_, let message):
                Text(message)
            }
        }
        .sheet(isPresented: $showSettings) {
            settingsView
        }
    }

    // MARK: - Picker View

    private var pickerView: some View {
        ZStack {
            // Subtle gradient background
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color(.systemGroupedBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                VStack(spacing: 20) {
                    // App icon area
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

                        Image(systemName: "scissors")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(.accent)
                    }

                    VStack(spacing: 6) {
                        Text("RepCut")
                            .font(.system(size: 32, weight: .bold, design: .rounded))

                        Text("Split your video into clips")
                            .font(.system(.subheadline, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    showPicker = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "photo.stack")
                            .font(.system(size: 16, weight: .medium))
                        Text("Choose Videos")
                            .font(.system(.body, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(width: 220, height: 54)
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
                .disabled(isLoadingVideo)

                if isLoadingVideo {
                    ProgressView()
                        .tint(.accent)
                }

                Spacer()
                Spacer()
            }

            // Settings gear — top-right corner
            VStack {
                HStack {
                    Spacer()
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 18, weight: .light))
                            .foregroundStyle(.secondary)
                            .padding(.top, 16)
                            .padding(.trailing, 20)
                    }
                }
                Spacer()
            }
        }
        .onAppear {
            // Request photo library access immediately on launch so the
            // permission dialog fires before the user picks a video —
            // not mid-flow after PHPicker closes (which causes "video not found").
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in }
        }
    }

    // MARK: - Settings View

    private var settingsView: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Auto delete original", isOn: $alwaysDeleteOriginal)
                } footer: {
                    Text("When on, the original video is automatically deleted from your photo library after clips are exported.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showSettings = false }
                        .foregroundStyle(.accent)
                }
            }
        }
    }

    // MARK: - Editor View

    private func editorView(player: AVPlayer) -> some View {
        VStack(spacing: 0) {
            // Video player
            VideoPlayerView(player: player)
                .frame(maxWidth: .infinity)
                .aspectRatio(videoAspectRatio, contentMode: .fit)
                .frame(maxHeight: 500)
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: clipPanelExpanded)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            // Time display + scrub
            HStack(spacing: 16) {
                Button {
                    scrub(by: -1)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 10, weight: .bold))
                        Text("1s")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.secondary)
                    .frame(width: 50, height: 32)
                    .background(
                        Capsule()
                            .fill(Color(UIColor.tertiarySystemFill))
                    )
                }

                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(ClipMarker.formatTime(currentTime))
                        .font(.custom("HelveticaNeue-Light", size: 30))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                    if duration > 0 {
                        Text("/ \(ClipMarker.formatTime(duration))")
                            .font(.custom("HelveticaNeue-Light", size: 14))
                            .foregroundStyle(.tertiary)
                    }
                }

                Button {
                    scrub(by: 1)
                } label: {
                    HStack(spacing: 3) {
                        Text("1s")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        Image(systemName: "chevron.forward")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(.secondary)
                    .frame(width: 50, height: 32)
                    .background(
                        Capsule()
                            .fill(Color(UIColor.tertiarySystemFill))
                    )
                }
            }
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Filmstrip
            TimelineView(
                currentTime: $currentTime,
                duration: duration,
                markers: markers,
                thumbnails: thumbnails,
                videoBreakpoints: videoBreakpoints,
                playheadColor: playheadColor,
                onSeek: { time in
                    player.seek(
                        to: CMTime(seconds: time, preferredTimescale: 600),
                        toleranceBefore: .zero,
                        toleranceAfter: .zero
                    )
                }
            )

            // Drag handle — tap or drag to reveal/hide the clip list
            if markers.isEmpty {
                Spacer().frame(height: 16)
            } else {
                clipPanelHandle
            }

            // Marker editor
            MarkerEditorView(
                markers: $markers,
                currentTime: currentTime,
                videoBreakpoints: videoBreakpoints,
                clipPanelExpanded: clipPanelExpanded
            )
            .padding(.horizontal, 16)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: clipPanelExpanded)

            Spacer(minLength: 8)

            // Cut button
            if !markers.isEmpty {
                Button(action: cutAndSave) {
                    HStack(spacing: 10) {
                        if isExporting {
                            ProgressView()
                                .tint(.white)
                            Text(exportProgress)
                        } else {
                            Image(systemName: "scissors")
                                .font(.system(size: 15, weight: .medium))
                            Text("Cut & Save \(completeMarkerCount) Clip\(completeMarkerCount == 1 ? "" : "s")")
                        }
                    }
                    .font(.system(.body, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                completeMarkerCount == 0 || isExporting
                                    ? AnyShapeStyle(Color.gray.opacity(0.4))
                                    : AnyShapeStyle(
                                        LinearGradient(
                                            colors: [.accent, .accentLight],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                    )
                    .shadow(
                        color: completeMarkerCount > 0 && !isExporting ? .accent.opacity(0.25) : .clear,
                        radius: 10, y: 4
                    )
                }
                .disabled(isExporting || completeMarkerCount == 0)
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Clip Panel Handle

    private var clipPanelHandle: some View {
        VStack(spacing: 4) {
            Capsule()
                .fill(Color.secondary.opacity(0.25))
                .frame(width: 32, height: 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 10)
                .onEnded { value in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        if value.translation.height < -20 {
                            clipPanelExpanded = true
                        } else if value.translation.height > 20 {
                            clipPanelExpanded = false
                        }
                    }
                }
        )
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                clipPanelExpanded.toggle()
            }
        }
    }

    // MARK: - Logic

    private var completeMarkerCount: Int {
        markers.filter { $0.isComplete }.count
    }

    private var playheadColor: Color {
        let colors: [Color] = [.accent, .orange, .purple, .cyan, .pink, .teal]
        // Mirror the same nextClipIndex logic as MarkerEditorView so all three stay in sync
        let idx: Int
        if let last = markers.last, !last.isComplete {
            idx = markers.count - 1
        } else {
            idx = markers.count
        }
        return colors[idx % colors.count]
    }

    private func scrub(by seconds: Double) {
        guard duration > 0 else { return }
        let newTime = max(0, min(duration, currentTime + seconds))
        currentTime = newTime
        player?.seek(
            to: CMTime(seconds: newTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    /// Wraps the callback-based PHImageManager call in an async/await interface.
    private func loadAVAsset(for phAsset: PHAsset) async throws -> AVAsset {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat

        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { avAsset, _, _ in
                if let avAsset = avAsset {
                    continuation.resume(returning: avAsset)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "RepCut",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Could not load video."]
                    ))
                }
            }
        }
    }

    private func loadVideos(assetIdentifiers: [String]) {
        isLoadingVideo = true

        Task {
            do {
                // 1. Fetch all PHAssets (preserving picker order)
                let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: assetIdentifiers, options: nil)
                // fetchAssets returns in arbitrary order; re-sort to match picker selection order
                var assetMap: [String: PHAsset] = [:]
                fetchResult.enumerateObjects { asset, _, _ in assetMap[asset.localIdentifier] = asset }
                let phAssets = assetIdentifiers.compactMap { assetMap[$0] }

                guard !phAssets.isEmpty else {
                    await MainActor.run {
                        isLoadingVideo = false
                        activeAlert = .error(title: "Error", message: "Could not find the selected videos.")
                    }
                    return
                }

                // 2. Load each AVAsset concurrently would cause PHImageManager contention;
                //    load sequentially to stay safe.
                var avAssets: [AVAsset] = []
                for phAsset in phAssets {
                    let av = try await loadAVAsset(for: phAsset)
                    avAssets.append(av)
                }

                // 3. Build AVMutableComposition — concatenate all videos end-to-end
                let composition = AVMutableComposition()
                var breakpoints: [Double] = []
                var cursor = CMTime.zero

                // Use a single shared video/audio track pair for the whole composition
                let compVideoTrack = composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                )
                let compAudioTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                )

                var firstVideoSize: CGSize?
                var firstTransform: CGAffineTransform?

                for av in avAssets {
                    let dur = try await av.load(.duration)
                    breakpoints.append(cursor.seconds)
                    let range = CMTimeRange(start: .zero, duration: dur)

                    if let srcVideo = try await av.loadTracks(withMediaType: .video).first {
                        try compVideoTrack?.insertTimeRange(range, of: srcVideo, at: cursor)
                        // Capture size/transform from first video for aspect ratio
                        if firstVideoSize == nil {
                            firstVideoSize = try? await srcVideo.load(.naturalSize)
                            firstTransform = try? await srcVideo.load(.preferredTransform)
                        }
                    }
                    if let srcAudio = try await av.loadTracks(withMediaType: .audio).first {
                        try? compAudioTrack?.insertTimeRange(range, of: srcAudio, at: cursor)
                    }
                    cursor = CMTimeAdd(cursor, dur)
                }

                let totalDuration = cursor.seconds

                // Copy the first video's preferred transform to the composition track so
                // AVPlayerLayer renders portrait videos correctly (not rotated 90°).
                if let transform = firstTransform {
                    compVideoTrack?.preferredTransform = transform
                }

                // 4. Calculate aspect ratio from first video
                var aspectRatio: CGFloat = 16.0 / 9.0
                if let size = firstVideoSize, let transform = firstTransform {
                    let transformed = size.applying(transform)
                    let w = abs(transformed.width)
                    let h = abs(transformed.height)
                    if w > 0, h > 0 { aspectRatio = w / h }
                }

                // 5. Set the player first so the editor view appears and the filmstrip
                //    scroll view gets laid out (non-zero bounds) before thumbnails arrive.
                await MainActor.run {
                    if let old = self.timeObserver {
                        self.player?.removeTimeObserver(old)
                        self.timeObserver = nil
                    }
                    self.player?.pause()

                    self.sourcePhAssets = phAssets
                    self.videoBreakpoints = breakpoints
                    self.videoAsset = composition
                    self.markers = []
                    self.currentTime = 0
                    self.duration = totalDuration
                    self.thumbnails = []
                    self.videoAspectRatio = aspectRatio
                    self.isLoadingVideo = false

                    let playerItem = AVPlayerItem(asset: composition)
                    let newPlayer = AVPlayer(playerItem: playerItem)
                    self.player = newPlayer
                    self.setupTimeObserver(for: newPlayer)
                }

                // 6. Generate thumbnails after the view is visible so the scroll view
                //    has non-zero bounds when updateUIView fires with the new thumbnails.
                let thumbs = await ThumbnailGenerator.generateThumbnails(
                    from: composition,
                    count: 20,
                    size: CGSize(width: 80, height: 112)
                )
                await MainActor.run {
                    self.thumbnails = thumbs
                }
            } catch {
                await MainActor.run {
                    self.isLoadingVideo = false
                    self.activeAlert = .error(title: "Error", message: error.localizedDescription)
                }
            }
        }
    }

    private func setupTimeObserver(for player: AVPlayer) {
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            self.currentTime = time.seconds
        }
    }

    private func cutAndSave() {
        guard let asset = videoAsset else { return }

        isExporting = true
        exportProgress = "Preparing..."

        Task {
            do {
                let identifiers = try await VideoExporter.exportClips(
                    from: asset,
                    markers: markers
                ) { current, total in
                    Task { @MainActor in
                        exportProgress = "Saving clip \(current) of \(total)..."
                    }
                }
                await MainActor.run {
                    isExporting = false
                    self.savedIdentifiers = identifiers
                    if self.alwaysDeleteOriginal {
                        self.deleteOriginalVideos(clipCount: identifiers.count)
                    } else {
                        self.activeAlert = .success(clipCount: identifiers.count)
                    }
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    activeAlert = .error(title: "Export Error", message: error.localizedDescription)
                }
            }
        }
    }

    private func deleteOriginalVideos(clipCount: Int = 0) {
        guard !sourcePhAssets.isEmpty else { return }
        let assetsToDelete = sourcePhAssets
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(assetsToDelete as NSArray)
        }) { success, error in
            DispatchQueue.main.async {
                if success {
                    self.activeAlert = .success(clipCount: clipCount)
                } else if (error as NSError?)?.code == 3072 {
                    // PHPhotosError.userCancelled — user tapped "Don't Allow" on the
                    // system deletion confirmation; not a real error, just show clips saved.
                    self.activeAlert = .successKept(clipCount: clipCount)
                } else {
                    self.activeAlert = .error(
                        title: "Error",
                        message: error?.localizedDescription ?? "Could not delete the original video(s)."
                    )
                }
            }
        }
    }

    private func resetState() {
        if let old = timeObserver {
            player?.removeTimeObserver(old)
        }
        timeObserver = nil
        player?.pause()
        player = nil
        videoAsset = nil
        sourcePhAssets = []
        videoBreakpoints = []
        markers = []
        currentTime = 0
        duration = 0
        thumbnails = []
        videoAspectRatio = 16.0 / 9.0
        savedIdentifiers = []
        clipPanelExpanded = false
    }

}

// MARK: - PHPicker UIKit Wrapper

struct VideoPicker: UIViewControllerRepresentable {
    var onPick: ([String]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .videos
        config.selectionLimit = 0  // 0 = unlimited
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: ([String]) -> Void

        init(onPick: @escaping ([String]) -> Void) {
            self.onPick = onPick
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            let identifiers = results.compactMap(\.assetIdentifier)
            onPick(identifiers)
        }
    }
}
