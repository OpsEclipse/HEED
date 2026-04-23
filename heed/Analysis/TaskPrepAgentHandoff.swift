import AppKit
import Foundation

@MainActor
protocol TaskPrepAgentHandoffLaunching {
    func launch(prompt: String) throws
}

@MainActor
protocol AppleScriptRunning {
    func run(source: String) throws
}

@MainActor
protocol TaskPrepPasteboardAccessing {
    func readString() -> String?
    func writeString(_ value: String?)
}

struct TaskPrepAgentHandoffPromptBuilder {
    nonisolated static func buildPrompt(
        task: CompiledTask,
        transcriptSegments: [TranscriptSegment],
        draft: TaskPrepContextDraft,
        messages: [TaskPrepMessage],
        request: TaskPrepSpawnRequest
    ) -> String {
        let assigneeHint = cleanedLine(task.assigneeHint) ?? "Not specified."
        let summary = cleanedLine(draft.summary) ?? "No summary captured."
        let goal = cleanedLine(draft.goal) ?? "No goal captured."
        let taskDetails = cleanedLine(task.details) ?? "No extra task details."
        let taskEvidence = cleanedLine(task.evidenceExcerpt) ?? "No task evidence excerpt."
        let requestReason = cleanedLine(request.reason) ?? "No explicit spawn reason was recorded."

        let constraints = numberedLines(from: draft.constraints, emptyFallback: "No extra constraints.")
        let acceptance = numberedLines(from: draft.acceptanceCriteria, emptyFallback: "No explicit acceptance criteria.")
        let risks = numberedLines(from: draft.risks, emptyFallback: "No explicit risks.")
        let openQuestions = numberedLines(from: draft.openQuestions, emptyFallback: "No open questions were captured.")
        let evidence = evidenceLines(from: draft.evidence, transcriptSegments: transcriptSegments, fallback: taskEvidence)
        let conversation = conversationLines(from: messages)
        let transcript = transcriptLines(from: transcriptSegments)

        return """
        Start working on this task in the current Codex session.
        The user already approved the handoff. Begin the work end-to-end.
        Use the full context below. Treat the summary as compressed guidance and the transcript as the fuller source of truth.

        Task
        Title: \(task.title.heedCollapsedWhitespace)
        Type: \(task.type.rawValue)
        Details: \(taskDetails)
        Assignee hint: \(assigneeHint)
        Spawn reason: \(requestReason)

        Brief
        Summary: \(summary)
        Goal: \(goal)

        Constraints
        \(constraints)

        Acceptance
        \(acceptance)

        Risks
        \(risks)

        Open questions
        \(openQuestions)

        Evidence
        \(evidence)

        Prep conversation
        \(conversation)

        Full transcript
        \(transcript)
        """
    }

    private nonisolated static func cleanedLine(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            return nil
        }

        return trimmed.heedCollapsedWhitespace
    }

    private nonisolated static func numberedLines(from lines: [String], emptyFallback: String) -> String {
        let cleaned = lines
            .compactMap(cleanedLine(_:))

        guard !cleaned.isEmpty else {
            return "1. \(emptyFallback)"
        }

        return cleaned.enumerated()
            .map { index, line in
                "\(index + 1). \(line)"
            }
            .joined(separator: "\n")
    }

    private nonisolated static func evidenceLines(
        from evidence: [TaskPrepEvidence],
        transcriptSegments: [TranscriptSegment],
        fallback: String
    ) -> String {
        guard !evidence.isEmpty else {
            return "1. \(fallback)"
        }

        let sessionSegmentByID = Dictionary(uniqueKeysWithValues: transcriptSegments.map { ($0.id, $0) })

        return evidence.enumerated().map { index, item in
            let quotedExcerpt = cleanedLine(item.excerpt) ?? "No excerpt."
            let segmentContext = item.segmentIDs
                .compactMap { sessionSegmentByID[$0] }
                .map { segment in
                    let start = Int(segment.startedAt.rounded(.down))
                    let end = Int(segment.endedAt.rounded(.up))
                    return "[\(segment.source.rawValue.uppercased()) \(start)s-\(end)s] \(segment.text.heedCollapsedWhitespace)"
                }
                .joined(separator: " | ")

            if segmentContext.isEmpty {
                return "\(index + 1). \(item.label.heedCollapsedWhitespace): \(quotedExcerpt)"
            }

            return "\(index + 1). \(item.label.heedCollapsedWhitespace): \(quotedExcerpt) \(segmentContext)"
        }
        .joined(separator: "\n")
    }

    private nonisolated static func conversationLines(from messages: [TaskPrepMessage]) -> String {
        let visibleMessages = messages.filter { message in
            let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty
        }

        guard !visibleMessages.isEmpty else {
            return "1. No prep chat history."
        }

        return visibleMessages.enumerated().map { index, message in
            let role: String
            switch message.role {
            case .assistant:
                role = "Assistant"
            case .user:
                role = "User"
            case .system:
                role = "System"
            }

            let interruptionSuffix = message.isInterrupted ? " [interrupted]" : ""
            return "\(index + 1). \(role)\(interruptionSuffix): \(message.text.heedCollapsedWhitespace)"
        }
        .joined(separator: "\n")
    }

    private nonisolated static func transcriptLines(from transcriptSegments: [TranscriptSegment]) -> String {
        guard !transcriptSegments.isEmpty else {
            return "1. No transcript segments were available."
        }

        return transcriptSegments.enumerated().map { index, segment in
            let start = Int(segment.startedAt.rounded(.down))
            let end = Int(segment.endedAt.rounded(.up))
            return "\(index + 1). [\(segment.source.rawValue.uppercased()) \(start)s-\(end)s] \(segment.text.heedCollapsedWhitespace)"
        }
        .joined(separator: "\n")
    }
}

enum TaskPrepAgentHandoffError: LocalizedError, Equatable {
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case let .launchFailed(message):
            return "Could not launch Codex in Terminal. \(message)"
        }
    }
}

struct TaskPrepTerminalHandoffLauncher: TaskPrepAgentHandoffLaunching {
    private let appleScriptRunner: any AppleScriptRunning
    private let pasteboard: any TaskPrepPasteboardAccessing

    init() {
        self.init(
            appleScriptRunner: TaskPrepAppleScriptRunner(),
            pasteboard: TaskPrepSystemPasteboard()
        )
    }

    init(
        appleScriptRunner: any AppleScriptRunning,
        pasteboard: any TaskPrepPasteboardAccessing
    ) {
        self.appleScriptRunner = appleScriptRunner
        self.pasteboard = pasteboard
    }

    func launch(prompt: String) throws {
        let previousClipboard = pasteboard.readString()

        do {
            pasteboard.writeString(prompt)
            try appleScriptRunner.run(source: terminalLaunchSource)
            try appleScriptRunner.run(source: terminalPasteAndSubmitSource)
            pasteboard.writeString(previousClipboard)
        } catch {
            pasteboard.writeString(previousClipboard)
            throw error
        }
    }

    private var terminalLaunchSource: String {
        """
        tell application "Terminal"
            activate
            do script "codex"
        end tell
        """
    }

    private var terminalPasteAndSubmitSource: String {
        """
        delay 0.4
        tell application "System Events"
            tell process "Terminal"
                keystroke "v" using command down
                key code 36
            end tell
        end tell
        """
    }
}

struct TaskPrepNoopHandoffLauncher: TaskPrepAgentHandoffLaunching {
    func launch(prompt: String) throws {
        _ = prompt
    }
}

@MainActor
private struct TaskPrepAppleScriptRunner: AppleScriptRunning {
    func run(source: String) throws {
        var errorDictionary: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw TaskPrepAgentHandoffError.launchFailed("Heed could not create the Terminal automation script.")
        }

        _ = script.executeAndReturnError(&errorDictionary)
        if let errorDictionary {
            let message = (errorDictionary[NSAppleScript.errorMessage] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw TaskPrepAgentHandoffError.launchFailed(message ?? "Terminal did not accept the automation request.")
        }
    }
}

@MainActor
private final class TaskPrepSystemPasteboard: TaskPrepPasteboardAccessing {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func readString() -> String? {
        pasteboard.string(forType: .string)
    }

    func writeString(_ value: String?) {
        pasteboard.clearContents()

        guard let value else {
            return
        }

        pasteboard.setString(value, forType: .string)
    }
}
