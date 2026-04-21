import Foundation

enum OpenAIStreamEvent: Equatable, Sendable {
    case textDelta(String)
    case functionArgumentsDelta(String)
    case completed
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
        case "response.function_call_arguments.delta":
            return .functionArgumentsDelta(try decodeStringField(named: "delta", in: payload, event: name))
        case "response.function_call_arguments.done":
            return nil
        case "response.completed":
            return .completed
        case "error":
            return .failed(try decodeErrorMessage(in: payload))
        default:
            return nil
        }
    }

    private func decodeStringField(named field: String, in payload: String, event: String) throws -> String {
        guard let object = try jsonObject(from: payload),
              let value = object[field] as? String else {
            throw missingFieldError(for: event, field: field, payload: payload)
        }

        return value
    }

    private func decodeErrorMessage(in payload: String) throws -> String {
        guard let object = try jsonObject(from: payload) else {
            throw OpenAIResponsesStreamParseError.invalidEventData(event: "error")
        }

        if let message = object["message"] as? String, !message.isEmpty {
            return message
        }

        if let nestedError = object["error"] as? [String: Any],
           let message = nestedError["message"] as? String,
           !message.isEmpty {
            return message
        }

        throw OpenAIResponsesStreamParseError.missingRequiredField(event: "error", field: "message")
    }

    private func jsonObject(from payload: String) throws -> [String: Any]? {
        guard !payload.isEmpty, payload != "[DONE]" else {
            return nil
        }

        guard let data = payload.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenAIResponsesStreamParseError.invalidEventData(event: "unknown")
        }

        return object
    }

    private func missingFieldError(for event: String, field: String, payload: String) -> OpenAIResponsesStreamParseError {
        if payload.isEmpty || payload == "[DONE]" {
            return .missingRequiredField(event: event, field: field)
        }

        return .missingRequiredField(event: event, field: field)
    }

    private func fieldValue(in line: String, named field: String) -> String? {
        let prefix = "\(field):"
        guard line.hasPrefix(prefix) else {
            return nil
        }

        return line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
    }
}
