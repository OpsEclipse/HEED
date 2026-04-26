import Foundation
import Testing
@testable import heed

struct ComposioToolRouterSessionProviderTests {
    @Test func missingAPIKeyDisablesComposioTool() async throws {
        let provider = ComposioToolRouterSessionProvider(
            apiKeyProvider: { nil },
            userIDProvider: { "heed-user" },
            transport: RecordingComposioSessionTransport(responseBody: Data())
        )

        let tool = try await provider.makeMCPTool()

        #expect(tool == nil)
    }

    @Test func createsScopedSessionAndBuildsMCPTool() async throws {
        let response = """
        {
          "session_id": "trs_test",
          "mcp": {
            "type": "http",
            "url": "https://app.composio.dev/tool_router/v3/trs_test/mcp"
          }
        }
        """
        let transport = RecordingComposioSessionTransport(responseBody: Data(response.utf8))
        let provider = ComposioToolRouterSessionProvider(
            apiKeyProvider: { "composio-test-key" },
            userIDProvider: { "heed-user" },
            transport: transport
        )

        let tool = try #require(try await provider.makeMCPTool())

        #expect(tool.serverURL.absoluteString == "https://app.composio.dev/tool_router/v3/trs_test/mcp")
        #expect(tool.headers["x-api-key"] == "composio-test-key")

        let request = try #require(transport.recordedRequests.first)
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "composio-test-key")

        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["user_id"] as? String == "heed-user")

        let toolkits = try #require(json["toolkits"] as? [String: Any])
        #expect(toolkits["enabled"] as? [String] == ["gmail", "googlecalendar", "googledrive"])

        let workbench = try #require(json["workbench"] as? [String: Any])
        #expect(workbench["enable"] as? Bool == false)
    }
}

private final class RecordingComposioSessionTransport: @unchecked Sendable, ComposioSessionTransport {
    private(set) var recordedRequests: [URLRequest] = []
    private let responseBody: Data
    private let statusCode: Int

    init(responseBody: Data, statusCode: Int = 201) {
        self.responseBody = responseBody
        self.statusCode = statusCode
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        recordedRequests.append(request)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://backend.composio.dev/api/v3.1/tool_router/session")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!

        return (responseBody, response)
    }
}
