import Foundation
import Security

protocol OpenAIResponsesTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionOpenAIResponsesTransport: OpenAIResponsesTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIResponsesError.invalidHTTPResponse
        }

        return (data, httpResponse)
    }
}

struct OpenAIResponsesClient: Sendable {
    let model: String

    private let apiKeyProvider: @Sendable () throws -> String?
    private let transport: any OpenAIResponsesTransport

    init(
        model: String = "gpt-5.4-mini",
        apiKeyProvider: @escaping @Sendable () throws -> String? = {
            try loadStoredOpenAIAPIKey()
        },
        transport: any OpenAIResponsesTransport = URLSessionOpenAIResponsesTransport()
    ) {
        self.model = model
        self.apiKeyProvider = apiKeyProvider
        self.transport = transport
    }

    func generateStructuredOutput<Output: Decodable>(
        systemPrompt: String,
        userPrompt: String,
        schemaName: String,
        schema: [String: Any],
        maxOutputTokens: Int = 3200
    ) async throws -> Output {
        guard let apiKey = try apiKeyProvider()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            throw OpenAIResponsesError.missingAPIKey
        }

        let request = try makeRequest(
            apiKey: apiKey,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            schemaName: schemaName,
            schema: schema,
            maxOutputTokens: maxOutputTokens
        )

        let (data, response) = try await transport.send(request)
        guard (200...299).contains(response.statusCode) else {
            throw OpenAIResponsesError.httpFailure(
                statusCode: response.statusCode,
                message: Self.errorMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
            )
        }

        let envelope = try JSONDecoder().decode(OpenAIResponsesEnvelope.self, from: data)
        guard let outputText = envelope.outputText else {
            throw OpenAIResponsesError.missingOutputText
        }

        guard let outputData = outputText.data(using: .utf8) else {
            throw OpenAIResponsesError.invalidStructuredOutput
        }

        do {
            return try JSONDecoder().decode(Output.self, from: outputData)
        } catch {
            throw OpenAIResponsesError.decodingFailed(error.localizedDescription)
        }
    }

    private func makeRequest(
        apiKey: String,
        systemPrompt: String,
        userPrompt: String,
        schemaName: String,
        schema: [String: Any],
        maxOutputTokens: Int
    ) throws -> URLRequest {
        let body: [String: Any] = [
            "model": model,
            "input": [
                Self.messagePayload(role: "system", text: systemPrompt),
                Self.messagePayload(role: "user", text: userPrompt)
            ],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": schemaName,
                    "strict": true,
                    "schema": schema
                ]
            ],
            "max_output_tokens": maxOutputTokens
        ]

        guard JSONSerialization.isValidJSONObject(body) else {
            throw OpenAIResponsesError.invalidRequestBody
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Client-Request-Id")
        return request
    }

    private static func messagePayload(role: String, text: String) -> [String: Any] {
        [
            "role": role,
            "content": [
                [
                    "type": "input_text",
                    "text": text
                ]
            ]
        ]
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let envelope = try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data) else {
            return nil
        }

        return envelope.error.message
    }
}

enum OpenAIResponsesError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidRequestBody
    case invalidHTTPResponse
    case httpFailure(statusCode: Int, message: String)
    case missingOutputText
    case invalidStructuredOutput
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Set an OpenAI API key before compiling tasks."
        case .invalidRequestBody:
            return "Could not build the OpenAI request."
        case .invalidHTTPResponse:
            return "OpenAI returned an invalid response."
        case let .httpFailure(_, message):
            return "OpenAI request failed: \(message)"
        case .missingOutputText:
            return "OpenAI returned no text output."
        case .invalidStructuredOutput:
            return "OpenAI returned invalid structured output."
        case let .decodingFailed(message):
            return "Could not decode OpenAI output: \(message)"
        }
    }
}

private struct OpenAIResponsesEnvelope: Decodable {
    let output: [ResponseOutput]

    var outputText: String? {
        for item in output {
            for content in item.content ?? [] where content.type == "output_text" {
                if let text = content.text, !text.isEmpty {
                    return text
                }
            }
        }

        return nil
    }

    struct ResponseOutput: Decodable {
        let content: [ResponseContent]?
    }

    struct ResponseContent: Decodable {
        let type: String
        let text: String?
    }
}

private struct OpenAIErrorEnvelope: Decodable {
    let error: APIError

    struct APIError: Decodable {
        let message: String
    }
}

private func loadStoredOpenAIAPIKey() throws -> String? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "sprsh.ca.heed.api-key",
        kSecAttrAccount as String: "default",
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne
    ]

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)

    switch status {
    case errSecSuccess:
        guard let data = item as? Data else {
            throw APIKeyStorageError.invalidStoredValue
        }

        return String(data: data, encoding: .utf8)
    case errSecItemNotFound:
        return nil
    default:
        throw APIKeyStorageError.keychainFailure(status)
    }
}
