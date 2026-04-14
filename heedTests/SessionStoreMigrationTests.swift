import Foundation
import Testing
@testable import heed

struct SessionStoreMigrationTests {
    @Test func legacySessionJSONDecodesIntoSplitSourceArrays() throws {
        let legacyJSON = """
        {
          "appVersion": "1.0",
          "duration": 10,
          "endedAt": "1970-01-01T00:00:10Z",
          "id": "00000000-0000-0000-0000-000000000001",
          "modelName": "ggml-base.en",
          "segments": [
            {
              "endedAt": 2,
              "id": "00000000-0000-0000-0000-000000000011",
              "source": "mic",
              "startedAt": 1,
              "text": "Hello from the mic"
            },
            {
              "endedAt": 4,
              "id": "00000000-0000-0000-0000-000000000012",
              "source": "system",
              "startedAt": 3,
              "text": "Hello from system audio"
            }
          ],
          "startedAt": "1970-01-01T00:00:00Z",
          "status": "completed"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let session = try decoder.decode(TranscriptSession.self, from: Data(legacyJSON.utf8))

        #expect(session.micSegments.count == 1)
        #expect(session.systemSegments.count == 1)
        #expect(session.micSegments[0].text == "Hello from the mic")
        #expect(session.systemSegments[0].text == "Hello from system audio")
        #expect(session.segments.map(\.text) == [
            "Hello from the mic",
            "Hello from system audio"
        ])
    }

    @Test func splitSessionJSONDecodesAndKeepsMergedCompatibilityView() throws {
        let splitJSON = """
        {
          "appVersion": "1.0",
          "duration": 10,
          "endedAt": "1970-01-01T00:00:10Z",
          "id": "00000000-0000-0000-0000-000000000002",
          "micSegments": [
            {
              "endedAt": 2,
              "id": "00000000-0000-0000-0000-000000000021",
              "source": "mic",
              "startedAt": 1,
              "text": "Mic segment"
            }
          ],
          "modelName": "ggml-base.en",
          "segments": [
            {
              "endedAt": 2,
              "id": "00000000-0000-0000-0000-000000000021",
              "source": "mic",
              "startedAt": 1,
              "text": "Mic segment"
            },
            {
              "endedAt": 4,
              "id": "00000000-0000-0000-0000-000000000022",
              "source": "system",
              "startedAt": 3,
              "text": "System segment"
            }
          ],
          "startedAt": "1970-01-01T00:00:00Z",
          "status": "completed",
          "systemSegments": [
            {
              "endedAt": 4,
              "id": "00000000-0000-0000-0000-000000000022",
              "source": "system",
              "startedAt": 3,
              "text": "System segment"
            }
          ]
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let session = try decoder.decode(TranscriptSession.self, from: Data(splitJSON.utf8))

        #expect(session.micSegments.map(\.text) == ["Mic segment"])
        #expect(session.systemSegments.map(\.text) == ["System segment"])
        #expect(session.segments.map(\.text) == ["Mic segment", "System segment"])
    }

    @Test func splitSessionEncodesCompatibilityAndSplitFields() throws {
        let session = TranscriptSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 10),
            duration: 10,
            status: .completed,
            modelName: "ggml-base.en",
            appVersion: "1.0",
            micSegments: [
                TranscriptSegment(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000031")!,
                    source: .mic,
                    startedAt: 1,
                    endedAt: 2,
                    text: "Mic segment"
                )
            ],
            systemSegments: [
                TranscriptSegment(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000032")!,
                    source: .system,
                    startedAt: 3,
                    endedAt: 4,
                    text: "System segment"
                )
            ]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(session)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        let micSegments = try #require(object["micSegments"] as? [[String: Any]])
        let systemSegments = try #require(object["systemSegments"] as? [[String: Any]])
        let mergedSegments = try #require(object["segments"] as? [[String: Any]])

        #expect(micSegments.count == 1)
        #expect(systemSegments.count == 1)
        #expect(mergedSegments.count == 2)
    }

    @Test func exportUsesMergedCompatibilityViewForSplitSessions() {
        let session = TranscriptSession(
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 10),
            duration: 10,
            status: .completed,
            modelName: "ggml-base.en",
            appVersion: "1.0",
            micSegments: [
                TranscriptSegment(source: .mic, startedAt: 1, endedAt: 2, text: "Mic first")
            ],
            systemSegments: [
                TranscriptSegment(source: .system, startedAt: 3, endedAt: 4, text: "System second")
            ]
        )

        let plainText = TranscriptExport.plainText(from: session)

        #expect(plainText.contains("[00:00:01] MIC: Mic first"))
        #expect(plainText.contains("[00:00:03] SYSTEM: System second"))
    }
}
