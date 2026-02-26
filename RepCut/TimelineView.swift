import SwiftUI
import UIKit

struct TimelineView: View {
    @Binding var currentTime: Double
    let duration: Double
    let markers: [ClipMarker]
    let thumbnails: [UIImage]
    var playheadColor: Color = .accent
    var onSeek: (Double) -> Void

    private let thumbHeight: CGFloat = 60

    var body: some View {
        ZStack {
            // Filmstrip background
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.systemFill).opacity(0.5))
                .frame(height: thumbHeight + 4)
                .padding(.horizontal, 12)

            FilmstripScrollView(
                thumbnails: thumbnails,
                currentTime: $currentTime,
                duration: duration,
                markers: markers,
                onSeek: onSeek
            )
            .frame(height: thumbHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 14)

            // Fixed center playhead
            VStack(spacing: 0) {
                // Top handle
                Capsule()
                    .fill(playheadColor)
                    .frame(width: 14, height: 5)

                // Line
                Rectangle()
                    .fill(playheadColor)
                    .frame(width: 2.5, height: thumbHeight)

                // Bottom handle
                Capsule()
                    .fill(playheadColor)
                    .frame(width: 14, height: 5)
            }
            .shadow(color: playheadColor.opacity(0.4), radius: 4, y: 0)
            .allowsHitTesting(false)
        }
        .frame(height: thumbHeight + 18)
    }
}

// MARK: - UIKit Filmstrip

struct FilmstripScrollView: UIViewRepresentable {
    let thumbnails: [UIImage]
    @Binding var currentTime: Double
    let duration: Double
    let markers: [ClipMarker]
    let onSeek: (Double) -> Void

    static let baseThumbWidth: CGFloat = 40
    static let thumbHeight: CGFloat = 60

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.decelerationRate = .fast
        scrollView.delegate = context.coordinator
        scrollView.clipsToBounds = true
        scrollView.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        scrollView.layer.cornerRadius = 8

        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        pinch.delegate = context.coordinator
        scrollView.addGestureRecognizer(pinch)

        context.coordinator.scrollView = scrollView
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        let coord = context.coordinator
        coord.parent = self

        let viewWidth = scrollView.bounds.width
        guard viewWidth > 0 else { return }

        // On first load with thumbnails, zoom so the full strip fits exactly on screen
        if !coord.hasSetInitialZoom && !thumbnails.isEmpty {
            let fitZoom = viewWidth / (CGFloat(thumbnails.count) * Self.baseThumbWidth)
            coord.zoomScale = fitZoom
            coord.minZoom = fitZoom
            coord.hasSetInitialZoom = true
        }

        let thumbWidth = Self.baseThumbWidth * coord.zoomScale
        let totalStripWidth = CGFloat(max(thumbnails.count, 1)) * thumbWidth
        let halfView = viewWidth / 2
        let contentWidth = totalStripWidth + viewWidth

        // Update content size
        scrollView.contentSize = CGSize(width: contentWidth, height: Self.thumbHeight)

        // Rebuild thumbnails if count changed
        if coord.lastThumbnailCount != thumbnails.count {
            coord.rebuildThumbnails(
                in: scrollView,
                thumbnails: thumbnails,
                thumbWidth: thumbWidth,
                halfView: halfView
            )
            coord.lastThumbnailCount = thumbnails.count
        }

        // Update frames if zoom changed
        if abs(coord.lastThumbWidth - thumbWidth) > 0.1 {
            coord.relayoutThumbnails(thumbWidth: thumbWidth, halfView: halfView)
            coord.lastThumbWidth = thumbWidth
        }

        // Update marker overlays
        let markerKey = markers.map { "\($0.id)\($0.start)\($0.end ?? -1)" }.joined()
        if coord.lastMarkerKey != markerKey || abs(coord.lastThumbWidth - thumbWidth) > 0.1 {
            coord.updateMarkerOverlays(
                in: scrollView,
                markers: markers,
                duration: duration,
                totalStripWidth: totalStripWidth,
                halfView: halfView
            )
            coord.lastMarkerKey = markerKey
        }

        // Sync scroll position from time (only when user is NOT scrolling)
        if !coord.isUserScrolling && totalStripWidth > 0 {
            let targetOffset = CGFloat(duration > 0 ? currentTime / duration : 0) * totalStripWidth
            if abs(scrollView.contentOffset.x - targetOffset) > 0.5 {
                scrollView.contentOffset = CGPoint(x: targetOffset, y: 0)
            }
        }

        coord.totalStripWidth = totalStripWidth
        coord.halfView = halfView
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var parent: FilmstripScrollView
        weak var scrollView: UIScrollView?

        var isUserScrolling = false
        var zoomScale: CGFloat = 1.0
        var minZoom: CGFloat = 0.05
        var hasSetInitialZoom = false
        var totalStripWidth: CGFloat = 0
        var halfView: CGFloat = 0
        var lastThumbnailCount = 0
        var lastThumbWidth: CGFloat = 0
        var lastMarkerKey = ""

        var thumbnailViews: [UIImageView] = []
        var markerViews: [UIView] = []

        init(parent: FilmstripScrollView) {
            self.parent = parent
        }

        // MARK: Layout

        func rebuildThumbnails(in scrollView: UIScrollView, thumbnails: [UIImage], thumbWidth: CGFloat, halfView: CGFloat) {
            thumbnailViews.forEach { $0.removeFromSuperview() }
            thumbnailViews = []

            for (i, thumb) in thumbnails.enumerated() {
                let iv = UIImageView(image: thumb)
                iv.contentMode = .scaleAspectFill
                iv.clipsToBounds = true
                iv.frame = CGRect(
                    x: halfView + CGFloat(i) * thumbWidth,
                    y: 0,
                    width: thumbWidth + 0.5, // Slight overlap to avoid hairline gaps
                    height: FilmstripScrollView.thumbHeight
                )
                scrollView.addSubview(iv)
                thumbnailViews.append(iv)
            }
            lastThumbWidth = thumbWidth
        }

        func relayoutThumbnails(thumbWidth: CGFloat, halfView: CGFloat) {
            for (i, iv) in thumbnailViews.enumerated() {
                iv.frame = CGRect(
                    x: halfView + CGFloat(i) * thumbWidth,
                    y: 0,
                    width: thumbWidth + 0.5,
                    height: FilmstripScrollView.thumbHeight
                )
            }
        }

        func updateMarkerOverlays(in scrollView: UIScrollView, markers: [ClipMarker], duration: Double, totalStripWidth: CGFloat, halfView: CGFloat) {
            markerViews.forEach { $0.removeFromSuperview() }
            markerViews = []

            // Accent indigo color matching Color.accent
            let accentUIColor = UIColor(red: 0.38, green: 0.40, blue: 0.95, alpha: 1.0)
            let colors: [UIColor] = [accentUIColor, .systemOrange, .systemPurple, .systemCyan, .systemPink, .systemTeal]

            for (index, marker) in markers.enumerated() {
                guard let end = marker.end, duration > 0 else { continue }
                let startX = halfView + CGFloat(marker.start / duration) * totalStripWidth
                let endX = halfView + CGFloat(end / duration) * totalStripWidth
                let color = colors[index % colors.count]

                let overlay = UIView()
                overlay.frame = CGRect(
                    x: startX,
                    y: 0,
                    width: max(endX - startX, 2),
                    height: FilmstripScrollView.thumbHeight
                )
                overlay.backgroundColor = color.withAlphaComponent(0.25)
                overlay.layer.borderColor = color.withAlphaComponent(0.8).cgColor
                overlay.layer.borderWidth = 2
                overlay.layer.cornerRadius = 4
                overlay.isUserInteractionEnabled = false
                scrollView.addSubview(overlay)
                markerViews.append(overlay)
            }
        }

        // MARK: UIScrollViewDelegate

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            isUserScrolling = true
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard isUserScrolling, totalStripWidth > 0, parent.duration > 0 else { return }

            let offset = scrollView.contentOffset.x
            let fraction = max(0, min(1, Double(offset / totalStripWidth)))
            let newTime = fraction * parent.duration

            parent.currentTime = newTime
            parent.onSeek(newTime)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                finalizeScroll(scrollView)
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            finalizeScroll(scrollView)
        }

        private func finalizeScroll(_ scrollView: UIScrollView) {
            isUserScrolling = false
            guard totalStripWidth > 0, parent.duration > 0 else { return }
            let fraction = max(0, min(1, Double(scrollView.contentOffset.x / totalStripWidth)))
            let newTime = fraction * parent.duration
            parent.currentTime = newTime
            parent.onSeek(newTime)
        }

        // MARK: Gesture Delegate

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            return true
        }

        // MARK: Pinch to Zoom

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let scrollView = scrollView else { return }

            if gesture.state == .changed {
                let oldScale = zoomScale
                let newScale = max(minZoom, min(4.0, zoomScale * gesture.scale))
                gesture.scale = 1.0
                guard abs(newScale - oldScale) > 0.001 else { return }

                let oldTotalWidth = CGFloat(thumbnailViews.count) * FilmstripScrollView.baseThumbWidth * oldScale
                let fraction = oldTotalWidth > 0 ? scrollView.contentOffset.x / oldTotalWidth : 0

                zoomScale = newScale
                let newThumbWidth = FilmstripScrollView.baseThumbWidth * newScale
                let newTotalWidth = CGFloat(thumbnailViews.count) * newThumbWidth
                let viewWidth = scrollView.bounds.width
                let newHalfView = viewWidth / 2

                scrollView.contentSize = CGSize(
                    width: newTotalWidth + viewWidth,
                    height: FilmstripScrollView.thumbHeight
                )
                relayoutThumbnails(thumbWidth: newThumbWidth, halfView: newHalfView)
                scrollView.contentOffset = CGPoint(x: fraction * newTotalWidth, y: 0)

                totalStripWidth = newTotalWidth
                halfView = newHalfView
                lastThumbWidth = newThumbWidth

                updateMarkerOverlays(
                    in: scrollView,
                    markers: parent.markers,
                    duration: parent.duration,
                    totalStripWidth: newTotalWidth,
                    halfView: newHalfView
                )
            }
        }
    }
}
