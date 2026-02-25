import SwiftUI

struct MarkerEditorView: View {
    @Binding var markers: [ClipMarker]
    let currentTime: Double

    var body: some View {
        VStack(spacing: 12) {
            // Action buttons
            HStack(spacing: 10) {
                Button(action: markStart) {
                    Label {
                        Text("Mark In")
                            .font(.system(.subheadline, weight: .semibold))
                    } icon: {
                        Image(systemName: "arrow.right.to.line")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundColor(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(red: 0.22, green: 0.78, blue: 0.45))
                    )
                }

                Button(action: markEnd) {
                    Label {
                        Text("Mark Out")
                            .font(.system(.subheadline, weight: .semibold))
                    } icon: {
                        Image(systemName: "arrow.left.to.line")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundColor(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(canMarkEnd ? Color(red: 0.94, green: 0.33, blue: 0.31) : Color.gray.opacity(0.3))
                    )
                }
                .disabled(!canMarkEnd)
            }

            // Marker list
            if markers.isEmpty {
                HStack {
                    Image(systemName: "hand.draw")
                        .foregroundStyle(.quaternary)
                    Text("Scrub to a position and tap Mark In")
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
                                        .font(.system(.caption, design: .monospaced, weight: .regular))
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
                .frame(maxHeight: CGFloat(min(markers.count, 4)) * 68)
            }
        }
    }

    private var canMarkEnd: Bool {
        guard let last = markers.last else { return false }
        return last.end == nil
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
        last.end = endTime
        markers[markers.count - 1] = last
    }

    private func markerColor(for index: Int) -> Color {
        let colors: [Color] = [.accent, .green, .orange, .purple, .pink, .cyan]
        return colors[index % colors.count]
    }
}
