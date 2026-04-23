import Foundation

struct OpenAIStreamFunctionCallMetadata: Equatable, Sendable {
    let callID: String?
    let itemID: String?
    let outputIndex: Int?
    let sequenceNumber: Int?
}

struct OpenAIStreamFunctionCallIdentity: Equatable, Sendable {
    let metadata: OpenAIStreamFunctionCallMetadata
    let name: String?
}

enum OpenAIStreamEvent: Equatable, Sendable {
    case textDelta(String)
    case functionCallItemAdded(OpenAIStreamFunctionCallIdentity)
    case functionArgumentsDelta(OpenAIStreamFunctionCallMetadata, String)
    case functionCallCompleted(OpenAIStreamFunctionCallIdentity, arguments: String)
    case completed(responseID: String?)
    case failed(String)
}

enum OpenAIResponsesStreamParseError: LocalizedError, Equatable {
    case invalidEventData(event: String)
    case missingRequiredField(event: String, field: String)

    var errorDescription: String? {
        switch self {
        case let .invalidEventData(event):
            return "Could not parse streamed OpenAI event data for \(event)."
        case let .missingRequiredField(event, field):
            return "Streamed OpenAI event \(event) was missing \(field)."
        }
    }
}

struct OpenAIResponsesStreamParser {
    func parse(_ payload: String) throws -> [OpenAIStreamEvent] {
        try parse(lines: payload.components(separatedBy: .newlines))
    }

    private func parse(lines: [String]) throws -> [OpenAIStreamEvent] {
        var events: [OpenAIStreamEvent] = []
        var currentEventName: String?
        var dataLines: [String] = []

        func flushCurrentEvent() throws {
            guard let currentEventName else {
                dataLines.removeAll(keepingCapacity: true)
                return
            }

            defer {
                dataLines.removeAll(keepingCapacity: true)
            }

            let payload = dataLines.joined(separator: "\n").trimmingCharacters(in: .whitespaces)
            guard let event = try parseEvent(named: currentEventName, payload: payload) else {
                return
            }

            events.append(event)
        }

        for line in lines {
            if line.isEmpty {
                try flushCurrentEvent()
                currentEventName = nil
                continue
            }

            if let field = fieldValue(in: line, named: "event") {
                if currentEventName != nil || !dataLines.isEmpty {
                    try flushCurrentEvent()
                }
                currentEventName = field
                continue
            }

            if let field = fieldValue(in: line, named: "data") {
                dataLines.append(field)
            }
        }

        try flushCurrentEvent()
        return events
    }

    private func parseEvent(named name: String, payload: String) throws -> OpenAIStreamEvent? {
        switch name {
        case "response.output_text.delta":
            return .textDelta(try decodeStringField(named: "delta", in: payload, event: name))
        case "response.output_item.added":
            let object = try requiredJSONObject(from: payload, event: name)
            let item = functionCallItem(from: object)
            guard item["type"] as? String == "function_call" else {
                return nil
            }

            return .functionCallItemAdded(
                OpenAIStreamFunctionCallIdentity(
                    metadata: try decodeFunctionCallMetadata(from: object, event: name),
                    name: decodeOptionalStringField(named: "name", from: item)
                )
            )
        case "response.function_call_arguments.delta":
            let object = try requiredJSONObject(from: payload, event: name)
            return .functionArgumentsDelta(
                try decodeFunctionCallMetadata(from: object, event: name),
                try decodeStringField(named: "delta", from: object, event: name)
            )
        case "response.function_call_arguments.done":
            let object = try requiredJSONObject(from: payload, event: name)
            let item = functionCallItem(from: object)
            return .functionCallCompleted(
                OpenAIStreamFunctionCallIdentity(
                    metadata: try decodeFunctionCallMetadata(from: object, event: name),
                    name: decodeOptionalStringField(named: "name", from: item)
                ),
                arguments: try decodeStringField(named: "arguments", from: item, event: name)
            )
        case "response.completed":
            let object = try jsonObject(from: payload, event: name)
            return .completed(responseID: decodeResponseID(from: object))
        case "response.failed", "error":
            return .failed(try decodeFailureMessage(in: payload, event: name))
        default:
            return nil
        }
    }

    private func decodeFunctionCallMetadata(
        from object: [String: Any],
        event: String,
        requireCallID: Bool = false
    ) throws -> OpenAIStreamFunctionCallMetadata {
        let item = functionCallItem(from: object)
        let callID = (item["call_id"] as? String) ?? (object["call_id"] as? String)

        if requireCallID, callID == nil {
            throw OpenAIResponsesStreamParseError.missingRequiredField(event: event, field: "call_id")
        }

        return OpenAIStreamFunctionCallMetadata(
            callID: callID,
            itemID: (item["id"] as? String) ?? (item["item_id"] as? String) ?? (object["item_id"] as? String),
            outputIndex: decodeIntField(named: "output_index", from: object)
                ?? decodeIntField(named: "output_index", from: item),
            sequenceNumber: decodeIntField(named: "sequence_number", from: object)
                ?? decodeIntField(named: "content_index", from: object)
        )
    }

    private func functionCallItem(from object: [String: Any]) -> [String: Any] {
        if let item = object["item"] as? [String: Any] {
            return item
        }

        return object
    }

    private func decodeStringField(named field: String, in payload: String, event: String) throws -> String {
        let object = try requiredJSONObject(from: payload, event: event)
        return try decodeStringField(named: field, from: object, event: event)
    }

    private func decodeStringField(
        named field: String,
        from object: [String: Any],
        event: String
    ) throws -> String {
        guard let value = decodeOptionalStringField(named: field, from: object) else {
            throw OpenAIResponsesStreamParseError.missingRequiredField(event: event, field: field)
        }

        return value
    }

    private func decodeOptionalStringField(named field: String, from object: [String: Any]) -> String? {
        object[field] as? String
    }

    private func decodeIntField(named field: String, from object: [String: Any]) -> Int? {
        if let value = object[field] as? Int {
            return value
        }

        if let value = object[field] as? NSNumber {
            return value.intValue
        }

        return nil
    }

    private func decodeFailureMessage(in payload: String, event: String) throws -> String {
        let object = try requiredJSONObject(from: payload, event: event)

        if let message = nestedString(in: object, path: ["message"]) ?? nestedString(in: object, path: ["error", "message"]) {
            return message
        }

        if let message = nestedString(in: object, path: ["response", "error", "message"])
            ?? nestedString(in: object, path: ["response", "status_details", "error", "message"])
            ?? nestedString(in: object, path: ["response", "status_details", "message"]) {
            return message
        }

        throw OpenAIResponsesStreamParseError.missingRequiredField(event: event, field: "message")
    }

    private func decodeResponseID(from object: [String: Any]?) -> String? {
        guard let object else {
            return nil
        }

        return nestedString(in: object, path: ["response", "id"]) ?? nestedString(in: object, path: ["response_id"])
    }

    private func requiredJSONObject(from payload: String, event: String) throws -> [String: Any] {
        guard let object = try jsonObject(from: payload, event: event) else {
            throw OpenAIResponsesStreamParseError.invalidEventData(event: event)
        }

        return object
    }

    private func jsonObject(from payload: String, event: String) throws -> [String: Any]? {
        guard !payload.isEmpty, payload != "[DONE]" else {
            return nil
        }

        guard let data = payload.data(using: .utf8) else {
            throw OpenAIResponsesStreamParseError.invalidEventData(event: event)
        }

        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw OpenAIResponsesStreamParseError.invalidEventData(event: event)
            }

            return object
        } catch let error as OpenAIResponsesStreamParseError {
            throw error
        } catch {
            throw OpenAIResponsesStreamParseError.invalidEventData(event: event)
        }
    }

    private func nestedString(in object: [String: Any], path: [String]) -> String? {
        var current: Any = object

        for key in path {
            guard let dictionary = current as? [String: Any],
                  let next = dictionary[key] else {
                return nil
            }

            current = next
        }

        return current as? String
    }

    private func fieldValue(in line: String, named field: String) -> String? {
        let prefix = "\(field):"
        guard line.hasPrefix(prefix) else {
            return nil
        }

        return line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
    }
}
