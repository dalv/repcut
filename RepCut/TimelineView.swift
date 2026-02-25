import SwiftUI

struct TimelineView: View {
    @Binding var currentTime: Double
    let duration: Double
    let markers: [ClipMarker]
    var onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                // Track background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 8)

                // Marker regions
                ForEach(Array(markers.enumerated()), id: \.element.id) { index, marker in
                    if let end = marker.end, duration > 0 {
                        let startX = CGFloat(marker.start / duration) * width
                        let endX = CGFloat(end / duration) * width
                        RoundedRectangle(cornerRadius: 2)
                            .fill(markerColor(for: index).opacity(0.4))
                            .frame(width: max(endX - startX, 2), height: 8)
                            .offset(x: startX)
                    }
                }

                // Playhead
                if duration > 0 {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 18, height: 18)
                        .shadow(radius: 2)
                        .offset(x: CGFloat(currentTime / duration) * width - 9)
                }
            }
            .frame(height: 18)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = max(0, min(1, value.location.x / width))
                        let time = Double(fraction) * duration
                        currentTime = time
                        onSeek(time)
                    }
            )
        }
        .frame(height: 18)
    }

    private func markerColor(for index: Int) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan]
        return colors[index % colors.count]
    }
}
