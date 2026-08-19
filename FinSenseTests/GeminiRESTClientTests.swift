import Foundation
import XCTest
@testable import FinSense

final class GeminiRESTClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    @MainActor
    func testAuthenticationFailureIsTypedAndNotRetried() async throws {
        var requestCount = 0
        MockURLProtocol.handler = { request in
            requestCount += 1
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(#"{"error":{"message":"bad key"}}"#.utf8))
        }
        let client = GeminiRESTClient(
            session: makeSession(),
            maximumAttempts: 3,
            sleeper: { _ in }
        )

        do {
            _ = try await client.generate(
                request: request,
                apiKey: "invalid",
                model: GeminiRESTClient.defaultModel
            )
            XCTFail("Expected authentication failure")
        } catch AIProviderError.authenticationFailed {
            XCTAssertEqual(requestCount, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testTransientFailuresRetryThenReturnResponse() async throws {
        var requestCount = 0
        MockURLProtocol.handler = { request in
            requestCount += 1
            if requestCount == 1 {
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 429,
                        httpVersion: nil,
                        headerFields: ["Retry-After": "0"]
                    )!,
                    Data(#"{"error":{"message":"quota"}}"#.utf8)
                )
            }
            if requestCount == 2 {
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 503,
                        httpVersion: nil,
                        headerFields: nil
                    )!,
                    Data(#"{"error":{"message":"unavailable"}}"#.utf8)
                )
            }
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(
                    #"""
                    {
                      "candidates": [
                        {"content": {"parts": [{"text": "verified"}]}}
                      ],
                      "usageMetadata": {
                        "promptTokenCount": 5,
                        "candidatesTokenCount": 1
                      }
                    }
                    """#.utf8
                )
            )
        }
        let client = GeminiRESTClient(
            session: makeSession(),
            maximumAttempts: 3,
            sleeper: { _ in }
        )

        let response = try await client.generate(
            request: request,
            apiKey: "test-key",
            model: GeminiRESTClient.defaultModel
        )

        XCTAssertEqual(response.text, "verified")
        XCTAssertEqual(response.promptTokenCount, 5)
        XCTAssertEqual(requestCount, 3)
    }

    @MainActor
    func testStreamingParsesIncrementalSSEChunks() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            let body = """
            data: {"candidates":[{"content":{"parts":[{"text":"Hello "}]}}]}

            data: {"candidates":[{"content":{"parts":[{"text":"world"}]}}]}

            data: [DONE]

            """
            return (response, Data(body.utf8))
        }
        let client = GeminiRESTClient(
            session: makeSession(),
            maximumAttempts: 1,
            sleeper: { _ in }
        )

        var chunks: [String] = []
        for try await chunk in client.stream(
            request: request,
            apiKey: "test-key",
            model: GeminiRESTClient.defaultModel
        ) {
            chunks.append(chunk)
        }

        XCTAssertEqual(chunks, ["Hello ", "world"])
    }

    @MainActor
    func testCancellationDuringRetryBackoffMapsToTypedCancellation() async {
        MockURLProtocol.handler = { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 429,
                    httpVersion: nil,
                    headerFields: ["Retry-After": "0"]
                )!,
                Data(#"{"error":{"message":"quota"}}"#.utf8)
            )
        }
        let client = GeminiRESTClient(
            session: makeSession(),
            maximumAttempts: 3,
            sleeper: { _ in throw CancellationError() }
        )

        do {
            _ = try await client.generate(
                request: request,
                apiKey: "test-key",
                model: GeminiRESTClient.defaultModel
            )
            XCTFail("Expected cancellation")
        } catch AIProviderError.cancelled {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testStreamingRetriesQuotaFailureBeforeEmittingText() async throws {
        var requestCount = 0
        MockURLProtocol.handler = { request in
            requestCount += 1
            if requestCount == 1 {
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 429,
                        httpVersion: nil,
                        headerFields: ["Retry-After": "0"]
                    )!,
                    Data(#"{"error":{"message":"quota"}}"#.utf8)
                )
            }
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/event-stream"]
                )!,
                Data(
                    "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"ready\"}]}}]}\n\n"
                        .utf8
                )
            )
        }
        let client = GeminiRESTClient(
            session: makeSession(),
            maximumAttempts: 2,
            sleeper: { _ in }
        )

        var output = ""
        for try await chunk in client.stream(
            request: request,
            apiKey: "test-key",
            model: GeminiRESTClient.defaultModel
        ) {
            output += chunk
        }

        XCTAssertEqual(output, "ready")
        XCTAssertEqual(requestCount, 2)
    }

    @MainActor
    private var request: AIProviderRequest {
        AIProviderRequest(
            systemInstruction: "Return a short answer.",
            messages: [AIProviderMessage(role: .user, text: "Hello")]
        )
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
