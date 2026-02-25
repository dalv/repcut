import AVFoundation
import UIKit

class ThumbnailGenerator {
    static func generateThumbnails(
        from asset: AVAsset,
        count: Int,
        size: CGSize
    ) async -> [UIImage] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: size.width * 2, height: size.height * 2)

        guard let duration = try? await asset.load(.duration) else { return [] }
        let totalSeconds = duration.seconds
        guard totalSeconds > 0, count > 0 else { return [] }

        let interval = totalSeconds / Double(count)
        var images: [UIImage] = []

        for i in 0..<count {
            let time = CMTime(seconds: interval * Double(i), preferredTimescale: 600)
            do {
                let (cgImage, _) = try await generator.image(at: time)
                images.append(UIImage(cgImage: cgImage))
            } catch {
                // Use a blank placeholder on failure
                let renderer = UIGraphicsImageRenderer(size: size)
                let blank = renderer.image { ctx in
                    UIColor.darkGray.setFill()
                    ctx.fill(CGRect(origin: .zero, size: size))
                }
                images.append(blank)
            }
        }

        return images
    }
}
