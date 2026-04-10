import SwiftUI

struct TranscriptCanvasView: View {
    let state: RecordingState
    let session: TranscriptSession?
    let segments: [TranscriptSegment]
    @Binding var autoScrollEnabled: Bool

    private var emptyTitle: String {
        "Press record to begin the full transcript"
    }

    var body: some View {
        TranscriptScroller(
            segments: segments,
            emptyTitle: emptyTitle,
            autoScrollEnabled: $autoScrollEnabled
        )
        .frame(maxWidth: 760, maxHeight: .infinity, alignment: .top)
        .padding(.top, 56)
        .padding(.horizontal, 28)
        .padding(.bottom, 104)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct TranscriptScroller: View {
    let segments: [TranscriptSegment]
    let emptyTitle: String
    @Binding var autoScrollEnabled: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if segments.isEmpty {
                        Text(emptyTitle)
                            .font(.system(size: 18, weight: .regular, design: .default))
                            .foregroundStyle(HeedTheme.ColorToken.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 24)
                            .accessibilityIdentifier("empty-state")
                    } else {
                        ForEach(segments) { segment in
                            TranscriptSegmentView(segment: segment)
                                .id(segment.id)
                        }
                    }

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
            .scrollIndicators(.hidden)
            .onChange(of: segments.count) {
                guard autoScrollEnabled else {
                    return
                }

                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo("timeline-bottom", anchor: .bottom)
                }
            }
        }
    }
}

private struct TranscriptSegmentView: View {
    let segment: TranscriptSegment

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
                .font(.system(size: 19, weight: .regular, design: .default))
                .lineSpacing(7)
                .foregroundStyle(HeedTheme.ColorToken.textPrimary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("segment-\(segment.source.rawValue)")
    }
}
