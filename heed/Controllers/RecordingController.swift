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

    var canRecord: Bool {
        state != .recording && state != .stopping
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
        selectedSessionID = sessionID
    }

    func refreshPermissions() {
        permissions = demoMode ? PermissionSnapshot(microphone: .granted, screenCapture: .granted) : permissionsManager.refresh()
        if state == .idle && permissions.canRecord {
            state = .ready
        }
    }

    func handlePrimaryAction() {
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
            state = .error("Export failed")
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
        state = .recording

        do {
            try await sessionStore.save(session: session)
        } catch {
            state = .error(error.localizedDescription)
            errorMessage = error.localizedDescription
            activeSession = nil
            return
        }

        if demoMode {
            startDemoRecording()
            startTimer(from: startedAt)
            return
        }

        do {
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

            try await micPipeline.start()
            try await systemPipeline.start()

            let micCaptureManager = MicCaptureManager()
            try micCaptureManager.start { [weak self] frames in
                guard let self else { return }
                Task {
                    do {
                        try await micPipeline.ingest(frames: frames)
                    } catch {
                        await self.failRecording(with: error.localizedDescription)
                    }
                }
            }

            let systemAudioCaptureManager = SystemAudioCaptureManager()
            try await systemAudioCaptureManager.start { [weak self] frames in
                guard let self else { return }
                Task {
                    do {
                        try await systemPipeline.ingest(frames: frames)
                    } catch {
                        await self.failRecording(with: error.localizedDescription)
                    }
                }
            }

            self.micPipeline = micPipeline
            self.systemPipeline = systemPipeline
            self.micCaptureManager = micCaptureManager
            self.systemAudioCaptureManager = systemAudioCaptureManager
            startTimer(from: startedAt)
        } catch {
            await failRecording(with: error.localizedDescription)
        }
    }

    private func stopRecording() async {
        guard state == .recording, let activeSession else {
            return
        }

        state = .stopping
        demoTask?.cancel()
        micCaptureManager?.stop()
        await systemAudioCaptureManager?.stop()

        do {
            try await micPipeline?.finish()
            try await systemPipeline?.finish()
        } catch {
            await failRecording(with: error.localizedDescription)
            return
        }

        timerTask?.cancel()
        let finishedAt = Date()
        var finishedSession = activeSession
        finishedSession.endedAt = finishedAt
        finishedSession.duration = finishedAt.timeIntervalSince(finishedSession.startedAt)
        finishedSession.status = .completed

        self.activeSession = finishedSession
        upsertStoredSession(finishedSession)

        do {
            try await sessionStore.save(session: finishedSession)
            self.activeSession = nil
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
        errorMessage = message
        state = .error(message)
    }

    private func upsertStoredSession(_ session: TranscriptSession) {
        sessions.removeAll(where: { $0.id == session.id })
        sessions.insert(session, at: 0)
    }
}

private actor SourcePipeline {
    private let worker: WhisperWorker
    private let source: AudioSource
    private let sink: @Sendable ([TranscriptSegment]) async -> Void
    private var chunker: AudioChunker

    init(
        source: AudioSource,
        helperURL: URL,
        modelURL: URL,
        sink: @escaping @Sendable ([TranscriptSegment]) async -> Void
    ) {
        self.source = source
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

    func finish() async throws {
        let chunks = chunker.flush()
        try await process(chunks)
        await worker.stop()
    }

    func stop() async {
        await worker.stop()
    }

    private func process(_ chunks: [AudioChunk]) async throws {
        for chunk in chunks {
            let segments = try await worker.transcribe(chunk: chunk)
            guard !segments.isEmpty else {
                continue
            }
            await sink(segments)
        }
    }
}
