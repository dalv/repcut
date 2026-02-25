import SwiftUI
import PhotosUI
import AVKit
import Photos

struct ContentView: View {
    @State private var videoAsset: AVAsset?
    @State private var player: AVPlayer?
    @State private var duration: Double = 0
    @State private var currentTime: Double = 0
    @State private var markers: [ClipMarker] = []
    @State private var timeObserver: Any?

    @State private var isLoadingVideo = false
    @State private var showPicker = false
    @State private var isExporting = false
    @State private var exportProgress: String = ""
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    var body: some View {
        NavigationStack {
            if let player = player {
                editorView(player: player)
                    .navigationTitle("RepCut")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("New Video") {
                                resetState()
                            }
                        }
                    }
            } else {
                pickerView
                    .navigationTitle("RepCut")
            }
        }
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
    }

    // MARK: - Picker View

    private var pickerView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "scissors")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Select a video to split into clips")
                .font(.title3)
                .foregroundStyle(.secondary)
            Button {
                showPicker = true
            } label: {
                Label("Choose Video", systemImage: "photo.on.rectangle")
                    .font(.headline)
                    .frame(width: 200, height: 50)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoadingVideo)

            if isLoadingVideo {
                ProgressView()
                    .padding(.top, 8)
            }

            Spacer()
        }
    }

    // MARK: - Editor View

    private func editorView(player: AVPlayer) -> some View {
        VStack(spacing: 0) {
            // Video player
            VideoPlayerView(player: player)
                .frame(height: 250)
                .background(Color.black)

            VStack(spacing: 12) {
                // Current time display
                Text(ClipMarker.formatTime(currentTime))
                    .font(.system(.title2, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(.top, 8)

                // Timeline scrubber
                TimelineView(
                    currentTime: $currentTime,
                    duration: duration,
                    markers: markers,
                    onSeek: { time in
                        player.seek(
                            to: CMTime(seconds: time, preferredTimescale: 600),
                            toleranceBefore: .zero,
                            toleranceAfter: .zero
                        )
                    }
                )
                .padding(.horizontal)

                // Marker editor
                MarkerEditorView(markers: $markers, currentTime: currentTime)
                    .padding(.horizontal)

                Spacer()

                // Cut button
                if !markers.isEmpty {
                    Button(action: cutAndSave) {
                        HStack {
                            if isExporting {
                                ProgressView()
                                    .tint(.white)
                                Text(exportProgress)
                            } else {
                                Image(systemName: "scissors")
                                Text("Cut & Save \(completeMarkerCount) Clip\(completeMarkerCount == 1 ? "" : "s")")
                            }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(isExporting || completeMarkerCount == 0)
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }
            }
        }
    }

    // MARK: - Logic

    private var completeMarkerCount: Int {
        markers.filter { $0.isComplete }.count
    }

    private func loadVideo(assetIdentifier: String) {
        isLoadingVideo = true

        // Fetch PHAsset by identifier
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let phAsset = fetchResult.firstObject else {
            isLoadingVideo = false
            alertTitle = "Error"
            alertMessage = "Could not find the selected video."
            showAlert = true
            return
        }

        // Request AVAsset directly — no file copy needed
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

                self.videoAsset = avAsset
                let playerItem = AVPlayerItem(asset: avAsset)
                let newPlayer = AVPlayer(playerItem: playerItem)
                self.player = newPlayer
                self.markers = []
                self.currentTime = 0

                Task {
                    if let d = try? await avAsset.load(.duration) {
                        await MainActor.run {
                            self.duration = d.seconds
                        }
                    }
                }

                self.setupTimeObserver(for: newPlayer)
            }
        }
    }

    private func setupTimeObserver(for player: AVPlayer) {
        if let old = timeObserver {
            self.player?.removeTimeObserver(old)
        }
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
                    alertTitle = "Done!"
                    alertMessage = "\(count) clip\(count == 1 ? "" : "s") saved to your photo library."
                    showAlert = true
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

    private func resetState() {
        if let old = timeObserver {
            player?.removeTimeObserver(old)
        }
        player?.pause()
        player = nil
        videoAsset = nil
        markers = []
        currentTime = 0
        duration = 0
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
