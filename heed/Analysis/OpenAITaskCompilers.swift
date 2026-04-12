import Foundation

struct OpenAITaskAnalysisCompiler: TaskAnalysisCompiling {
    private let client: OpenAIResponsesClient

    init(client: OpenAIResponsesClient = OpenAIResponsesClient()) {
        self.client = client
    }

    func compile(session: TranscriptSession) async throws -> TaskAnalysisResult {
        let output: TaskAnalysisOutput = try await client.generateStructuredOutput(
            systemPrompt: Self.systemPrompt,
            userPrompt: Self.userPrompt(for: session),
            schemaName: "task_analysis_result",
            schema: Self.schema
        )

        return TaskAnalysisResult(
            summary: output.summary.heedCollapsedWhitespace,
            tasks: mapTasks(output.tasks, session: session),
            noTasksReason: output.noTasksReason.heedNilIfEmpty,
            warnings: output.warnings.map(\.heedCollapsedWhitespace).filter { !$0.isEmpty }
        )
    }

    fileprivate static func formattedTranscript(_ session: TranscriptSession) -> String {
        session.segments.enumerated().map { index, segment in
            let start = Int(segment.startedAt.rounded(.down))
            let end = Int(segment.endedAt.rounded(.up))
            return "\(index + 1). [\(segment.source.rawValue.uppercased()) \(start)s-\(end)s] \(segment.text.heedCollapsedWhitespace)"
        }
        .joined(separator: "\n")
    }

    private func mapTasks(_ items: [TaskAnalysisOutput.TaskItem], session: TranscriptSession) -> [CompiledTask] {
        var usedIDs = Set<String>()

        return items.map { item in
            let evidence = resolveEvidence(item.evidenceIndices, session: session)
            let taskID = uniqueID(from: item.title, usedIDs: &usedIDs)

            return CompiledTask(
                id: taskID,
                title: item.title.heedCollapsedWhitespace,
                details: item.details.heedCollapsedWhitespace,
                type: item.type.compiledType,
                assigneeHint: item.assigneeHint.heedNilIfEmpty,
                evidenceSegmentIDs: evidence.map(\.id),
                evidenceExcerpt: resolvedExcerpt(
                    preferred: item.evidenceExcerpt,
                    fallbackSegments: evidence.map(\.text),
                    fallbackText: item.details
                )
            )
        }
    }

    private func resolveEvidence(_ indices: [Int], session: TranscriptSession) -> [TranscriptSegment] {
        indices.compactMap { index in
            let offset = index - 1
            guard session.segments.indices.contains(offset) else {
                return nil
            }

            return session.segments[offset]
        }
    }

    private func resolvedExcerpt(preferred: String, fallbackSegments: [String], fallbackText: String) -> String {
        preferred.heedNilIfEmpty
            ?? fallbackSegments.first(where: { !$0.heedCollapsedWhitespace.isEmpty })?.heedCollapsedWhitespace
            ?? fallbackText.heedCollapsedWhitespace
    }

    private func uniqueID(from title: String, usedIDs: inout Set<String>) -> String {
        let base = title.heedSlugified.isEmpty ? "task" : title.heedSlugified
        var candidate = base
        var suffix = 2

        while usedIDs.contains(candidate) {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }

        usedIDs.insert(candidate)
        return candidate
    }

    private static let systemPrompt = """
    You turn meeting transcripts into crisp product work.
    Return JSON only.
    Prefer tasks that are directly actionable.
    Return tasks only. Do not return decisions or follow-up notes.
    Use feature for new product or engineering deliverables.
    Use bug_fix for defects, regressions, or broken behavior that should be fixed.
    Use miscellaneous for non-feature, non-bug action items like emails, calls, coordination, admin work, or manual follow-through.
    Group supporting details into one task when they describe the same deliverable.
    Do not split one feature into multiple tasks when the transcript is describing one deliverable.
    Use evidenceIndices as 1-based transcript line references.
    If no action is clear, return an empty tasks array and explain why in noTasksReason.
    """

    private static func userPrompt(for session: TranscriptSession) -> String {
        """
        Analyze this transcript.

        Session status: \(session.status.rawValue)
        Duration seconds: \(Int(session.duration.rounded()))
        Transcript:
        \(formattedTranscript(session))
        """
    }

    private static let schema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["summary", "tasks", "noTasksReason", "warnings"],
        "properties": [
            "summary": ["type": "string"],
            "tasks": [
                "type": "array",
                "items": taskItemSchema
            ],
            "noTasksReason": ["type": "string"],
            "warnings": [
                "type": "array",
                "items": ["type": "string"]
            ]
        ]
    ]

    private static let taskItemSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["title", "details", "type", "assigneeHint", "evidenceIndices", "evidenceExcerpt"],
        "properties": [
            "title": ["type": "string"],
            "details": ["type": "string"],
            "type": [
                "type": "string",
                "enum": ["feature", "bug_fix", "miscellaneous"]
            ],
            "assigneeHint": ["type": "string"],
            "evidenceIndices": [
                "type": "array",
                "items": ["type": "integer"]
            ],
            "evidenceExcerpt": ["type": "string"]
        ]
    ]
}

struct OpenAITaskContextCompiler: TaskContextCompiling {
    private let client: OpenAIResponsesClient

    init(client: OpenAIResponsesClient = OpenAIResponsesClient()) {
        self.client = client
    }

    func prepareTaskContext(session: TranscriptSession, task: CompiledTask) async throws -> TaskContextPanelContent {
        let output: TaskContextOutput = try await client.generateStructuredOutput(
            systemPrompt: Self.systemPrompt,
            userPrompt: Self.userPrompt(for: task, session: session),
            schemaName: "task_context_result",
            schema: Self.schema
        )

        return TaskContextPanelContent(
            task: task,
            goal: output.goal.heedCollapsedWhitespace,
            whyItMatters: output.whyItMatters.heedCollapsedWhitespace,
            implementationNotes: output.implementationNotes.map(\.heedCollapsedWhitespace).filter { !$0.isEmpty },
            acceptanceCriteria: output.acceptanceCriteria.map(\.heedCollapsedWhitespace).filter { !$0.isEmpty },
            risks: output.risks.map(\.heedCollapsedWhitespace).filter { !$0.isEmpty },
            suggestedSkills: output.suggestedSkills.map(\.heedCollapsedWhitespace).filter { !$0.isEmpty },
            evidence: output.evidence.enumerated().map { index, item in
                let evidenceSegments = resolveEvidence(item.evidenceIndices, session: session)

                return TaskContextEvidence(
                    id: "evidence-\(index + 1)",
                    label: item.label.heedCollapsedWhitespace,
                    excerpt: resolvedExcerpt(
                        preferred: item.excerpt,
                        fallbackSegments: evidenceSegments.map(\.text),
                        fallbackText: task.evidenceExcerpt
                    ),
                    segmentIDs: evidenceSegments.map(\.id)
                )
            }
        )
    }

    private func resolveEvidence(_ indices: [Int], session: TranscriptSession) -> [TranscriptSegment] {
        indices.compactMap { index in
            let offset = index - 1
            guard session.segments.indices.contains(offset) else {
                return nil
            }

            return session.segments[offset]
        }
    }

    private func resolvedExcerpt(preferred: String, fallbackSegments: [String], fallbackText: String) -> String {
        preferred.heedNilIfEmpty
            ?? fallbackSegments.first(where: { !$0.heedCollapsedWhitespace.isEmpty })?.heedCollapsedWhitespace
            ?? fallbackText.heedCollapsedWhitespace
    }

    private static let systemPrompt = """
    You prepare focused implementation context for one task from a meeting transcript.
    Return JSON only.
    Stay grounded in the transcript.
    Use evidenceIndices as 1-based transcript line references.
    """

    private static func userPrompt(for task: CompiledTask, session: TranscriptSession) -> String {
        """
        Expand this task into agent-ready context.

        Selected task title: \(task.title)
        Selected task details: \(task.details)
        Selected task type: \(task.type.rawValue)
        Selected task assignee hint: \(task.assigneeHint ?? "")
        Current evidence excerpt: \(task.evidenceExcerpt)

        Transcript:
        \(OpenAITaskAnalysisCompiler.formattedTranscript(session))
        """
    }

    private static let schema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": [
            "goal",
            "whyItMatters",
            "implementationNotes",
            "acceptanceCriteria",
            "risks",
            "suggestedSkills",
            "evidence"
        ],
        "properties": [
            "goal": ["type": "string"],
            "whyItMatters": ["type": "string"],
            "implementationNotes": [
                "type": "array",
                "items": ["type": "string"]
            ],
            "acceptanceCriteria": [
                "type": "array",
                "items": ["type": "string"]
            ],
            "risks": [
                "type": "array",
                "items": ["type": "string"]
            ],
            "suggestedSkills": [
                "type": "array",
                "items": ["type": "string"]
            ],
            "evidence": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["label", "excerpt", "evidenceIndices"],
                    "properties": [
                        "label": ["type": "string"],
                        "excerpt": ["type": "string"],
                        "evidenceIndices": [
                            "type": "array",
                            "items": ["type": "integer"]
                        ]
                    ]
                ]
            ]
        ]
    ]
}

struct TaskContextFixtureCompiler: TaskContextCompiling {
    func prepareTaskContext(session: TranscriptSession, task: CompiledTask) async throws -> TaskContextPanelContent {
        let evidenceSegment = session.segments.first { task.evidenceSegmentIDs.contains($0.id) } ?? session.segments.first

        return TaskContextPanelContent(
            task: task,
            goal: "Turn this transcript task into a concrete implementation plan.",
            whyItMatters: "The user wants to review task context before the real handoff happens.",
            implementationNotes: [
                "Keep the transcript visible while the task context panel is open.",
                "Use the selected task as the anchor for any deeper follow-up."
            ],
            acceptanceCriteria: [
                "The side panel opens for one task at a time.",
                "The final Spawn agent action stays inside the panel."
            ],
            risks: [
                "If the task is vague, the agent context can overfit to weak transcript evidence."
            ],
            suggestedSkills: [
                "SwiftUI",
                "Structured output",
                "Prompt design"
            ],
            evidence: [
                TaskContextEvidence(
                    id: "evidence-1",
                    label: "Transcript evidence",
                    excerpt: evidenceSegment?.text.heedCollapsedWhitespace ?? task.evidenceExcerpt,
                    segmentIDs: evidenceSegment.map { [$0.id] } ?? []
                )
            ]
        )
    }
}

private struct TaskAnalysisOutput: Decodable {
    let summary: String
    let tasks: [TaskItem]
    let noTasksReason: String
    let warnings: [String]

    struct TaskItem: Decodable {
        let title: String
        let details: String
        let type: TaskKind
        let assigneeHint: String
        let evidenceIndices: [Int]
        let evidenceExcerpt: String
    }

    enum TaskKind: String, Decodable {
        case feature
        case bugFix = "bug_fix"
        case miscellaneous

        var compiledType: TaskType {
            switch self {
            case .feature:
                return .feature
            case .bugFix:
                return .bugFix
            case .miscellaneous:
                return .miscellaneous
            }
        }
    }
}

private struct TaskContextOutput: Decodable {
    let goal: String
    let whyItMatters: String
    let implementationNotes: [String]
    let acceptanceCriteria: [String]
    let risks: [String]
    let suggestedSkills: [String]
    let evidence: [EvidenceItem]

    struct EvidenceItem: Decodable {
        let label: String
        let excerpt: String
        let evidenceIndices: [Int]
    }
}
