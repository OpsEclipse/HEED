import SwiftUI

struct SourceTranscriptPanelsView<Appendix: View>: View {
    let micSegments: [TranscriptSegment]
    let systemSegments: [TranscriptSegment]
    let sourceJumpRequest: TaskAnalysisController.SourceJumpRequest?
    let highlightedSegmentID: UUID?
    let appendix: Appendix

    init(
        micSegments: [TranscriptSegment],
        systemSegments: [TranscriptSegment],
        sourceJumpRequest: TaskAnalysisController.SourceJumpRequest? = nil,
        highlightedSegmentID: UUID? = nil,
        @ViewBuilder appendix: () -> Appendix
    ) {
        self.micSegments = micSegments
        self.systemSegments = systemSegments
        self.sourceJumpRequest = sourceJumpRequest
        self.highlightedSegmentID = highlightedSegmentID
        self.appendix = appendix()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                SourceTranscriptPanel(
                    title: "MIC transcript",
                    emptyText: "No microphone transcript captured",
                    sourceColor: Color(red: 157 / 255, green: 176 / 255, blue: 163 / 255),
                    segments: micSegments,
                    sourceJumpRequest: sourceJumpRequest,
                    highlightedSegmentID: highlightedSegmentID
                )

                SourceTranscriptPanel(
                    title: "SYSTEM transcript",
                    emptyText: "No system audio transcript captured",
                    sourceColor: Color(red: 186 / 255, green: 164 / 255, blue: 130 / 255),
                    segments: systemSegments,
                    sourceJumpRequest: sourceJumpRequest,
                    highlightedSegmentID: highlightedSegmentID
                )
            }

            appendix
        }
    }
}

private struct SourceTranscriptPanel: View {
    let title: String
    let emptyText: String
    let sourceColor: Color
    let segments: [TranscriptSegment]
    let sourceJumpRequest: TaskAnalysisController.SourceJumpRequest?
    let highlightedSegmentID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(sourceColor)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if segments.isEmpty {
                            Text(emptyText)
                                .font(.system(size: 15))
                                .foregroundStyle(HeedTheme.ColorToken.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 6)
                        } else {
                            ForEach(segments) { segment in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(segment.startedAt.heedClockString)
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(sourceColor)

                                    Text(segment.text)
                                        .font(.system(size: 16))
                                        .lineSpacing(5)
                                        .foregroundStyle(HeedTheme.ColorToken.textPrimary)
                                        .textSelection(.enabled)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(HeedTheme.ColorToken.actionYellow.opacity(highlightedSegmentID == segment.id ? 0.12 : 0))
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(
                                            highlightedSegmentID == segment.id ? HeedTheme.ColorToken.actionYellow.opacity(0.45) : Color.clear,
                                            lineWidth: 1
                                        )
                                }
                                .id(segment.id)
                            }
                        }
                    }
                    .padding(.trailing, 6)
                }
                .heedHiddenScrollBars()
                .scrollIndicators(.hidden)
                .onChange(of: sourceJumpRequest?.nonce) {
                    guard let sourceJumpRequest,
                          segments.contains(where: { $0.id == sourceJumpRequest.segmentID }) else {
                        return
                    }

                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(sourceJumpRequest.segmentID, anchor: .center)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 280, maxHeight: 420, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(HeedTheme.ColorToken.panel.opacity(0.96))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(HeedTheme.ColorToken.borderSubtle, lineWidth: 1)
        }
    }
}
