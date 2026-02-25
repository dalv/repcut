import SwiftUI

struct MarkerEditorView: View {
    @Binding var markers: [ClipMarker]
    let currentTime: Double

    var body: some View {
        VStack(spacing: 12) {
            // Action buttons
            HStack(spacing: 16) {
                Button(action: markStart) {
                    Label("Mark Start", systemImage: "arrow.right.to.line")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button(action: markEnd) {
                    Label("Mark End", systemImage: "arrow.left.to.line")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!canMarkEnd)
            }

            // Marker list
            if markers.isEmpty {
                Text("Scrub to a position and tap \"Mark Start\" to begin")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                List {
                    ForEach(Array(markers.enumerated()), id: \.element.id) { index, marker in
                        HStack {
                            Circle()
                                .fill(markerColor(for: index))
                                .frame(width: 10, height: 10)
                            Text("Clip \(index + 1)")
                                .fontWeight(.medium)
                            Spacer()
                            Text(marker.formattedRange())
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { indexSet in
                        markers.remove(atOffsets: indexSet)
                    }
                }
                .listStyle(.plain)
                .frame(maxHeight: CGFloat(markers.count) * 50)
            }
        }
    }

    private var canMarkEnd: Bool {
        guard let last = markers.last else { return false }
        return last.end == nil
    }

    private func markStart() {
        // If the last marker is incomplete, remove it before adding a new one
        if let last = markers.last, !last.isComplete {
            markers.removeLast()
        }
        markers.append(ClipMarker(start: currentTime))
    }

    private func markEnd() {
        guard var last = markers.last, last.end == nil else { return }
        let endTime = currentTime
        guard endTime > last.start else { return }
        last.end = endTime
        markers[markers.count - 1] = last
    }

    private func markerColor(for index: Int) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan]
        return colors[index % colors.count]
    }
}
