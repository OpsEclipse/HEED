import Foundation
import Testing
@testable import heed

struct OpenAIResponsesStreamTests {
    @Test func parserEmitsTextAndFunctionArgumentDeltasInOrder() throws {
        let payload = [
            "event: response.output_text.delta",
            "data: {\"delta\":\"Hello\"}",
            "",
            "event: response.function_call_arguments.delta",
            "data: {\"delta\":\"{\\\"approval\\\":true}\"}",
            ""
        ].joined(separator: "\n")

        let events = try OpenAIResponsesStreamParser().parse(payload)

        #expect(events == [
            .textDelta("Hello"),
            .functionArgumentsDelta("{\"approval\":true}")
        ])
    }
}
