import XCTest
@testable import ScriptForgeMac

final class OpenAIClientTests: XCTestCase {
    private struct StructuredFixture: Codable, Equatable, Sendable {
        let title: String
        let items: [Int]
    }

    func testEndpointURLAcceptsAPIRoot() {
        XCTAssertEqual(
            LLMClient.endpointURL(
                baseURL: "https://api.example.com/v1",
                endpoint: "chat/completions"
            )?.absoluteString,
            "https://api.example.com/v1/chat/completions"
        )
    }

    func testEndpointURLNormalizesCompleteOpenAICompatibleEndpoint() {
        let completeEndpoints = [
            "https://api.example.com/v1/responses",
            "https://api.example.com/v1/chat/completions",
            "https://api.example.com/v1/images/generations",
            "https://api.example.com/v1/audio/speech",
        ]

        for baseURL in completeEndpoints {
            XCTAssertEqual(
                LLMClient.endpointURL(
                    baseURL: baseURL,
                    endpoint: "chat/completions"
                )?.absoluteString,
                "https://api.example.com/v1/chat/completions"
            )
        }
    }

    func testEndpointURLPreservesProviderQueryParameters() {
        XCTAssertEqual(
            LLMClient.endpointURL(
                baseURL: "https://api.example.com/openai/v1/responses?api-version=2026-01-01",
                endpoint: "chat/completions"
            )?.absoluteString,
            "https://api.example.com/openai/v1/chat/completions?api-version=2026-01-01"
        )
    }

    func testEndpointURLRejectsNonHTTPValues() {
        XCTAssertNil(LLMClient.endpointURL(baseURL: "api.example.com/v1", endpoint: "responses"))
        XCTAssertNil(LLMClient.endpointURL(baseURL: "file:///tmp/v1", endpoint: "responses"))
    }

    func testStructuredStagesHaveExplicitBoundedOutputBudgets() {
        XCTAssertEqual(ModelStage.bookAnalysisExtract.outputTokenLimit, 8_192)
        XCTAssertEqual(ModelStage.bookAnalysisCommercial.outputTokenLimit, 8_192)
        XCTAssertTrue(ModelStage.allCases.allSatisfy { (4_096...8_192).contains($0.outputTokenLimit) })
    }

    func testFastExtractionDoesNotInheritExpensiveGlobalReasoning() {
        XCTAssertEqual(
            ModelStage.bookAnalysisExtract.resolvedReasoningEffort(configured: "medium"),
            "low"
        )
        XCTAssertEqual(
            ModelStage.bookAnalysisCommercial.resolvedReasoningEffort(configured: "medium"),
            "medium"
        )
    }

    func testOpenRouterUsesDocumentedChatStructuredRoute() {
        XCTAssertTrue(LLMClient.prefersChatStructuredOutput(
            baseURL: "https://openrouter.ai/api/v1"
        ))
        XCTAssertFalse(LLMClient.prefersChatStructuredOutput(
            baseURL: "https://api.openai.com/v1"
        ))
    }

    func testOpenRouterChatPayloadEnforcesJSONSchemaAtTheAPI() throws {
        let schema: [String: Any] = [
            "type": "object",
            "properties": ["title": ["type": "string"]],
            "required": ["title"],
            "additionalProperties": false,
        ]
        let payload = try LLMClient.makeChatPayload(
            model: "google/gemini-3.7-flash",
            instructions: "Return a title.",
            input: "Source",
            name: "title_result",
            schema: schema,
            outputTokenLimit: 4_096,
            reasoningEffort: "medium",
            isOpenRouter: true,
            strict: true
        )

        let responseFormat = try XCTUnwrap(payload["response_format"] as? [String: Any])
        XCTAssertEqual(responseFormat["type"] as? String, "json_schema")
        let jsonSchema = try XCTUnwrap(responseFormat["json_schema"] as? [String: Any])
        XCTAssertEqual(jsonSchema["name"] as? String, "title_result")
        XCTAssertEqual(jsonSchema["strict"] as? Bool, true)
        XCTAssertNotNil(jsonSchema["schema"] as? [String: Any])
        XCTAssertEqual(payload["max_completion_tokens"] as? Int, 4_096)
        XCTAssertNil(payload["max_tokens"])
        XCTAssertEqual(
            (payload["provider"] as? [String: Any])?["require_parameters"] as? Bool,
            true
        )
        XCTAssertEqual(
            ((payload["plugins"] as? [[String: Any]])?.first)?["id"] as? String,
            "response-healing"
        )
        XCTAssertEqual(
            (payload["reasoning"] as? [String: Any])?["effort"] as? String,
            "medium"
        )
    }

    func testStructuredDecoderAcceptsFencesAndSurroundingExplanation() throws {
        let value = """
        Here is the requested object:
        ```json
        {"title":"Ready","items":[1,2]}
        ```
        """
        let result: StructuredFixture = try LLMClient.decodeStructuredText(value)
        XCTAssertEqual(result, StructuredFixture(title: "Ready", items: [1, 2]))
    }

    func testStructuredDecoderAcceptsDoubleEncodedJSON() throws {
        let inner = #"{"title":"Ready","items":[1,2]}"#
        let encoded = try JSONEncoder().encode(inner)
        let result: StructuredFixture = try LLMClient.decodeStructuredText(
            try XCTUnwrap(String(data: encoded, encoding: .utf8))
        )
        XCTAssertEqual(result, StructuredFixture(title: "Ready", items: [1, 2]))
    }

    func testStructuredDecoderRepairsTrailingCommasAndLiteralNewlines() throws {
        let value = """
        {"title":"First
        Second","items":[1,2,],}
        """
        let result: StructuredFixture = try LLMClient.decodeStructuredText(value)
        XCTAssertEqual(result, StructuredFixture(title: "First\nSecond", items: [1, 2]))
    }

    func testStructuredDecoderIdentifiesTruncatedJSONWithoutAnotherRequest() {
        XCTAssertThrowsError(
            try LLMClient.decodeStructuredText(#"{"title":"Ready","items":[1,2"#) as StructuredFixture
        ) { error in
            guard case let ModelError.invalidJSON(detail) = error else {
                return XCTFail("Expected invalid JSON error, got \(error)")
            }
            XCTAssertTrue(detail.contains("可能被截断"))
        }
    }

    func testResponseDecoderReadsChatToolCallArguments() throws {
        let data = Data(#"{"choices":[{"message":{"tool_calls":[{"function":{"arguments":"{\"title\":\"Ready\",\"items\":[1,2]}"}}]}}]}"#.utf8)
        let result: StructuredFixture = try LLMClient.decodeResponseData(data)
        XCTAssertEqual(result, StructuredFixture(title: "Ready", items: [1, 2]))
    }

    func testResponseDecoderReadsResponsesToolArguments() throws {
        let data = Data(#"{"output":[{"type":"function_call","arguments":"{\"title\":\"Ready\",\"items\":[1,2]}"}]}"#.utf8)
        let result: StructuredFixture = try LLMClient.decodeResponseData(data)
        XCTAssertEqual(result, StructuredFixture(title: "Ready", items: [1, 2]))
    }

    func testResponseDecoderReadsObjectValuedChatContent() throws {
        let data = Data(#"{"choices":[{"message":{"content":{"title":"Ready","items":[1,2]}}}]}"#.utf8)
        let result: StructuredFixture = try LLMClient.decodeResponseData(data)
        XCTAssertEqual(result, StructuredFixture(title: "Ready", items: [1, 2]))
    }

    func testTruncatedChatErrorIncludesSafeCompletionMetadata() {
        let data = Data(#"{"choices":[{"finish_reason":"length","message":{"content":"{\"title\":\"Cut off\",\"items\":[1"}}],"usage":{"completion_tokens":4096}}"#.utf8)

        XCTAssertThrowsError(try LLMClient.decodeResponseData(data) as StructuredFixture) { error in
            guard case let ModelError.invalidJSON(detail) = error else {
                return XCTFail("Expected invalid JSON error, got \(error)")
            }
            XCTAssertTrue(detail.contains("finish_reason=length"))
            XCTAssertTrue(detail.contains("completion_tokens=4096"))
            XCTAssertFalse(detail.contains("Cut off"))
        }
    }

    func testIncompleteResponsesErrorIncludesSafeTerminationMetadata() {
        let data = Data(#"{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output":[{"content":[{"type":"output_text","text":"{\"title\":\"Cut off\""}]}],"usage":{"output_tokens":8192}}"#.utf8)

        XCTAssertThrowsError(try LLMClient.decodeResponseData(data) as StructuredFixture) { error in
            guard case let ModelError.invalidJSON(detail) = error else {
                return XCTFail("Expected invalid JSON error, got \(error)")
            }
            XCTAssertTrue(detail.contains("status=incomplete"))
            XCTAssertTrue(detail.contains("reason=max_output_tokens"))
            XCTAssertTrue(detail.contains("output_tokens=8192"))
            XCTAssertFalse(detail.contains("Cut off"))
        }
    }

    func testEmptyChatContentReportsSafeCompletionMetadataInsteadOfGenericMissingText() {
        let data = Data(#"{"choices":[{"finish_reason":"length","message":{"role":"assistant","content":"","reasoning":"private reasoning must not be shown"}}],"usage":{"completion_tokens":4096,"completion_tokens_details":{"reasoning_tokens":4096}}}"#.utf8)

        XCTAssertThrowsError(try LLMClient.decodeResponseData(data) as StructuredFixture) { error in
            guard case let ModelError.invalidJSON(detail) = error else {
                return XCTFail("Expected metadata-rich invalid JSON error, got \(error)")
            }
            XCTAssertTrue(detail.contains("finish_reason=length"))
            XCTAssertTrue(detail.contains("completion_tokens=4096"))
            XCTAssertTrue(detail.contains("reasoning_tokens=4096"))
            XCTAssertFalse(detail.contains("private reasoning"))
        }
    }
}
