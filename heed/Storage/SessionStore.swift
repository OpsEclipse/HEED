import Foundation

actor SessionStore {
    private let baseDirectoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseDirectoryURL: URL? = nil) {
        if let baseDirectoryURL {
            self.baseDirectoryURL = baseDirectoryURL
        } else {
            let applicationSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.baseDirectoryURL = applicationSupportURL
                .appending(path: "Heed", directoryHint: .isDirectory)
                .appending(path: "Sessions", directoryHint: .isDirectory)
        }

        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func loadSessions() throws -> [TranscriptSession] {
        try ensureBaseDirectory()

        let directoryContents = try FileManager.default.contentsOfDirectory(
            at: baseDirectoryURL,
            includingPropertiesForKeys: nil
        )

        var sessions: [TranscriptSession] = []

        for sessionDirectory in directoryContents where sessionDirectory.hasDirectoryPath {
            let sessionURL = sessionDirectory.appending(path: "session.json")
            guard FileManager.default.fileExists(atPath: sessionURL.path()) else {
                continue
            }

            let data = try Data(contentsOf: sessionURL)
            var session = try decoder.decode(TranscriptSession.self, from: data)
            if session.status == .recording {
                session.status = .recovered
                session.endedAt = session.endedAt ?? session.startedAt.addingTimeInterval(session.duration)
            }
            sessions.append(session)
        }

        let sorted = sessions.sorted { lhs, rhs in
            lhs.startedAt > rhs.startedAt
        }

        for session in sorted where session.status == .recovered {
            try save(session: session)
        }

        return sorted
    }

    func save(session: TranscriptSession) throws {
        try ensureBaseDirectory()
        let sessionDirectory = baseDirectoryURL.appending(path: session.id.uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)

        let data = try encoder.encode(session)
        let sessionURL = sessionDirectory.appending(path: "session.json")
        try data.write(to: sessionURL, options: .atomic)
    }

    func deleteSession(id: UUID) throws {
        let sessionDirectory = baseDirectoryURL.appending(path: id.uuidString, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: sessionDirectory.path()) else {
            return
        }

        try FileManager.default.removeItem(at: sessionDirectory)
    }

    func sessionDirectoryURL(for sessionID: UUID) -> URL {
        baseDirectoryURL.appending(path: sessionID.uuidString, directoryHint: .isDirectory)
    }

    private func ensureBaseDirectory() throws {
        try FileManager.default.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
    }
}
