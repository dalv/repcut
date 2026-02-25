import Foundation

struct ClipMarker: Identifiable {
    let id = UUID()
    var start: Double // seconds
    var end: Double?  // seconds, nil until user sets it

    var isComplete: Bool {
        guard let end = end else { return false }
        return end > start
    }

    func formattedRange() -> String {
        let startStr = Self.formatTime(start)
        if let end = end {
            return "\(startStr) → \(Self.formatTime(end))"
        }
        return "\(startStr) → ..."
    }

    static func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let frac = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", mins, secs, frac)
    }
}
