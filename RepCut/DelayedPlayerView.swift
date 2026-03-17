import SwiftUI
import AVFoundation

struct DelayedPlayerView: UIViewRepresentable {
    let displayLayer: AVSampleBufferDisplayLayer

    func makeUIView(context: Context) -> DelayedPlayerUIView {
        let view = DelayedPlayerUIView()
        view.displayLayer = displayLayer
        view.layer.addSublayer(displayLayer)
        displayLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: DelayedPlayerUIView, context: Context) {
        displayLayer.frame = uiView.bounds
    }
}

class DelayedPlayerUIView: UIView {
    var displayLayer: AVSampleBufferDisplayLayer?

    override func layoutSubviews() {
        super.layoutSubviews()
        displayLayer?.frame = bounds
    }
}

// MARK: - Zoomable Video View (pinch-to-zoom + pan)

struct ZoomableVideoView: UIViewRepresentable {
    let displayLayer: AVSampleBufferDisplayLayer
    var onLongPressChanged: ((Bool) -> Void)?

    func makeUIView(context: Context) -> ZoomableVideoUIView {
        let view = ZoomableVideoUIView()
        view.onLongPressChanged = onLongPressChanged
        view.setupDisplayLayer(displayLayer)
        return view
    }

    func updateUIView(_ uiView: ZoomableVideoUIView, context: Context) {
        uiView.onLongPressChanged = onLongPressChanged
        uiView.updateLayerFrame()
    }
}

class ZoomableVideoUIView: UIView {
    private var displayLayer: AVSampleBufferDisplayLayer?
    private var currentScale: CGFloat = 1.0
    private var currentTranslation: CGPoint = .zero
    private var lastScale: CGFloat = 1.0
    var onLongPressChanged: ((Bool) -> Void)?

    func setupDisplayLayer(_ layer: AVSampleBufferDisplayLayer) {
        self.displayLayer = layer
        self.layer.addSublayer(layer)
        layer.videoGravity = .resizeAspectFill
        clipsToBounds = true

        // Pinch gesture
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        addGestureRecognizer(pinch)

        // Pan gesture (only when zoomed)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 2
        pan.delegate = self
        addGestureRecognizer(pan)

        // Double tap to reset zoom
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        // Long press (for slow-mo in analysis mode)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.3
        longPress.delegate = self
        addGestureRecognizer(longPress)
    }

    func updateLayerFrame() {
        applyTransform()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyTransform()
    }

    private func applyTransform() {
        guard let layer = displayLayer else { return }

        let scaledWidth = bounds.width * currentScale
        let scaledHeight = bounds.height * currentScale

        // Clamp translation so the video doesn't go off-screen
        let maxTx = max(0, (scaledWidth - bounds.width) / 2)
        let maxTy = max(0, (scaledHeight - bounds.height) / 2)
        currentTranslation.x = min(maxTx, max(-maxTx, currentTranslation.x))
        currentTranslation.y = min(maxTy, max(-maxTy, currentTranslation.y))

        layer.frame = CGRect(
            x: (bounds.width - scaledWidth) / 2 + currentTranslation.x,
            y: (bounds.height - scaledHeight) / 2 + currentTranslation.y,
            width: scaledWidth,
            height: scaledHeight
        )
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .changed:
            let newScale = lastScale * gesture.scale
            currentScale = min(max(newScale, 1.0), 5.0)
            applyTransform()
        case .ended, .cancelled:
            lastScale = currentScale
            if currentScale < 1.05 {
                // Snap back to 1x
                UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
                    self.currentScale = 1.0
                    self.lastScale = 1.0
                    self.currentTranslation = .zero
                    self.applyTransform()
                }
            }
        default: break
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard currentScale > 1.05 else { return }
        let translation = gesture.translation(in: self)
        switch gesture.state {
        case .changed:
            currentTranslation.x += translation.x
            currentTranslation.y += translation.y
            gesture.setTranslation(.zero, in: self)
            applyTransform()
        default: break
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if currentScale > 1.05 {
            // Reset to 1x
            UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
                self.currentScale = 1.0
                self.lastScale = 1.0
                self.currentTranslation = .zero
                self.applyTransform()
            }
        } else {
            // Zoom to 2.5x centered on tap point
            let tapPoint = gesture.location(in: self)
            let centerOffset = CGPoint(
                x: (bounds.midX - tapPoint.x) * 1.5,
                y: (bounds.midY - tapPoint.y) * 1.5
            )
            UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
                self.currentScale = 2.5
                self.lastScale = 2.5
                self.currentTranslation = centerOffset
                self.applyTransform()
            }
        }
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            onLongPressChanged?(true)
        case .ended, .cancelled:
            onLongPressChanged?(false)
        default: break
        }
    }
}

extension ZoomableVideoUIView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                          shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}

// MARK: - Frame Display Helper

class FrameDisplayManager {
    let displayLayer = AVSampleBufferDisplayLayer()
    private var lastEnqueuedTimestamp: TimeInterval = 0

    /// Flush the display layer (call when seeking or switching modes)
    func flush() {
        displayLayer.flush()
        lastEnqueuedTimestamp = 0
    }

    func enqueuePixelBuffer(_ pixelBuffer: CVPixelBuffer, at timestamp: TimeInterval) {
        // If timestamp goes backward, flush the layer so it accepts the earlier frame
        if timestamp < lastEnqueuedTimestamp - 0.01 {
            displayLayer.flush()
        }
        lastEnqueuedTimestamp = timestamp

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMTime(seconds: timestamp, preferredTimescale: 600),
            decodeTimeStamp: .invalid
        )

        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )

        guard let fmtDesc = formatDescription else { return }

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: fmtDesc,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )

        guard let sb = sampleBuffer else { return }

        if displayLayer.status == .failed {
            displayLayer.flush()
        }

        displayLayer.enqueue(sb)
    }
}
