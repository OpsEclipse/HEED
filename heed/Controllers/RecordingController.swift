import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class RecordingController: ObservableObject {
    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var permissions = PermissionSnapshot.unknown
    @Published private(set) var sessions: [TranscriptSession] = []
    @Published private(set) var activeSession: TranscriptSession?
    @Published private(set) var liveSegments: [TranscriptSegment] = []
    @Published private(set) var selectedSessionID: UUID?
    @Published private(set) var errorMessage: String?
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published var autoScrollEnabled = true

    var selectedSession: TranscriptSession? {
        if let activeSession, selectedSessionID == activeSession.id {
            return activeSession
        }

        return sessions.first(where: { $0.id == selectedSessionID })
    }

    var canExportSelectedSession: Bool {
        guard let selectedSession else {
            return false
        }

        guard let activeSession else {
            return true
        }

        if selectedSession.id != activeSession.id {
            return true
        }

        return state != .recording && state != .requestingPermissions && state != .stopping
    }

    var canRecord: Bool {
        state != .requestingPermissions && state != .stopping
    }

    var isDemoModeEnabled: Bool {
        demoMode
    }

    var primaryButtonTitle: String {
        state == .recording ? "Stop" : "Record"
    }

    private let permissionsManager = PermissionsManager()
    private let sessionStore: SessionStore
    private let demoMode: Bool
    private let modelName = "ggml-base.en"
    private let appVersion: String

    private var timelineStore = TranscriptTimelineStore()
    private var micCaptureManager: MicCaptureManager?
    private var systemAudioCaptureManager: SystemAudioCaptureManager?
    private var micPipeline: SourcePipeline?
    private var systemPipeline: SourcePipeline?
    private var timerTask: Task<Void, Never>?
    private var demoTask: Task<Void, Never>?
    private var startupWatchdogTask: Task<Void, Never>?
    private var activeSources = Set<AudioSource>()
    private var hasReceivedAudioFrames = false
    private var hasDetectedSpeechLikeAudio = false

    init(demoMode: Bool = false, sessionStore: SessionStore = SessionStore()) {
        self.demoMode = demoMode
        self.sessionStore = sessionStore
        self.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        self.permissions = demoMode ? PermissionSnapshot(microphone: .granted, screenCapture: .granted) : permissionsManager.refresh()
        self.state = demoMode ? .ready : .idle

        Task {
            await loadSessions()
        }
    }

    func loadSessions() async {
        do {
            let storedSessions = try await sessionStore.loadSessions()
            sessions = storedSessions
            if selectedSessionID == nil {
                selectedSessionID = storedSessions.first?.id
            }
            if state == .idle {
                state = permissions.canRecord ? .ready : .idle
            }
        } catch {
            state = .error(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    func selectSession(_ sessionID: UUID?) {
        if let activeSession, sessionID != activeSession.id {
            return
        }

        selectedSessionID = sessionID
    }

    func refreshPermissions() {
        let previousGuidance = permissions.guidanceText
        permissions = demoMode ? PermissionSnapshot(microphone: .granted, screenCapture: .granted) : permissionsManager.refresh()
        guard state != .recording && state != .stopping else {
            return
        }

        if permissions.canRecord {
            if errorMessage == previousGuidance || errorMessage == permissions.guidanceText {
                errorMessage = nil
            }
            state = .ready
        } else {
            state = .idle
        }
    }

    func handlePrimaryAction() {
        guard canRecord else {
            return
        }

        if state == .recording {
            Task {
                await stopRecording()
            }
        } else {
            Task {
                await startRecording()
            }
        }
    }

    func copySelectedSession() {
        guard let session = selectedSession else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(TranscriptExport.plainText(from: session), forType: .string)
    }

    func exportSelectedSession(as format: TranscriptExportFormat) {
        guard let session = selectedSession else {
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = format == .text ? [.plainText] : [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "heed-\(session.id.uuidString).\(format.fileExtension)"

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return
        }

        let content = switch format {
        case .text:
            TranscriptExport.plainText(from: session)
        case .markdown:
            TranscriptExport.markdown(from: session)
        }

        do {
            try content.write(to: destinationURL, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startRecording() async {
        errorMessage = nil
        state = .requestingPermissions

        permissions = demoMode ? PermissionSnapshot(microphone: .granted, screenCapture: .granted) : await permissionsManager.requestIfNeeded()
        guard permissions.canRecord else {
            state = .error(permissions.guidanceText)
            errorMessage = permissions.guidanceText
            return
        }

        let startedAt = Date()
        let session = TranscriptSession(
            startedAt: startedAt,
            status: .recording,
            modelName: modelName,
            appVersion: appVersion
        )

        activeSession = session
        liveSegments = []
        timelineStore.reset()
        selectedSessionID = session.id
        elapsedTime = 0
        activeSources = []
        hasReceivedAudioFrames = false
        hasDetectedSpeechLikeAudio = false

        do {
            try await sessionStore.save(session: session)
        } catch {
            state = .error(error.localizedDescription)
            errorMessage = error.localizedDescription
            activeSession = nil
            return
        }

        if demoMode {
            state = .recording
            startDemoRecording()
            startTimer(from: startedAt)
            startStartupWatchdog()
            return
        }

        let helperURL = Bundle.main.bundleURL
            .appending(path: "Contents", directoryHint: .isDirectory)
            .appending(path: "Helpers", directoryHint: .isDirectory)
            .appending(path: "WhisperChunkCLI")
        let modelURL = Bundle.main.resourceURL!
            .appending(path: "Models", directoryHint: .isDirectory)
            .appending(path: "ggml-base.en.bin")

        let micPipeline = SourcePipeline(
            source: .mic,
            helperURL: helperURL,
            modelURL: modelURL
        ) { [weak self] segments in
            await self?.consume(segments: segments)
        }
        let systemPipeline = SourcePipeline(
            source: .system,
            helperURL: helperURL,
            modelURL: modelURL
        ) { [weak self] segments in
            await self?.consume(segments: segments)
        }

        var startupMessages: [String] = []

        do {
            try await startMicSource(with: micPipeline)
        } catch {
            startupMessages.append("Microphone capture could not start: \(error.localizedDescription)")
        }

        do {
            try await startSystemSource(with: systemPipeline)
        } catch {
            startupMessages.append("System audio capture could not start: \(error.localizedDescription)")
        }

        guard !activeSources.isEmpty else {
            let message = startupMessages.joined(separator: " ")
            await failRecording(with: message.isEmpty ? "Heed could not start any audio capture source." : message)
            return
        }

        if !startupMessages.isEmpty {
            errorMessage = startupMessages.joined(separator: " ")
        }

        self.state = .recording
        startTimer(from: startedAt)
        startStartupWatchdog()
    }

    private func stopRecording() async {
        guard state == .recording, let activeSession else {
            return
        }

        state = .stopping
        startupWatchdogTask?.cancel()
        timerTask?.cancel()
        demoTask?.cancel()
        let stopRequestedAt = Date()
        elapsedTime = stopRequestedAt.timeIntervalSince(activeSession.startedAt)
        micCaptureManager?.stop()
        await systemAudioCaptureManager?.stop()

        do {
            try await micPipeline?.finish(responseTimeout: .seconds(8))
            try await systemPipeline?.finish(responseTimeout: .seconds(8))
        } catch {
            await failRecording(with: error.localizedDescription)
            return
        }

        let finishedSession = finalizedSession(from: activeSession, status: .completed, endedAt: stopRequestedAt)

        self.activeSession = finishedSession
        upsertStoredSession(finishedSession)

        do {
            try await sessionStore.save(session: finishedSession)
            self.activeSession = nil
            self.liveSegments = []
            self.activeSources = []
            self.micPipeline = nil
            self.systemPipeline = nil
            self.micCaptureManager = nil
            self.systemAudioCaptureManager = nil
            self.state = .ready
            self.selectedSessionID = finishedSession.id
        } catch {
            await failRecording(with: error.localizedDescription)
        }
    }

    private func startDemoRecording() {
        demoTask = Task { [weak self] in
            guard let self else { return }

            let segments = [
                TranscriptSegment(source: .mic, startedAt: 1, endedAt: 2.4, text: "Can you hear me clearly on this side?"),
                TranscriptSegment(source: .system, startedAt: 2, endedAt: 3.5, text: "Yes, the remote call audio is coming through."),
                TranscriptSegment(source: .mic, startedAt: 4.2, endedAt: 5.8, text: "Perfect. Heed is showing separate live labels."),
            ]

            for segment in segments {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                await consume(segments: [segment])
            }
        }
    }

    private func startTimer(from startDate: Date) {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, let activeSession else { continue }
                self.elapsedTime = Date().timeIntervalSince(activeSession.startedAt)
            }
        }
    }

    private func consume(segments: [TranscriptSegment]) async {
        guard !segments.isEmpty, var activeSession else {
            return
        }

        startupWatchdogTask?.cancel()
        timelineStore.append(segments)
        activeSession.segments = timelineStore.orderedSegments
        activeSession.duration = elapsedTime
        self.activeSession = activeSession
        self.liveSegments = activeSession.segments
        upsertStoredSession(activeSession)

        do {
            try await sessionStore.save(session: activeSession)
        } catch {
            await failRecording(with: error.localizedDescription)
        }
    }

    private func failRecording(with message: String) async {
        startupWatchdogTask?.cancel()
        let interruptedSession = activeSession.map {
            finalizedSession(from: $0, status: .recovered, endedAt: Date())
        }

        timerTask?.cancel()
        demoTask?.cancel()
        micCaptureManager?.stop()
        await systemAudioCaptureManager?.stop()
        await micPipeline?.stop()
        await systemPipeline?.stop()
        micCaptureManager = nil
        systemAudioCaptureManager = nil
        micPipeline = nil
        systemPipeline = nil
        activeSources = []
        activeSession = nil
        liveSegments = []

        if let interruptedSession, !interruptedSession.segments.isEmpty {
            upsertStoredSession(interruptedSession)
            selectedSessionID = interruptedSession.id
            do {
                try await sessionStore.save(session: interruptedSession)
            } catch {
                NSLog("Failed to save interrupted session: %@", error.localizedDescription)
            }
            elapsedTime = interruptedSession.duration
        } else if let interruptedSession {
            sessions.removeAll(where: { $0.id == interruptedSession.id })
            selectedSessionID = sessions.first?.id
            elapsedTime = 0
            do {
                try await sessionStore.deleteSession(id: interruptedSession.id)
            } catch {
                NSLog("Failed to delete empty interrupted session: %@", error.localizedDescription)
            }
        } else {
            selectedSessionID = sessions.first?.id
            elapsedTime = 0
        }

        errorMessage = message
        state = .error(message)
    }

    private func startMicSource(with pipeline: SourcePipeline) async throws {
        try await pipeline.start()

        do {
            let micCaptureManager = MicCaptureManager()
            try micCaptureManager.start { [weak self] frames in
                guard let self else { return }
                Task {
                    await self.noteIncomingFrames(frames, from: .mic)
                    do {
                        try await pipeline.ingest(frames: frames)
                    } catch {
                        await self.handleSourceFailure(.mic, message: error.localizedDescription)
                    }
                }
            }

            self.micPipeline = pipeline
            self.micCaptureManager = micCaptureManager
            self.activeSources.insert(.mic)
        } catch {
            await pipeline.stop()
            throw error
        }
    }

    private func startSystemSource(with pipeline: SourcePipeline) async throws {
        try await pipeline.start()

        do {
            let systemAudioCaptureManager = SystemAudioCaptureManager()
            try await systemAudioCaptureManager.start(
                onFrames: { [weak self] frames in
                    guard let self else { return }
                    Task {
                        await self.noteIncomingFrames(frames, from: .system)
                        do {
                            try await pipeline.ingest(frames: frames)
                        } catch {
                            await self.handleSourceFailure(.system, message: error.localizedDescription)
                        }
                    }
                },
                onFailure: { [weak self] message in
                    guard let self else { return }
                    Task {
                        await self.handleSourceFailure(.system, message: message)
                    }
                }
            )

            self.systemPipeline = pipeline
            self.systemAudioCaptureManager = systemAudioCaptureManager
            self.activeSources.insert(.system)
        } catch {
            await pipeline.stop()
            throw error
        }
    }

    private func noteIncomingFrames(_ frames: [Float], from source: AudioSource) {
        guard activeSources.contains(source) else {
            return
        }

        hasReceivedAudioFrames = true
        if AudioEnergyGate.containsSpeechLikeEnergy(frames, source: source) {
            hasDetectedSpeechLikeAudio = true
        }
    }

    private func handleSourceFailure(_ source: AudioSource, message: String) async {
        guard activeSources.contains(source) else {
            return
        }

        await stopSource(source)
        activeSources.remove(source)

        guard !activeSources.isEmpty else {
            await failRecording(with: message)
            return
        }

        let survivingSources = activeSources
            .map(\.label)
            .sorted()
            .joined(separator: " and ")
        errorMessage = "\(source.label) failed. Heed is still recording \(survivingSources). Details: \(message)"
    }

    private func stopSource(_ source: AudioSource) async {
        switch source {
        case .mic:
            micCaptureManager?.stop()
            micCaptureManager = nil
            await micPipeline?.stop()
            micPipeline = nil
        case .system:
            await systemAudioCaptureManager?.stop()
            systemAudioCaptureManager = nil
            await systemPipeline?.stop()
            systemPipeline = nil
        }
    }

    private func startStartupWatchdog() {
        startupWatchdogTask?.cancel()
        startupWatchdogTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard let self else { return }
            await self.evaluateStartupHealth()
        }
    }

    private func evaluateStartupHealth() async {
        guard state == .recording, activeSession?.segments.isEmpty != false else {
            return
        }

        if !hasReceivedAudioFrames {
            await failRecording(with: "Heed started the session but never received audio. Check your microphone, screen capture permission, and current audio devices, then try again.")
            return
        }

        guard hasDetectedSpeechLikeAudio else {
            return
        }

        await failRecording(with: "Heed heard audio but did not produce text. Try recording again. If this keeps happening, restart the app so the local model can reload cleanly.")
    }

    private func finalizedSession(
        from session: TranscriptSession,
        status: TranscriptSessionStatus,
        endedAt: Date
    ) -> TranscriptSession {
        var finalized = session
        finalized.endedAt = endedAt
        finalized.duration = max(elapsedTime, endedAt.timeIntervalSince(session.startedAt))
        finalized.status = status
        return finalized
    }

    private func upsertStoredSession(_ session: TranscriptSession) {
        sessions.removeAll(where: { $0.id == session.id })
        sessions.insert(session, at: 0)
    }
}

private actor SourcePipeline {
    private let worker: WhisperWorker
    private let sink: @Sendable ([TranscriptSegment]) async -> Void
    private var chunker: AudioChunker

    init(
        source: AudioSource,
        helperURL: URL,
        modelURL: URL,
        sink: @escaping @Sendable ([TranscriptSegment]) async -> Void
    ) {
        self.worker = WhisperWorker(source: source, helperURL: helperURL, modelURL: modelURL)
        self.chunker = AudioChunker(source: source)
        self.sink = sink
    }

    func start() async throws {
        try await worker.start()
    }

    func ingest(frames: [Float]) async throws {
        let chunks = chunker.append(frames)
        try await process(chunks)
    }

    func finish(responseTimeout: Duration = .seconds(20)) async throws {
        let chunks = chunker.flush()
        try await process(chunks, responseTimeout: responseTimeout)
        await worker.stop()
    }

    func stop() async {
        await worker.stop()
    }

    private func process(
        _ chunks: [AudioChunk],
        responseTimeout: Duration = .seconds(20)
    ) async throws {
        for chunk in chunks {
            let segments = try await worker.transcribe(
                chunk: chunk,
                responseTimeout: responseTimeout
            )
            guard !segments.isEmpty else {
                continue
            }
            await sink(segments)
        }
    }
}
