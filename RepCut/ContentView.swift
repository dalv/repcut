import SwiftUI
import PhotosUI
import AVKit
import Photos

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

    @State private var sourcePhAsset: PHAsset?

    @State private var isLoadingVideo = false
    @State private var showPicker = false
    @State private var isExporting = false
    @State private var exportProgress: String = ""
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showSettings = false

    @AppStorage("alwaysDeleteOriginal") private var alwaysDeleteOriginal = false

    var body: some View {
        NavigationStack {
            if let player = player {
                editorView(player: player)
                    .background(Color(.systemGroupedBackground))
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
            VideoPicker { assetIdentifier in
                if let assetIdentifier = assetIdentifier {
                    loadVideo(assetIdentifier: assetIdentifier)
                }
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
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
                        Image(systemName: "video.badge.plus")
                            .font(.system(size: 16, weight: .medium))
                        Text("Choose Video")
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
                    Toggle("Always delete original", isOn: $alwaysDeleteOriginal)
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
                .frame(maxHeight: 320)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .layoutPriority(1)

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
                playheadColor: playheadColor,
                onSeek: { time in
                    player.seek(
                        to: CMTime(seconds: time, preferredTimescale: 600),
                        toleranceBefore: .zero,
                        toleranceAfter: .zero
                    )
                }
            )

            Spacer().frame(height: 16)

            // Marker editor
            MarkerEditorView(markers: $markers, currentTime: currentTime)
                .padding(.horizontal, 16)

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

    private func loadVideo(assetIdentifier: String) {
        isLoadingVideo = true

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let phAsset = fetchResult.firstObject else {
            isLoadingVideo = false
            alertTitle = "Error"
            alertMessage = "Could not find the selected video."
            showAlert = true
            return
        }

        self.sourcePhAsset = phAsset

        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat

        PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { avAsset, _, _ in
            DispatchQueue.main.async {
                self.isLoadingVideo = false

                guard let avAsset = avAsset else {
                    self.alertTitle = "Error"
                    self.alertMessage = "Could not load the selected video."
                    self.showAlert = true
                    return
                }

                // Clean up any previous player/observer before setting new one
                if let old = self.timeObserver {
                    self.player?.removeTimeObserver(old)
                    self.timeObserver = nil
                }
                self.player?.pause()

                self.videoAsset = avAsset
                let playerItem = AVPlayerItem(asset: avAsset)
                let newPlayer = AVPlayer(playerItem: playerItem)
                self.player = newPlayer
                self.markers = []
                self.currentTime = 0
                self.duration = 0
                self.thumbnails = []
                self.videoAspectRatio = 16.0 / 9.0

                // Load duration
                Task {
                    if let d = try? await avAsset.load(.duration) {
                        await MainActor.run {
                            self.duration = d.seconds
                        }
                    }
                }

                // Load video aspect ratio from track
                Task {
                    if let tracks = try? await avAsset.loadTracks(withMediaType: .video),
                       let track = tracks.first {
                        let size = try? await track.load(.naturalSize)
                        let transform = try? await track.load(.preferredTransform)
                        if let size = size, let transform = transform {
                            let transformed = size.applying(transform)
                            let w = abs(transformed.width)
                            let h = abs(transformed.height)
                            if w > 0, h > 0 {
                                await MainActor.run {
                                    self.videoAspectRatio = w / h
                                }
                            }
                        }
                    }
                }

                // Generate thumbnails
                Task {
                    let thumbs = await ThumbnailGenerator.generateThumbnails(
                        from: avAsset,
                        count: 20,
                        size: CGSize(width: 80, height: 112)
                    )
                    await MainActor.run {
                        self.thumbnails = thumbs
                    }
                }

                self.setupTimeObserver(for: newPlayer)
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
                let count = try await VideoExporter.exportClips(
                    from: asset,
                    markers: markers
                ) { current, total in
                    Task { @MainActor in
                        exportProgress = "Saving clip \(current) of \(total)..."
                    }
                }
                await MainActor.run {
                    isExporting = false
                    if self.alwaysDeleteOriginal {
                        self.deleteOriginalVideo()
                    } else {
                        self.alertTitle = "Clips Saved!"
                        self.alertMessage = "\(count) clip\(count == 1 ? "" : "s") saved to your photo library."
                        self.showAlert = true
                    }
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    alertTitle = "Export Error"
                    alertMessage = error.localizedDescription
                    showAlert = true
                }
            }
        }
    }

    private func deleteOriginalVideo() {
        guard let phAsset = sourcePhAsset else { return }
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets([phAsset] as NSArray)
        }) { success, error in
            DispatchQueue.main.async {
                if success {
                    self.alertTitle = "Deleted"
                    self.alertMessage = "The original video has been deleted."
                } else {
                    self.alertTitle = "Error"
                    self.alertMessage = error?.localizedDescription ?? "Could not delete the original video."
                }
                self.showAlert = true
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
        sourcePhAsset = nil
        markers = []
        currentTime = 0
        duration = 0
        thumbnails = []
        videoAspectRatio = 16.0 / 9.0
    }
}

// MARK: - PHPicker UIKit Wrapper

struct VideoPicker: UIViewControllerRepresentable {
    var onPick: (String?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .videos
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (String?) -> Void

        init(onPick: @escaping (String?) -> Void) {
            self.onPick = onPick
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            let identifier = results.first?.assetIdentifier
            onPick(identifier)
        }
    }
}
