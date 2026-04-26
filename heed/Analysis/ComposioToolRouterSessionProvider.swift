import Foundation

protocol ComposioSessionProviding: Sendable {
    func makeMCPTool() async throws -> ComposioMCPTool?
}

struct ComposioMCPTool: Equatable, Sendable {
    let serverURL: URL
    let headers: [String: String]

    var responseToolPayload: [String: Any] {
        [
            "type": "mcp",
            "server_label": "composio",
            "server_description": "Composio tools scoped to Gmail, Google Calendar, and Google Drive for the current Heed user.",
            "server_url": serverURL.absoluteString,
            "headers": headers,
            "require_approval": "never"
        ]
    }
}

struct DisabledComposioSessionProvider: ComposioSessionProviding {
    func makeMCPTool() async throws -> ComposioMCPTool? {
        nil
    }
}

protocol ComposioSessionTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionComposioSessionTransport: ComposioSessionTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ComposioSessionProviderError.invalidHTTPResponse
        }

        return (data, httpResponse)
    }
}

struct ComposioToolRouterSessionProvider: ComposioSessionProviding {
    private static let sessionURL = URL(string: "https://backend.composio.dev/api/v3.1/tool_router/session")!

    private let apiKeyProvider: @Sendable () throws -> String?
    private let userIDProvider: @Sendable () -> String
    private let transport: any ComposioSessionTransport

    init(
        apiKeyProvider: @escaping @Sendable () throws -> String? = {
            try KeychainAPIKeyStore(service: KeychainAPIKeyStore.composioService).readAPIKey()
        },
        userIDProvider: @escaping @Sendable () -> String = {
            ComposioUserIDStore.shared.userID()
        },
        transport: any ComposioSessionTransport = URLSessionComposioSessionTransport()
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.userIDProvider = userIDProvider
        self.transport = transport
    }

    func makeMCPTool() async throws -> ComposioMCPTool? {
        guard let apiKey = try apiKeyProvider()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            return nil
        }

        let request = try makeSessionRequest(apiKey: apiKey, userID: userIDProvider())
        let (data, response) = try await transport.send(request)

        guard (200...299).contains(response.statusCode) else {
            throw ComposioSessionProviderError.httpFailure(
                statusCode: response.statusCode,
                message: Self.errorMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
            )
        }

        let session = try JSONDecoder().decode(ComposioToolRouterSessionResponse.self, from: data)
        guard let serverURL = URL(string: session.mcp.url) else {
            throw ComposioSessionProviderError.invalidMCPURL
        }

        var headers = session.mcp.headers ?? [:]
        if headers["x-api-key"] == nil {
            headers["x-api-key"] = apiKey
        }

        return ComposioMCPTool(serverURL: serverURL, headers: headers)
    }

    private func makeSessionRequest(apiKey: String, userID: String) throws -> URLRequest {
        var request = URLRequest(url: Self.sessionURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: [
                "user_id": userID,
                "toolkits": [
                    "enabled": ["gmail", "googlecalendar", "googledrive"]
                ],
                "workbench": [
                    "enable": false
                ],
                "manage_connections": [
                    "enable": true,
                    "enable_wait_for_connections": false,
                    "enable_connection_removal": true
                ]
            ]
        )
        return request
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let message = object["message"] as? String {
            return message
        }

        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }

        return nil
    }
}

enum ComposioSessionProviderError: LocalizedError, Equatable {
    case invalidHTTPResponse
    case httpFailure(statusCode: Int, message: String)
    case invalidMCPURL

    var errorDescription: String? {
        switch self {
        case .invalidHTTPResponse:
            return "Composio returned an invalid response."
        case let .httpFailure(_, message):
            return "Composio session creation failed: \(message)"
        case .invalidMCPURL:
            return "Composio returned an invalid MCP URL."
        }
    }
}

private struct ComposioToolRouterSessionResponse: Decodable {
    struct MCP: Decodable {
        let url: String
        let headers: [String: String]?
    }

    let mcp: MCP
}

final class ComposioUserIDStore: @unchecked Sendable {
    static let shared = ComposioUserIDStore()

    private let defaults: UserDefaults
    private let key = "heed.composio.userID"
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func userID() -> String {
        lock.withLock {
            if let existing = defaults.string(forKey: key), !existing.isEmpty {
                return existing
            }

            let created = "heed-\(UUID().uuidString.lowercased())"
            defaults.set(created, forKey: key)
            return created
        }
    }
}
