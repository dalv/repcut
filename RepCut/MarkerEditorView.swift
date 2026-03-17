import SwiftUI

struct MarkerEditorView: View {
    @Binding var markers: [ClipMarker]
    let currentTime: Double
    var videoBreakpoints: [Double] = []
    var duration: Double = 0
    var clipPanelExpanded: Bool = false
    var onScrub: ((Double) -> Void)?
    var onSeekTo: ((Double) -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            // Combined row: [◀1s] [time] [1s▶] | [Start clip] [End clip]
            HStack(spacing: 6) {
                // Scrub back
                Button { onScrub?(-1) } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 9, weight: .bold))
                        Text("1s")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .background(Capsule().fill(Color(UIColor.tertiarySystemFill)))
                }

                // Current time + total duration
                VStack(spacing: 1) {
                    Text(ClipMarker.formatTime(currentTime))
                        .font(.custom("HelveticaNeue-Light", size: 18))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                        .monospacedDigit()
                        .lineLimit(1)
                    if duration > 0 {
                        Text(ClipMarker.formatTime(duration))
                            .font(.custom("HelveticaNeue-Light", size: 18))
                            .foregroundStyle(.quaternary)
                            .monospacedDigit()
                    }
                }
                .fixedSize(horizontal: true, vertical: false)

                // Scrub forward
                Button { onScrub?(1) } label: {
                    HStack(spacing: 2) {
                        Text("1s")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        Image(systemName: "chevron.forward")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .background(Capsule().fill(Color(UIColor.tertiarySystemFill)))
                }

                Divider()
                    .frame(height: 26)
                    .padding(.horizontal, 2)

                // Start clip
                Button(action: markStart) {
                    Label {
                        Text("Start clip")
                            .font(.system(size: 13, weight: .semibold))
                    } icon: {
                        Image(systemName: "arrow.right.to.line")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundColor(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(canMarkEnd
                                  ? markerColor(for: nextClipIndex).opacity(0.45)
                                  : markerColor(for: nextClipIndex))
                    )
                }

                // End clip
                Button(action: markEnd) {
                    Label {
                        Text("End clip")
                            .font(.system(size: 13, weight: .semibold))
                    } icon: {
                        Image(systemName: "arrow.left.to.line")
                            .font(.system(size: 10, weight: .bold))
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

            // Clip list — only visible when panel is expanded
            if clipPanelExpanded && !markers.isEmpty {
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
                                        .font(.system(size: 13, weight: .semibold))

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
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
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
                            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .onTapGesture { onSeekTo?(marker.start) }
                        }
                    }
                }
                .frame(height: 138)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if markers.isEmpty {
                HStack {
                    Image(systemName: "hand.draw")
                        .foregroundStyle(.quaternary)
                    Text("Scrub to a position and tap Start clip")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 8)
            }
            // When clips exist but panel is collapsed: nothing shown below buttons
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
