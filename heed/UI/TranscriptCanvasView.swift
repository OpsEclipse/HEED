import SwiftUI

struct TranscriptCanvasView<Appendix: View>: View {
    let state: RecordingState
    let session: TranscriptSession?
    let segments: [TranscriptSegment]
    let sourceJumpRequest: TaskAnalysisController.SourceJumpRequest?
    let highlightedSegmentID: UUID?
    let appendixFocusNonce: Int
    @Binding var autoScrollEnabled: Bool
    let appendix: Appendix

    init(
        state: RecordingState,
        session: TranscriptSession?,
        segments: [TranscriptSegment],
        sourceJumpRequest: TaskAnalysisController.SourceJumpRequest? = nil,
        highlightedSegmentID: UUID? = nil,
        appendixFocusNonce: Int = 0,
        autoScrollEnabled: Binding<Bool>,
        @ViewBuilder appendix: () -> Appendix
    ) {
        self.state = state
        self.session = session
        self.segments = segments
        self.sourceJumpRequest = sourceJumpRequest
        self.highlightedSegmentID = highlightedSegmentID
        self.appendixFocusNonce = appendixFocusNonce
        _autoScrollEnabled = autoScrollEnabled
        self.appendix = appendix()
    }

    private var emptyTitle: String {
        "Press record to begin the full transcript"
    }

    var body: some View {
        TranscriptScroller(
            segments: segments,
            emptyTitle: emptyTitle,
            sourceJumpRequest: sourceJumpRequest,
            highlightedSegmentID: highlightedSegmentID,
            appendixFocusNonce: appendixFocusNonce,
            appendix: appendix,
            autoScrollEnabled: $autoScrollEnabled
        )
        .frame(maxWidth: 760, maxHeight: .infinity, alignment: .top)
        .padding(.top, 56)
        .padding(.horizontal, 28)
        .padding(.bottom, 104)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct TranscriptScroller<Appendix: View>: View {
    let segments: [TranscriptSegment]
    let emptyTitle: String
    let sourceJumpRequest: TaskAnalysisController.SourceJumpRequest?
    let highlightedSegmentID: UUID?
    let appendixFocusNonce: Int
    let appendix: Appendix
    @Binding var autoScrollEnabled: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if segments.isEmpty {
                        Text(emptyTitle)
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(HeedTheme.ColorToken.textPrimary.opacity(0.6))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 24)
                            .accessibilityIdentifier("empty-state")
                    } else {
                        ForEach(segments) { segment in
                            TranscriptSegmentView(
                                segment: segment,
                                isHighlighted: highlightedSegmentID == segment.id
                            )
                            .id(segment.id)
                        }
                    }

                    appendix
                        .id("task-analysis-section-anchor")

                    Color.clear
                        .frame(height: 1)
                        .id("timeline-bottom")
                        .onAppear {
                            autoScrollEnabled = true
                        }
                        .onDisappear {
                            autoScrollEnabled = false
                        }
                }
                .padding(.bottom, 24)
            }
            .heedHiddenScrollBars()
            .scrollIndicators(.hidden)
            .onChange(of: segments.count) {
                guard autoScrollEnabled else {
                    return
                }

                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo("timeline-bottom", anchor: .bottom)
                }
            }
            .onChange(of: sourceJumpRequest?.nonce) {
                guard let sourceJumpRequest else {
                    return
                }

                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(sourceJumpRequest.segmentID, anchor: .center)
                }
            }
            .onChange(of: appendixFocusNonce) {
                guard appendixFocusNonce > 0 else {
                    return
                }

                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("task-analysis-section-anchor", anchor: .top)
                }
            }
        }
    }
}

private struct TranscriptSegmentView: View {
    let segment: TranscriptSegment
    let isHighlighted: Bool

    private var sourceColor: Color {
        switch segment.source {
        case .mic:
            return Color(red: 157 / 255, green: 176 / 255, blue: 163 / 255)
        case .system:
            return Color(red: 186 / 255, green: 164 / 255, blue: 130 / 255)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(segment.source.label) · \(segment.startedAt.heedClockString)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(sourceColor)

            Text(segment.text)
                .font(.system(size: 19, weight: .regular))
                .lineSpacing(7)
                .foregroundStyle(HeedTheme.ColorToken.textPrimary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(HeedTheme.ColorToken.actionYellow.opacity(isHighlighted ? 0.12 : 0))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isHighlighted ? HeedTheme.ColorToken.actionYellow.opacity(0.45) : Color.clear,
                    lineWidth: 1
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.18), value: isHighlighted)
        .accessibilityIdentifier("segment-\(segment.source.rawValue)")
    }
}
