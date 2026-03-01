import SwiftUI

struct MarkerEditorView: View {
    @Binding var markers: [ClipMarker]
    let currentTime: Double
    var videoBreakpoints: [Double] = []

    var body: some View {
        VStack(spacing: 12) {
            // Action buttons
            HStack(spacing: 10) {
                Button(action: markStart) {
                    Label {
                        Text("Start clip")
                            .font(.system(.subheadline, weight: .semibold))
                    } icon: {
                        Image(systemName: "arrow.right.to.line")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundColor(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(markerColor(for: nextClipIndex))
                    )
                }

                Button(action: markEnd) {
                    Label {
                        Text("End clip")
                            .font(.system(.subheadline, weight: .semibold))
                    } icon: {
                        Image(systemName: "arrow.left.to.line")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundColor(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(canMarkEnd ? markerColor(for: markers.count - 1) : markerColor(for: nextClipIndex).opacity(0.45))
                    )
                }
                .disabled(!canMarkEnd)
            }

            // Marker list
            if markers.isEmpty {
                HStack {
                    Image(systemName: "hand.draw")
                        .foregroundStyle(.quaternary)
                    Text("Scrub to a position and tap Start clip")
                        .font(.system(.footnote, weight: .regular))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 8)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(Array(markers.enumerated()), id: \.element.id) { index, marker in
                            HStack(spacing: 12) {
                                // Color accent bar
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(markerColor(for: index))
                                    .frame(width: 4, height: 32)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Clip \(index + 1)")
                                        .font(.system(.subheadline, weight: .semibold))

                                    Text(marker.formattedRange())
                                        .font(.custom("HelveticaNeue-Light", size: 12))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                // Status indicator
                                if marker.isComplete {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.green.opacity(0.7))
                                } else {
                                    Text("...")
                                        .font(.system(.caption, design: .monospaced, weight: .bold))
                                        .foregroundStyle(.orange)
                                }

                                Button {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        markers.removeAll { $0.id == marker.id }
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.secondary.opacity(0.6))
                                        .frame(width: 32, height: 32)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(Color(UIColor.tertiarySystemFill))
                                        )
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(UIColor.secondarySystemGroupedBackground))
                            )
                        }
                    }
                }
                .frame(maxHeight: markers.count <= 1 ? CGFloat(markers.count) * 68 : 98)
            }
        }
    }

    private var canMarkEnd: Bool {
        guard let last = markers.last, last.end == nil else { return false }
        // Disable End clip if current time is in a different video than the start
        if !videoBreakpoints.isEmpty {
            return videoIndex(for: currentTime) == videoIndex(for: last.start)
        }
        return true
    }

    /// Returns which video segment the given time falls in (index into videoBreakpoints).
    private func videoIndex(for time: Double) -> Int {
        (videoBreakpoints.lastIndex(where: { $0 <= time }) ?? 0)
    }

    // Index the next clip will get (used to color the action buttons)
    private var nextClipIndex: Int {
        if let last = markers.last, !last.isComplete {
            return markers.count - 1  // will replace the incomplete marker
        }
        return markers.count  // will append a new one
    }

    private func markStart() {
        if let last = markers.last, !last.isComplete {
            markers.removeLast()
        }
        markers.append(ClipMarker(start: currentTime))
    }

    private func markEnd() {
        guard var last = markers.last, last.end == nil else { return }
        let endTime = currentTime
        guard endTime > last.start else { return }
        // Prevent cross-video clips
        if !videoBreakpoints.isEmpty {
            guard videoIndex(for: endTime) == videoIndex(for: last.start) else { return }
        }
        last.end = endTime
        markers[markers.count - 1] = last
    }

    private func markerColor(for index: Int) -> Color {
        let colors: [Color] = [.accent, .orange, .purple, .cyan, .pink, .teal]
        return colors[index % colors.count]
    }
}
