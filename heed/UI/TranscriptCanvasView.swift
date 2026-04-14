import SwiftUI

struct TranscriptCanvasView<Appendix: View>: View {
    let state: RecordingState
    let session: TranscriptSession?
    let micSegments: [TranscriptSegment]
    let systemSegments: [TranscriptSegment]
    let sourceProcessingStates: [AudioSource: SourceProcessingState]
    let sourceJumpRequest: TaskAnalysisController.SourceJumpRequest?
    let highlightedSegmentID: UUID?
    let appendixFocusNonce: Int
    @Binding var autoScrollEnabled: Bool
    let appendix: Appendix

    init(
        state: RecordingState,
        session: TranscriptSession?,
        micSegments: [TranscriptSegment],
        systemSegments: [TranscriptSegment],
        sourceProcessingStates: [AudioSource: SourceProcessingState] = [:],
        sourceJumpRequest: TaskAnalysisController.SourceJumpRequest? = nil,
        highlightedSegmentID: UUID? = nil,
        appendixFocusNonce: Int = 0,
        autoScrollEnabled: Binding<Bool>,
        @ViewBuilder appendix: () -> Appendix
    ) {
        self.state = state
        self.session = session
        self.micSegments = micSegments
        self.systemSegments = systemSegments
        self.sourceProcessingStates = sourceProcessingStates
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
        canvasContent
            .frame(maxWidth: 980, maxHeight: .infinity, alignment: .top)
            .padding(.top, 56)
            .padding(.horizontal, 28)
            .padding(.bottom, 104)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var canvasContent: some View {
        switch state {
        case .recording, .stopping:
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("recording-blank-canvas")
        case .processing:
            ProcessingStateView(sourceProcessingStates: sourceProcessingStates)
        case .idle, .requestingPermissions, .ready, .error:
            if micSegments.isEmpty && systemSegments.isEmpty {
                Text(emptyTitle)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(HeedTheme.ColorToken.textPrimary.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 24)
                    .accessibilityIdentifier("empty-state")
            } else {
                SplitTranscriptReviewScroller(
                    micSegments: micSegments,
                    systemSegments: systemSegments,
                    sourceJumpRequest: sourceJumpRequest,
                    highlightedSegmentID: highlightedSegmentID,
                    appendixFocusNonce: appendixFocusNonce,
                    autoScrollEnabled: $autoScrollEnabled
                ) {
                    appendix
                }
            }
        }
    }
}

private struct SplitTranscriptReviewScroller<Appendix: View>: View {
    let micSegments: [TranscriptSegment]
    let systemSegments: [TranscriptSegment]
    let sourceJumpRequest: TaskAnalysisController.SourceJumpRequest?
    let highlightedSegmentID: UUID?
    let appendixFocusNonce: Int
    @Binding var autoScrollEnabled: Bool
    let appendix: Appendix

    init(
        micSegments: [TranscriptSegment],
        systemSegments: [TranscriptSegment],
        sourceJumpRequest: TaskAnalysisController.SourceJumpRequest?,
        highlightedSegmentID: UUID?,
        appendixFocusNonce: Int,
        autoScrollEnabled: Binding<Bool>,
        @ViewBuilder appendix: () -> Appendix
    ) {
        self.micSegments = micSegments
        self.systemSegments = systemSegments
        self.sourceJumpRequest = sourceJumpRequest
        self.highlightedSegmentID = highlightedSegmentID
        self.appendixFocusNonce = appendixFocusNonce
        _autoScrollEnabled = autoScrollEnabled
        self.appendix = appendix()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                SourceTranscriptPanelsView(
                    micSegments: micSegments,
                    systemSegments: systemSegments,
                    sourceJumpRequest: sourceJumpRequest,
                    highlightedSegmentID: highlightedSegmentID
                ) {
                    appendix
                        .id("task-analysis-section-anchor")
                }
                .padding(.bottom, 24)

                Color.clear
                    .frame(height: 1)
                    .id("split-review-bottom")
                    .onAppear {
                        autoScrollEnabled = true
                    }
                    .onDisappear {
                        autoScrollEnabled = false
                    }
            }
            .heedHiddenScrollBars()
            .scrollIndicators(.hidden)
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

private struct ProcessingStateView: View {
    let sourceProcessingStates: [AudioSource: SourceProcessingState]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Finishing transcript")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(HeedTheme.ColorToken.textPrimary)

            Text("Recording is complete. Heed is transcribing each source now.")
                .font(.system(size: 15))
                .foregroundStyle(HeedTheme.ColorToken.textSecondary)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(AudioSource.allCases, id: \.self) { source in
                    HStack(spacing: 10) {
                        Text(source.label)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(HeedTheme.ColorToken.textSecondary)
                            .frame(width: 60, alignment: .leading)

                        Text(statusText(for: source))
                            .font(.system(size: 14))
                            .foregroundStyle(statusColor(for: source))
                    }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 22)
        .frame(maxWidth: 560, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(HeedTheme.ColorToken.panel.opacity(0.96))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(HeedTheme.ColorToken.borderSubtle, lineWidth: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func statusText(for source: AudioSource) -> String {
        switch sourceProcessingStates[source] ?? .queued {
        case .queued:
            return "queued"
        case .processing:
            return "processing"
        case .done:
            return "done"
        case .failed:
            return "failed"
        }
    }

    private func statusColor(for source: AudioSource) -> Color {
        switch sourceProcessingStates[source] ?? .queued {
        case .queued:
            return HeedTheme.ColorToken.textSecondary
        case .processing:
            return HeedTheme.ColorToken.actionYellow
        case .done:
            return HeedTheme.ColorToken.success
        case .failed:
            return HeedTheme.ColorToken.warning
        }
    }
}
