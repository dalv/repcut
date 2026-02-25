import SwiftUI
import AVKit

struct VideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        controller.view.backgroundColor = .black
        controller.view.layer.cornerRadius = 16
        controller.view.clipsToBounds = true
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // Player is managed externally
    }
}
