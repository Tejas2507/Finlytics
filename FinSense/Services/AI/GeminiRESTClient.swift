import Foundation

final class GeminiRESTClient: AIProviderClient {
    static let shared = GeminiRESTClient()
    static let defaultModel = "gemini-3.1-flash-lite"

    private let session: URLSession
    private let maximumAttempts: Int
    private let sleeper: (TimeInterval) async throws -> Void

    init(
        session: URLSession = .shared,
        maximumAttempts: Int = 3,
        sleeper: @escaping (TimeInterval) async throws -> Void = { delay in
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    ) {
        self.session = session
        self.maximumAttempts = max(1, maximumAttempts)
        self.sleeper = sleeper
    }

    func generate(
        request: AIProviderRequest,
        apiKey: String,
        model: String
    ) async throws -> AIProviderResponse {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIProviderError.missingAPIKey
        }

        var attempt = 0
        while true {
            do {
                return try await generateOnce(
                    request: request,
                    apiKey: apiKey,
                    model: Self.normalizedModel(model)
                )
            } catch is CancellationError {
                throw AIProviderError.cancelled
            } catch let error as AIProviderError {
                attempt += 1
                guard attempt < maximumAttempts, shouldRetry(error) else {
                    throw error
                }
                do {
                    try await sleepBeforeRetry(error: error, attempt: attempt)
                } catch is CancellationError {
                    throw AIProviderError.cancelled
                }
            } catch {
                attempt += 1
                guard attempt < maximumAttempts else {
                    throw AIProviderError.network(error)
                }
                do {
                    try await sleepBeforeRetry(error: nil, attempt: attempt)
                } catch is CancellationError {
                    throw AIProviderError.cancelled
                }
            }
        }
    }

    func stream(
        request: AIProviderRequest,
        apiKey: String,
        model: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continuation.finish(throwing: AIProviderError.missingAPIKey)
                    return
                }

                var attempt = 0
                while attempt < maximumAttempts {
                    var emittedText = false
                    do {
                        let urlRequest = try makeURLRequest(
                            providerRequest: request,
                            apiKey: apiKey,
                            model: Self.normalizedModel(model),
                            streaming: true
                        )
                        let (bytes, response) = try await session.bytes(for: urlRequest)
                        guard let httpResponse = response as? HTTPURLResponse else {
                            throw AIProviderError.invalidResponse
                        }
                        guard (200...299).contains(httpResponse.statusCode) else {
                            var errorData = Data()
                            for try await byte in bytes {
                                errorData.append(byte)
                            }
                            let envelope = try? JSONDecoder().decode(
                                GeminiErrorEnvelope.self,
                                from: errorData
                            )
                            throw mapHTTPError(
                                statusCode: httpResponse.statusCode,
                                message: envelope?.error.message
                                    ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode),
                                retryAfter: retryAfter(from: httpResponse)
                            )
                        }

                        for try await line in bytes.lines {
                            try Task.checkCancellation()
                            guard line.hasPrefix("data:") else { continue }
                            let payload = String(line.dropFirst(5))
                                .trimmingCharacters(in: .whitespaces)
                            guard payload != "[DONE]", let data = payload.data(using: .utf8) else {
                                continue
                            }
                            let chunk = try JSONDecoder().decode(GeminiResponse.self, from: data)
                            let text = chunk.text
                            if !text.isEmpty {
                                emittedText = true
                                continuation.yield(text)
                            }
                        }

                        if !emittedText {
                            throw AIProviderError.emptyResponse
                        }
                        continuation.finish()
                        return
                    } catch is CancellationError {
                        continuation.finish(throwing: AIProviderError.cancelled)
                        return
                    } catch let error as AIProviderError {
                        attempt += 1
                        guard !emittedText, attempt < maximumAttempts, shouldRetry(error) else {
                            continuation.finish(throwing: error)
                            return
                        }
                        do {
                            try await sleepBeforeRetry(error: error, attempt: attempt)
                        } catch {
                            continuation.finish(throwing: AIProviderError.cancelled)
                            return
                        }
                    } catch {
                        attempt += 1
                        guard !emittedText, attempt < maximumAttempts else {
                            continuation.finish(throwing: AIProviderError.network(error))
                            return
                        }
                        do {
                            try await sleepBeforeRetry(error: nil, attempt: attempt)
                        } catch {
                            continuation.finish(throwing: AIProviderError.cancelled)
                            return
                        }
                    }
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    static func normalizedModel(_ model: String) -> String {
        let retiredNames: Set<String> = [
            "gemini-flash-lite-latest",
            "gemini-flash-latest",
            "gemini-2.0-flash-lite",
            "gemini-2.0-flash"
        ]
        return retiredNames.contains(model) || model.isEmpty ? defaultModel : model
    }

    private func generateOnce(
        request: AIProviderRequest,
        apiKey: String,
        model: String
    ) async throws -> AIProviderResponse {
        let urlRequest = try makeURLRequest(
            providerRequest: request,
            apiKey: apiKey,
            model: model,
            streaming: false
        )
        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let envelope = try? JSONDecoder().decode(GeminiErrorEnvelope.self, from: data)
            throw mapHTTPError(
                statusCode: httpResponse.statusCode,
                message: envelope?.error.message ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode),
                retryAfter: retryAfter(from: httpResponse)
            )
        }

        let responseBody = try JSONDecoder().decode(GeminiResponse.self, from: data)
        let text = responseBody.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw AIProviderError.emptyResponse
        }
        return AIProviderResponse(
            text: text,
            promptTokenCount: responseBody.usageMetadata?.promptTokenCount,
            responseTokenCount: responseBody.usageMetadata?.candidatesTokenCount
        )
    }

    private func makeURLRequest(
        providerRequest: AIProviderRequest,
        apiKey: String,
        model: String,
        streaming: Bool
    ) throws -> URLRequest {
        let action = streaming ? "streamGenerateContent" : "generateContent"
        let suffix = streaming ? "?alt=sse" : ""
        guard let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(
                string: "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModel):\(action)\(suffix)"
              ) else {
            throw AIProviderError.invalidRequest("Invalid model name.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(GeminiRequest(providerRequest))
        return request
    }

    private func shouldRetry(_ error: AIProviderError) -> Bool {
        switch error {
        case .quotaExceeded, .serverError, .network:
            return true
        case .missingAPIKey, .authenticationFailed, .invalidRequest,
             .invalidResponse, .emptyResponse, .cancelled:
            return false
        }
    }

    private func sleepBeforeRetry(
        error: AIProviderError?,
        attempt: Int
    ) async throws {
        let retryAfter: TimeInterval?
        if let error, case .quotaExceeded(let value) = error {
            retryAfter = value
        } else {
            retryAfter = nil
        }
        let exponential = min(pow(2, Double(attempt - 1)), 8)
        let jitter = Double.random(in: 0...0.4)
        let delay = max(retryAfter ?? 0, exponential + jitter)
        do {
            try await sleeper(delay)
        } catch is CancellationError {
            throw AIProviderError.cancelled
        }
    }

    private func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }
        if let seconds = TimeInterval(value) {
            return seconds
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        guard let date = formatter.date(from: value) else { return nil }
        return max(0, date.timeIntervalSinceNow)
    }

    private func mapHTTPError(
        statusCode: Int,
        message: String,
        retryAfter: TimeInterval?
    ) -> AIProviderError {
        switch statusCode {
        case 400:
            return .invalidRequest(message)
        case 401, 403:
            return .authenticationFailed
        case 429:
            return .quotaExceeded(retryAfter: retryAfter)
        case 500...599:
            return .serverError(message)
        default:
            return .invalidRequest(message)
        }
    }
}

private struct GeminiRequest: Encodable {
    let systemInstruction: GeminiContent
    let contents: [GeminiContent]
    let generationConfig: GeminiGenerationConfig

    init(_ request: AIProviderRequest) {
        systemInstruction = GeminiContent(role: nil, parts: [GeminiPart(text: request.systemInstruction)])
        contents = request.messages.map {
            GeminiContent(role: $0.role.rawValue, parts: [GeminiPart(text: $0.text)])
        }
        generationConfig = GeminiGenerationConfig(
            temperature: request.temperature,
            maxOutputTokens: request.maxOutputTokens,
            responseMimeType: request.responseSchema == nil ? nil : "application/json",
            responseSchema: request.responseSchema
        )
    }
}

private struct GeminiContent: Codable {
    let role: String?
    let parts: [GeminiPart]
}

private struct GeminiPart: Codable {
    let text: String?
}

private struct GeminiGenerationConfig: Encodable {
    let temperature: Double
    let maxOutputTokens: Int
    let responseMimeType: String?
    let responseSchema: AIJSONSchema?
}

private struct GeminiResponse: Decodable {
    let candidates: [GeminiCandidate]?
    let usageMetadata: GeminiUsageMetadata?

    var text: String {
        candidates?
            .first?
            .content
            .parts
            .compactMap(\.text)
            .joined() ?? ""
    }
}

private struct GeminiCandidate: Decodable {
    let content: GeminiResponseContent
}

private struct GeminiResponseContent: Decodable {
    let parts: [GeminiResponsePart]
}

private struct GeminiResponsePart: Decodable {
    let text: String?
}

private struct GeminiUsageMetadata: Decodable {
    let promptTokenCount: Int?
    let candidatesTokenCount: Int?
}

private struct GeminiErrorEnvelope: Decodable {
    let error: GeminiAPIError
}

private struct GeminiAPIError: Decodable {
    let message: String
}
