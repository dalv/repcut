import AVFoundation
import Photos

class VideoExporter {

    enum ExportError: LocalizedError {
        case exportFailed(String)
        case photoLibraryDenied

        var errorDescription: String? {
            switch self {
            case .exportFailed(let reason): return "Export failed: \(reason)"
            case .photoLibraryDenied: return "Photo library access denied."
            }
        }
    }

    static func exportClips(
        from asset: AVAsset,
        markers: [ClipMarker],
        progress: @escaping (Int, Int) -> Void
    ) async throws -> Int {
        let completeMarkers = markers.filter { $0.isComplete }
        var savedCount = 0

        for (index, marker) in completeMarkers.enumerated() {
            progress(index + 1, completeMarkers.count)
            try await exportSingleClip(from: asset, start: marker.start, end: marker.end!)
            savedCount += 1
        }

        return savedCount
    }

    private static func exportSingleClip(
        from asset: AVAsset,
        start: Double,
        end: Double
    ) async throws {
        let startTime = CMTime(seconds: start, preferredTimescale: 600)
        let endTime = CMTime(seconds: end, preferredTimescale: 600)
        let timeRange = CMTimeRange(start: startTime, end: endTime)

        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "RepCut_\(UUID().uuidString).mov"
        let outputURL = tempDir.appendingPathComponent(fileName)

        // Clean up any existing file at that path
        try? FileManager.default.removeItem(at: outputURL)

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw ExportError.exportFailed("Could not create export session.")
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.timeRange = timeRange

        await exportSession.export()

        guard exportSession.status == .completed else {
            let reason = exportSession.error?.localizedDescription ?? "Unknown error"
            throw ExportError.exportFailed(reason)
        }

        // Save to Photos
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            try? FileManager.default.removeItem(at: outputURL)
            throw ExportError.photoLibraryDenied
        }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputURL)
        }

        // Clean up temp file
        try? FileManager.default.removeItem(at: outputURL)
    }
}
