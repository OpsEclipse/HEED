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
    @Published private(set) var sourceProcessingStates: [AudioSource: SourceProcessingState] = [:]
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

        return state != .recording && state != .requestingPermissions && state != .stopping && state != .processing
    }

    var canRecord: Bool {
        state != .requestingPermissions && state != .stopping && state != .processing
    }

    var isDemoModeEnabled: Bool {
        demoMode
    }

    var primaryButtonTitle: String {
        state == .recording ? "Stop" : "Record"
    }

    private let dependencies: RecordingControllerDependencies
    private let sessionStore: SessionStore
    private let demoMode: Bool
    private let modelName = "ggml-base.en"
    private let appVersion: String

    private var micCaptureManager: (any MicCaptureManaging)?
    private var systemAudioCaptureManager: (any SystemAudioCaptureManaging)?
    private var micWriter: SourceRecordingFileWriter?
    private var systemWriter: SourceRecordingFileWriter?
    private var sourceFileURLs: [AudioSource: URL] = [:]
    private var timerTask: Task<Void, Never>?
    private var startupWatchdogTask: Task<Void, Never>?
    private var activeSources = Set<AudioSource>()
    private var hasReceivedAudioFrames = false
    private var hasDetectedSpeechLikeAudio = false

    init(
        demoMode: Bool = false,
        sessionStore: SessionStore = SessionStore(),
        dependencies: RecordingControllerDependencies? = nil
    ) {
        let resolvedDependencies = dependencies ?? .live()
        self.demoMode = demoMode
        self.sessionStore = sessionStore
        self.dependencies = resolvedDependencies
        self.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        self.permissions = demoMode ? PermissionSnapshot(microphone: .granted, screenCapture: .granted) : resolvedDependencies.refreshPermissions()
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
        permissions = demoMode ? PermissionSnapshot(microphone: .granted, screenCapture: .granted) : dependencies.refreshPermissions()
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
        dependencies.diagnosticSink(.recordingRequested)
        errorMessage = nil
        state = .requestingPermissions

        permissions = demoMode ? PermissionSnapshot(microphone: .granted, screenCapture: .granted) : await dependencies.requestPermissionsIfNeeded()
        dependencies.diagnosticSink(
            .permissionsResolved(microphone: permissions.microphone, screenCapture: permissions.screenCapture)
        )
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
        sourceProcessingStates = [:]
        selectedSessionID = session.id
        elapsedTime = 0
        activeSources = []
        hasReceivedAudioFrames = false
        hasDetectedSpeechLikeAudio = false
        sourceFileURLs = makeSourceFileURLs(for: session.id)

        do {
            try await sessionStore.save(session: session)
        } catch {
            state = .error(error.localizedDescription)
            errorMessage = error.localizedDescription
            activeSession = nil
            return
        }

        if let micURL = sourceFileURLs[.mic] {
            micWriter = SourceRecordingFileWriter(fileURL: micURL)
        }
        if let systemURL = sourceFileURLs[.system] {
            systemWriter = SourceRecordingFileWriter(fileURL: systemURL)
        }

        if demoMode {
            state = .recording
            startTimer(from: startedAt)
            startStartupWatchdog()
            return
        }

        var startupMessages: [String] = []

        do {
            try await startMicSource()
        } catch {
            startupMessages.append("Microphone capture could not start: \(error.localizedDescription)")
        }

        do {
            try await startSystemSource()
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
        dependencies.diagnosticSink(
            .recordingStarted(activeSources: activeSources.map(\.label).sorted())
        )
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
        let stopRequestedAt = Date()
        elapsedTime = stopRequestedAt.timeIntervalSince(activeSession.startedAt)
        micCaptureManager?.stop()
        await systemAudioCaptureManager?.stop()
        micCaptureManager = nil
        systemAudioCaptureManager = nil

        do {
            try micWriter?.finish()
            try systemWriter?.finish()
        } catch {
            await failRecording(with: error.localizedDescription)
            return
        }

        let processingSession = finalizedSession(from: activeSession, status: .completed, endedAt: stopRequestedAt)
        self.activeSession = processingSession
        self.liveSegments = []
        self.state = .processing

        do {
            let finishedSession = try await buildCompletedSession(from: processingSession)
            self.activeSession = finishedSession
            upsertStoredSession(finishedSession)
            try await sessionStore.save(session: finishedSession)
            cleanupTransientSourceFiles()
            self.activeSession = nil
            self.activeSources = []
            self.micWriter = nil
            self.systemWriter = nil
            self.sourceFileURLs = [:]
            self.sourceProcessingStates = [:]
            self.state = .ready
            self.selectedSessionID = finishedSession.id
        } catch {
            await failRecording(with: error.localizedDescription)
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


    private func failRecording(with message: String) async {
        startupWatchdogTask?.cancel()
        let interruptedSession = activeSession.map {
            finalizedSession(from: $0, status: .recovered, endedAt: Date())
        }

        timerTask?.cancel()
        micCaptureManager?.stop()
        await systemAudioCaptureManager?.stop()
        micCaptureManager = nil
        systemAudioCaptureManager = nil
        try? micWriter?.finish()
        try? systemWriter?.finish()
        micWriter = nil
        systemWriter = nil
        activeSources = []
        activeSession = nil
        liveSegments = []
        sourceProcessingStates = [:]

        if let interruptedSession, !interruptedSession.segments.isEmpty || hasRecoverableSourceFiles(for: interruptedSession.id) {
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

        sourceFileURLs = [:]
        errorMessage = message
        state = .error(message)
    }

    private func startMicSource() async throws {
        guard let writer = micWriter else {
            throw NSError(domain: "Heed.RecordingController", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "The microphone file writer was not prepared."
            ])
        }

        let micCaptureManager = dependencies.makeMicCaptureManager()
        dependencies.diagnosticSink(.microphoneStartBegan)
        do {
            try micCaptureManager.start { [weak self] frames in
                do {
                    try writer.write(frames: frames)
                } catch {
                    Task { [weak self] in
                        await self?.handleSourceFailure(.mic, message: error.localizedDescription)
                    }
                    return
                }

                guard let self else { return }
                Task { @MainActor in
                    self.noteIncomingFrames(frames, from: .mic)
                }
            }
        } catch {
            dependencies.diagnosticSink(.microphoneStartFailed(error.localizedDescription))
            throw error
        }

        dependencies.diagnosticSink(.microphoneStartSucceeded)
        self.micCaptureManager = micCaptureManager
        self.activeSources.insert(.mic)
    }

    private func startSystemSource() async throws {
        guard let writer = systemWriter else {
            throw NSError(domain: "Heed.RecordingController", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "The system audio file writer was not prepared."
            ])
        }

        let systemAudioCaptureManager = dependencies.makeSystemAudioCaptureManager()
        dependencies.diagnosticSink(.systemAudioStartBegan)
        do {
            try await systemAudioCaptureManager.start(
                onFrames: { [weak self] frames in
                    do {
                        try writer.write(frames: frames)
                    } catch {
                        Task { [weak self] in
                            await self?.handleSourceFailure(.system, message: error.localizedDescription)
                        }
                        return
                    }

                    guard let self else { return }
                    Task { @MainActor in
                        self.noteIncomingFrames(frames, from: .system)
                    }
                },
                onFailure: { [weak self] message in
                    guard let self else { return }
                    Task {
                        await self.handleSourceFailure(.system, message: message)
                    }
                }
            )
        } catch {
            dependencies.diagnosticSink(.systemAudioStartFailed(error.localizedDescription))
            throw error
        }

        dependencies.diagnosticSink(.systemAudioStartSucceeded)
        self.systemAudioCaptureManager = systemAudioCaptureManager
        self.activeSources.insert(.system)
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

        dependencies.diagnosticSink(.sourceFailed(source, message))
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
            try? micWriter?.finish()
            micWriter = nil
        case .system:
            await systemAudioCaptureManager?.stop()
            systemAudioCaptureManager = nil
            try? systemWriter?.finish()
            systemWriter = nil
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
        guard state == .recording, activeSession != nil else {
            return
        }

        if !hasReceivedAudioFrames {
            await failRecording(with: "Heed started the session but never received audio. Check your microphone, screen capture permission, and current audio devices, then try again.")
            return
        }
    }

    private func buildCompletedSession(from session: TranscriptSession) async throws -> TranscriptSession {
        if demoMode {
            return try await buildDemoCompletedSession(from: session)
        }

        var completedSession = session
        let availableSources = availableRecordedSources()

        sourceProcessingStates = Dictionary(uniqueKeysWithValues: availableSources.map { ($0, .queued) })

        var failureMessages: [String] = []

        for source in availableSources {
            sourceProcessingStates[source] = .processing

            do {
                let segments = try await transcribeSource(source)
                apply(segments: segments, to: &completedSession, source: source)
                sourceProcessingStates[source] = .done
            } catch {
                sourceProcessingStates[source] = .failed
                failureMessages.append("\(source.label) transcription failed: \(error.localizedDescription)")
            }
        }

        if completedSession.segments.isEmpty, !failureMessages.isEmpty {
            throw NSError(domain: "Heed.RecordingController", code: 2, userInfo: [
                NSLocalizedDescriptionKey: failureMessages.joined(separator: " ")
            ])
        }

        if !failureMessages.isEmpty {
            errorMessage = failureMessages.joined(separator: " ")
        }

        return completedSession
    }

    private func buildDemoCompletedSession(from session: TranscriptSession) async throws -> TranscriptSession {
        var completedSession = session
        sourceProcessingStates = [.mic: .queued, .system: .queued]

        for source in [AudioSource.mic, .system] {
            sourceProcessingStates[source] = .processing
            try await Task.sleep(for: .milliseconds(250))
            apply(segments: demoSegments(for: source), to: &completedSession, source: source)
            sourceProcessingStates[source] = .done
        }

        return completedSession
    }

    private func transcribeSource(_ source: AudioSource) async throws -> [TranscriptSegment] {
        guard let fileURL = sourceFileURLs[source] else {
            return []
        }

        let helperURL = Bundle.main.bundleURL
            .appending(path: "Contents", directoryHint: .isDirectory)
            .appending(path: "Helpers", directoryHint: .isDirectory)
            .appending(path: "WhisperChunkCLI")
        let modelURL = Bundle.main.resourceURL!
            .appending(path: "Models", directoryHint: .isDirectory)
            .appending(path: "ggml-base.en.bin")

        let worker = WhisperWorker(source: source, helperURL: helperURL, modelURL: modelURL)
        let transcriber = BatchSourceTranscriber(source: source, worker: worker)
        return try await transcriber.transcribe(from: fileURL)
    }

    private func apply(
        segments: [TranscriptSegment],
        to session: inout TranscriptSession,
        source: AudioSource
    ) {
        switch source {
        case .mic:
            session.micSegments = segments
        case .system:
            session.systemSegments = segments
        }
    }

    private func availableRecordedSources() -> [AudioSource] {
        AudioSource.allCases.filter { source in
            guard let fileURL = sourceFileURLs[source] else {
                return false
            }

            return hasNonEmptyFile(at: fileURL)
        }
    }

    private func hasRecoverableSourceFiles(for sessionID: UUID) -> Bool {
        let sessionDirectory = sessionStore.sessionDirectoryURL(for: sessionID)
        return AudioSource.allCases.contains { source in
            hasNonEmptyFile(at: sessionDirectory.appending(path: "\(source.rawValue).pcm"))
        }
    }

    private func hasNonEmptyFile(at fileURL: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let fileSize = attributes[.size] as? NSNumber else {
            return false
        }

        return fileSize.intValue > 0
    }

    private func makeSourceFileURLs(for sessionID: UUID) -> [AudioSource: URL] {
        let sessionDirectory = sessionStore.sessionDirectoryURL(for: sessionID)
        return [
            .mic: sessionDirectory.appending(path: "mic.pcm"),
            .system: sessionDirectory.appending(path: "system.pcm")
        ]
    }

    private func cleanupTransientSourceFiles() {
        for fileURL in sourceFileURLs.values {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func demoSegments(for source: AudioSource) -> [TranscriptSegment] {
        switch source {
        case .mic:
            return [
                TranscriptSegment(source: .mic, startedAt: 1, endedAt: 2.4, text: "Can you hear me clearly on this side?"),
                TranscriptSegment(source: .mic, startedAt: 4.2, endedAt: 5.8, text: "Perfect. Heed is saving the mic side for batch transcription.")
            ]
        case .system:
            return [
                TranscriptSegment(source: .system, startedAt: 2, endedAt: 3.5, text: "Yes, the remote call audio is coming through.")
            ]
        }
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
