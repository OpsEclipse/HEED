import Foundation

struct TaskAnalysisFixtureCompiler: TaskAnalysisCompiling {
    enum Mode: String, Sendable {
        case success
        case empty
        case failure
    }

    private let mode: Mode
    private let delay: Duration

    nonisolated init(mode: Mode = .success, delay: Duration = .seconds(1)) {
        self.mode = mode
        self.delay = delay
    }

    nonisolated init(processInfo: ProcessInfo = .processInfo) {
        self.mode = Self.mode(from: processInfo.arguments)
        self.delay = processInfo.arguments.contains("--heed-ui-test") ? .milliseconds(250) : .milliseconds(850)
    }

    nonisolated func compile(session: TranscriptSession) async throws -> TaskAnalysisResult {
        try await Task.sleep(for: delay)
        try Task.checkCancellation()

        switch mode {
        case .success:
            return makeSuccessResult(from: session)
        case .empty:
            return makeEmptyResult(from: session)
        case .failure:
            throw NSError(domain: "TaskAnalysisFixtureCompiler", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Could not compile tasks"
            ])
        }
    }

    nonisolated private static func mode(from arguments: [String]) -> Mode {
        guard let rawValue = arguments.first(where: { $0.hasPrefix("--heed-ui-test-task-analysis=") })?
            .split(separator: "=", maxSplits: 1)
            .last
        else {
            return .success
        }

        return Mode(rawValue: String(rawValue)) ?? .success
    }

    nonisolated private func makeSuccessResult(from session: TranscriptSession) -> TaskAnalysisResult {
        let segments = Array(session.segments.prefix(3))
        let firstSegment = segments[safe: 0]
        let secondSegment = segments[safe: 1]
        let thirdSegment = segments[safe: 2] ?? firstSegment

        return TaskAnalysisResult(
            summary: "The meeting focused on confirming audio capture and keeping transcript labels understandable.",
            tasks: [
                CompiledTask(
                    id: "verify-audio-paths",
                    title: "Verify the two-way audio path before the next session",
                    details: "Run one more quick check that the microphone and remote call audio both stay readable in the transcript.",
                    type: .followUp,
                    assigneeHint: nil,
                    evidenceSegmentIDs: [secondSegment?.id, firstSegment?.id].compactMap { $0 },
                    evidenceExcerpt: secondSegment?.text ?? firstSegment?.text ?? "Audio capture was reviewed."
                ),
                CompiledTask(
                    id: "review-source-labels",
                    title: "Review the live source labels in the transcript",
                    details: "Make sure the separate MIC and SYSTEM labels remain easy to scan during a live meeting.",
                    type: .feature,
                    assigneeHint: nil,
                    evidenceSegmentIDs: [thirdSegment?.id].compactMap { $0 },
                    evidenceExcerpt: thirdSegment?.text ?? "Source labels were discussed."
                )
            ],
            decisions: [
                CompiledNote(
                    id: "remote-audio-confirmed",
                    title: "Remote call audio is coming through",
                    details: "The team confirmed that the system-audio side of the call was audible.",
                    evidenceSegmentIDs: [secondSegment?.id].compactMap { $0 },
                    evidenceExcerpt: secondSegment?.text ?? "Remote call audio is coming through."
                )
            ],
            followUps: [
                CompiledNote(
                    id: "keep-shell-readable",
                    title: "Keep the live transcript easy to read",
                    details: "The team wants the transcript shell to stay clear while showing separate source labels.",
                    evidenceSegmentIDs: [thirdSegment?.id].compactMap { $0 },
                    evidenceExcerpt: thirdSegment?.text ?? "Heed is showing separate live labels."
                )
            ],
            noTasksReason: nil,
            warnings: ["Preview only. This build keeps task compilation local while the OpenAI-backed compile path is still in progress."]
        )
    }

    nonisolated private func makeEmptyResult(from session: TranscriptSession) -> TaskAnalysisResult {
        let firstSegment = session.segments.first

        return TaskAnalysisResult(
            summary: "The meeting mostly confirmed status and did not state a clear next action.",
            tasks: [],
            decisions: [
                CompiledNote(
                    id: "status-check",
                    title: "Audio status was confirmed",
                    details: "The transcript shows a quick confirmation that the setup was working.",
                    evidenceSegmentIDs: [firstSegment?.id].compactMap { $0 },
                    evidenceExcerpt: firstSegment?.text ?? "The setup was confirmed."
                )
            ],
            followUps: [],
            noTasksReason: "No clear tasks found",
            warnings: ["Preview only. This build keeps task compilation local while the OpenAI-backed compile path is still in progress."]
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else {
            return nil
        }

        return self[index]
    }
}
