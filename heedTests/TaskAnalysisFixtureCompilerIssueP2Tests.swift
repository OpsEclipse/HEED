import Foundation
import Testing
@testable import heed

struct TaskAnalysisFixtureCompilerIssueP2Tests {
    @Test func successFixtureUsesQuotedRemoteAudioSegmentAsFirstEvidenceJumpTarget() async throws {
        let compiler = TaskAnalysisFixtureCompiler(mode: .success, delay: .milliseconds(0))
        let session = TranscriptSession(
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 10),
            duration: 10,
            status: .completed,
            modelName: "ggml-base.en",
            appVersion: "1.0",
            segments: [
                TranscriptSegment(source: .mic, startedAt: 1, endedAt: 2.4, text: "Can you hear me clearly on this side?"),
                TranscriptSegment(source: .system, startedAt: 2, endedAt: 3.5, text: "Yes, the remote call audio is coming through."),
                TranscriptSegment(source: .mic, startedAt: 4.2, endedAt: 5.8, text: "Perfect. Heed is showing separate live labels."),
            ]
        )

        let result = try await compiler.compile(session: session)

        #expect(result.tasks[0].evidenceExcerpt == "Yes, the remote call audio is coming through.")
        #expect(result.tasks[0].evidenceSegmentIDs.first == session.segments[1].id)
    }
}
