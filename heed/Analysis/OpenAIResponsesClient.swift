import Foundation
import Security

protocol OpenAIResponsesTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
    func stream(_ request: URLRequest) -> AsyncThrowingStream<String, Error>
}

extension OpenAIResponsesTransport {
    func stream(_ request: URLRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: OpenAIResponsesError.streamingUnsupported)
        }
    }
}

struct URLSessionOpenAIResponsesTransport: OpenAIResponsesTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIResponsesError.invalidHTTPResponse
        }

        return (data, httpResponse)
    }

    func stream(_ request: URLRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw OpenAIResponsesError.invalidHTTPResponse
                    }

                    guard (200...299).contains(httpResponse.statusCode) else {
                        var responseData = Data()
                        for try await byte in bytes {
                            responseData.append(byte)
                        }

                        throw OpenAIResponsesError.httpFailure(
                            statusCode: httpResponse.statusCode,
                            message: openAIErrorMessage(from: responseData) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                        )
                    }

                    for try await line in bytes.lines {
                        continuation.yield(line)
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
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
            input: [
                Self.messagePayload(role: "system", text: systemPrompt),
                Self.messagePayload(role: "user", text: userPrompt)
            ],
            textFormat: [
                "type": "json_schema",
                "name": schemaName,
                "strict": true,
                "schema": schema
            ],
            tools: [],
            maxOutputTokens: maxOutputTokens
        )

        let (data, response) = try await transport.send(request)
        guard (200...299).contains(response.statusCode) else {
            throw OpenAIResponsesError.httpFailure(
                statusCode: response.statusCode,
                message: openAIErrorMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
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

    func streamConversation(
        systemPrompt: String,
        userPrompt: String,
        tools: [[String: Any]],
        maxOutputTokens: Int = 3200
    ) throws -> AsyncThrowingStream<OpenAIStreamEvent, Error> {
        try streamConversation(
            input: [
                Self.messagePayload(role: "system", text: systemPrompt),
                Self.messagePayload(role: "user", text: userPrompt)
            ],
            tools: tools,
            maxOutputTokens: maxOutputTokens
        )
    }

    func streamConversation(
        input: [[String: Any]],
        tools: [[String: Any]],
        previousResponseID: String? = nil,
        maxOutputTokens: Int = 3200
    ) throws -> AsyncThrowingStream<OpenAIStreamEvent, Error> {
        guard let apiKey = try apiKeyProvider()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            throw OpenAIResponsesError.missingAPIKey
        }

        let request = try makeRequest(
            apiKey: apiKey,
            input: input,
            textFormat: nil,
            tools: tools,
            previousResponseID: previousResponseID,
            maxOutputTokens: maxOutputTokens,
            stream: true
        )

        let lineStream = transport.stream(request)
        let parser = OpenAIResponsesStreamParser()

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var eventLines: [String] = []

                    for try await line in lineStream {
                        eventLines.append(line)

                        if line.isEmpty {
                            try yieldParsedEvents(from: &eventLines, parser: parser, continuation: continuation)
                        }
                    }

                    try yieldParsedEvents(from: &eventLines, parser: parser, continuation: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func makeRequest(
        apiKey: String,
        input: [[String: Any]],
        textFormat: [String: Any]?,
        tools: [[String: Any]],
        previousResponseID: String? = nil,
        maxOutputTokens: Int?,
        stream: Bool = false
    ) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.httpBody = try makeJSONRequestBody(
            input: input,
            textFormat: textFormat,
            tools: tools,
            previousResponseID: previousResponseID,
            maxOutputTokens: maxOutputTokens,
            stream: stream
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Client-Request-Id")
        return request
    }

    func makeJSONRequestBody(
        input: [[String: Any]],
        textFormat: [String: Any]?,
        tools: [[String: Any]],
        previousResponseID: String? = nil,
        maxOutputTokens: Int?,
        stream: Bool
    ) throws -> Data {
        var body: [String: Any] = [
            "model": model,
            "input": input,
            "stream": stream
        ]

        if let textFormat {
            body["text"] = [
                "format": textFormat
            ]
        }

        if !tools.isEmpty {
            body["tools"] = tools
        }

        if let previousResponseID {
            body["previous_response_id"] = previousResponseID
        }

        if let maxOutputTokens {
            body["max_output_tokens"] = maxOutputTokens
        }

        guard JSONSerialization.isValidJSONObject(body) else {
            throw OpenAIResponsesError.invalidRequestBody
        }

        return try JSONSerialization.data(withJSONObject: body)
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

    private func yieldParsedEvents(
        from eventLines: inout [String],
        parser: OpenAIResponsesStreamParser,
        continuation: AsyncThrowingStream<OpenAIStreamEvent, Error>.Continuation
    ) throws {
        guard !eventLines.isEmpty else {
            return
        }

        let payload = eventLines.joined(separator: "\n")
        eventLines.removeAll(keepingCapacity: true)

        for event in try parser.parse(payload) {
            continuation.yield(event)
        }
    }
}

enum OpenAIResponsesError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidRequestBody
    case invalidHTTPResponse
    case streamingUnsupported
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
        case .streamingUnsupported:
            return "OpenAI streaming is not available for this transport."
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

private func openAIErrorMessage(from data: Data) -> String? {
    guard let envelope = try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data) else {
        return nil
    }

    return envelope.error.message
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
