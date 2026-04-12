import Combine
import Foundation

protocol TaskAnalysisCompiling: Sendable {
    func compile(session: TranscriptSession) async throws -> TaskAnalysisResult
}

@MainActor
final class TaskAnalysisController: ObservableObject {
    struct SourceJumpRequest: Equatable {
        let segmentID: UUID
        let nonce: Int
    }

    struct SectionModel: Equatable {
        let title: String
        let helperText: String?
        let statusText: String?
        let errorText: String?
        let isExpanded: Bool
        let isCompiling: Bool
        let result: TaskAnalysisResult?
        let selectedTaskIDs: Set<String>
        let isDecisionsExpanded: Bool
        let isFollowUpsExpanded: Bool
        let retryTitle: String?
    }

    struct ViewState: Equatable {
        enum Phase: Equatable {
            case notCompiled
            case compiling
            case compiled
            case failed(String)
        }

        let sessionID: UUID
        let phase: Phase
        let isExpanded: Bool
        let isRefreshing: Bool
        let result: TaskAnalysisResult?
        let selectedTaskIDs: Set<String>
        let isDecisionsExpanded: Bool
        let isFollowUpsExpanded: Bool
    }

    private struct SessionState {
        var phase: ViewState.Phase = .notCompiled
        var isVisible = false
        var isExpanded = true
        var result: TaskAnalysisResult?
        var selectedTaskIDs = Set<String>()
        var isDecisionsExpanded = false
        var isFollowUpsExpanded = false
        var compileTask: Task<Void, Never>?
    }

    @Published private var sessionStates: [UUID: SessionState] = [:]
    @Published private var currentSession: TranscriptSession?
    @Published private(set) var sourceJumpRequest: SourceJumpRequest?
    @Published private(set) var highlightedSegmentID: UUID?
    @Published private(set) var sectionFocusNonce = 0
    @Published private(set) var lastSpawnedTaskID: String?

    private let compiler: any TaskAnalysisCompiling
    private var selectedSessionID: UUID?
    private var jumpNonce = 0
    private var highlightResetTask: Task<Void, Never>?

    init(compiler: any TaskAnalysisCompiling = TaskAnalysisFixtureCompiler()) {
        self.compiler = compiler
    }

    var canShowCompileAction: Bool {
        canShowPrimaryAction(for: currentSession)
    }

    var compileActionTitle: String? {
        guard currentSession != nil else {
            return nil
        }

        return primaryActionTitle(for: currentSession)
    }

    var isCompileActionEnabled: Bool {
        isPrimaryActionEnabled(for: currentSession)
    }

    var sectionModel: SectionModel? {
        guard let viewState = viewState(for: currentSession) else {
            return nil
        }

        let helperText = viewState.result != nil ? "Review before creating" : nil
        let statusText: String?
        let errorText: String?
        let retryTitle: String?

        switch viewState.phase {
        case .notCompiled:
            statusText = "Compile this meeting into action items."
            errorText = nil
            retryTitle = nil
        case .compiling:
            statusText = viewState.isRefreshing ? "Refreshing task draft" : "Preparing task draft"
            errorText = nil
            retryTitle = nil
        case .compiled:
            statusText = viewState.result?.summary
            errorText = nil
            retryTitle = nil
        case let .failed(message):
            statusText = viewState.result?.summary
            errorText = message
            retryTitle = "Try again"
        }

        return SectionModel(
            title: "Suggested tasks",
            helperText: helperText,
            statusText: statusText,
            errorText: errorText,
            isExpanded: viewState.isExpanded,
            isCompiling: isCompiling(viewState.phase),
            result: viewState.result,
            selectedTaskIDs: viewState.selectedTaskIDs,
            isDecisionsExpanded: viewState.isDecisionsExpanded,
            isFollowUpsExpanded: viewState.isFollowUpsExpanded,
            retryTitle: retryTitle
        )
    }

    func setSelectedSession(_ session: TranscriptSession?) {
        let previousSessionID = selectedSessionID
        selectedSessionID = session?.id
        if previousSessionID != selectedSessionID {
            lastSpawnedTaskID = nil
        }

        guard previousSessionID != selectedSessionID else {
            return
        }

        if let previousSessionID {
            cancelCompilation(for: previousSessionID, collapseIfEmpty: false)
        }
    }

    func updateDisplayedSession(_ session: TranscriptSession?) {
        currentSession = session
        setSelectedSession(session)
    }

    func canShowPrimaryAction(for session: TranscriptSession?) -> Bool {
        guard let session else {
            return false
        }

        return canCompile(session)
    }

    func primaryActionTitle(for session: TranscriptSession?) -> String {
        guard let session else {
            return "Compile tasks"
        }

        let phase = state(for: session.id).phase
        switch phase {
        case .compiling:
            return "Compiling..."
        case .failed:
            return "Try again"
        case .compiled:
            return "Recompile"
        case .notCompiled:
            return "Compile tasks"
        }
    }

    func isPrimaryActionEnabled(for session: TranscriptSession?) -> Bool {
        guard let session else {
            return false
        }

        return canCompile(session) && !isCompiling(state(for: session.id).phase)
    }

    func triggerPrimaryAction(for session: TranscriptSession) {
        guard canCompile(session) else {
            return
        }

        var currentState = state(for: session.id)
        currentState.isVisible = true
        currentState.isExpanded = true
        sessionStates[session.id] = currentState
        sectionFocusNonce += 1

        startCompilation(for: session)
    }

    func handleCompileAction() {
        guard let currentSession else {
            return
        }

        triggerPrimaryAction(for: currentSession)
    }

    func viewState(for session: TranscriptSession?) -> ViewState? {
        guard let session else {
            return nil
        }

        let currentState = state(for: session.id)
        let shouldShow = currentState.isVisible || currentState.result != nil || currentState.phase != .notCompiled
        guard shouldShow else {
            return nil
        }

        return ViewState(
            sessionID: session.id,
            phase: currentState.phase,
            isExpanded: currentState.isExpanded,
            isRefreshing: currentState.result != nil && isCompiling(currentState.phase),
            result: currentState.result,
            selectedTaskIDs: currentState.selectedTaskIDs,
            isDecisionsExpanded: currentState.isDecisionsExpanded,
            isFollowUpsExpanded: currentState.isFollowUpsExpanded
        )
    }

    func togglePanel(for session: TranscriptSession) {
        var currentState = state(for: session.id)
        currentState.isExpanded.toggle()

        if !currentState.isExpanded, isCompiling(currentState.phase) {
            sessionStates[session.id] = currentState
            cancelCompilation(for: session.id, collapseIfEmpty: currentState.result == nil)
            return
        }

        currentState.isVisible = currentState.isExpanded || currentState.result != nil
        sessionStates[session.id] = currentState
    }

    func toggleSectionExpansion() {
        guard let currentSession else {
            return
        }

        togglePanel(for: currentSession)
    }

    func toggleDecisions(for session: TranscriptSession) {
        var currentState = state(for: session.id)
        currentState.isDecisionsExpanded.toggle()
        sessionStates[session.id] = currentState
    }

    func toggleDecisionsExpansion() {
        guard let currentSession else {
            return
        }

        toggleDecisions(for: currentSession)
    }

    func toggleFollowUps(for session: TranscriptSession) {
        var currentState = state(for: session.id)
        currentState.isFollowUpsExpanded.toggle()
        sessionStates[session.id] = currentState
    }

    func toggleFollowUpsExpansion() {
        guard let currentSession else {
            return
        }

        toggleFollowUps(for: currentSession)
    }

    func toggleTaskSelection(taskID: String, for session: TranscriptSession) {
        var currentState = state(for: session.id)

        if currentState.selectedTaskIDs.contains(taskID) {
            currentState.selectedTaskIDs.remove(taskID)
        } else {
            currentState.selectedTaskIDs.insert(taskID)
        }

        sessionStates[session.id] = currentState
    }

    func toggleTaskSelection(_ taskID: String) {
        guard let currentSession else {
            return
        }

        toggleTaskSelection(taskID: taskID, for: currentSession)
    }

    func showSource(for segmentID: UUID) {
        jumpNonce += 1
        sourceJumpRequest = SourceJumpRequest(segmentID: segmentID, nonce: jumpNonce)
        highlightedSegmentID = segmentID

        highlightResetTask?.cancel()
        highlightResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                self?.highlightedSegmentID = nil
            }
        }
    }

    func showSource(for segmentIDs: [UUID]) {
        guard let segmentID = segmentIDs.first else {
            return
        }

        showSource(for: segmentID)
    }

    func requestSpawnAgent(for taskID: String) {
        lastSpawnedTaskID = taskID
    }

    private func canCompile(_ session: TranscriptSession) -> Bool {
        (session.status == .completed || session.status == .recovered)
            && session.segments.contains(where: { !$0.text.heedCollapsedWhitespace.isEmpty })
    }

    private func startCompilation(for session: TranscriptSession) {
        var currentState = state(for: session.id)
        currentState.compileTask?.cancel()
        currentState.compileTask = nil
        currentState.phase = .compiling
        currentState.isVisible = true
        currentState.isExpanded = true
        sessionStates[session.id] = currentState
        lastSpawnedTaskID = nil

        let compiler = compiler
        currentState.compileTask = Task { [weak self] in
            do {
                let result = try await compiler.compile(session: session)
                try Task.checkCancellation()

                await MainActor.run {
                    self?.finishCompilation(result, for: session.id)
                }
            } catch is CancellationError {
                await MainActor.run {
                    self?.cancelCompilation(for: session.id, collapseIfEmpty: currentState.result == nil)
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    self?.failCompilation(message: error.localizedDescription, for: session.id)
                }
            }
        }

        sessionStates[session.id] = currentState
    }

    private func finishCompilation(_ result: TaskAnalysisResult, for sessionID: UUID) {
        var currentState = state(for: sessionID)
        currentState.compileTask = nil
        currentState.phase = .compiled
        currentState.result = result
        currentState.isVisible = true
        currentState.isExpanded = true
        currentState.isDecisionsExpanded = false
        currentState.isFollowUpsExpanded = false
        currentState.selectedTaskIDs = currentState.selectedTaskIDs.intersection(Set(result.tasks.map(\.id)))
        sessionStates[sessionID] = currentState
    }

    private func failCompilation(message: String, for sessionID: UUID) {
        var currentState = state(for: sessionID)
        currentState.compileTask = nil
        currentState.phase = .failed(message)
        currentState.isVisible = true
        currentState.isExpanded = true
        sessionStates[sessionID] = currentState
    }

    private func cancelCompilation(for sessionID: UUID, collapseIfEmpty: Bool) {
        var currentState = state(for: sessionID)
        currentState.compileTask?.cancel()
        currentState.compileTask = nil

        if currentState.result == nil {
            currentState.phase = .notCompiled
            if collapseIfEmpty {
                currentState.isExpanded = false
                currentState.isVisible = false
            }
        } else {
            currentState.phase = .compiled
        }

        sessionStates[sessionID] = currentState
    }

    private func state(for sessionID: UUID) -> SessionState {
        sessionStates[sessionID] ?? SessionState()
    }

    private func isCompiling(_ phase: ViewState.Phase) -> Bool {
        if case .compiling = phase {
            return true
        }

        return false
    }
}
