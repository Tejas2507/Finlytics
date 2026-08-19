import Foundation

final class OpenAIProviderAdapter: AIProviderClient {
    static let shared = OpenAIProviderAdapter()

    private init() {}

    func generate(
        request: AIProviderRequest,
        apiKey: String,
        model: String
    ) async throws -> AIProviderResponse {
        guard !apiKey.isEmpty else { throw AIProviderError.missingAPIKey }
        UserDefaults.standard.set(model, forKey: "aiModel")

        var prompt = request.systemInstruction
        if let responseSchema = request.responseSchema,
           let schemaData = try? JSONEncoder().encode(responseSchema),
           let schemaText = String(data: schemaData, encoding: .utf8) {
            prompt += """

            Return only JSON conforming to this schema:
            \(schemaText)
            """
        }
        prompt += "\n\n## Conversation\n"
        prompt += request.messages.map {
            "\($0.role == .user ? "User" : "Assistant"): \($0.text)"
        }.joined(separator: "\n")

        let text = try await OpenAIService.shared.generateContent(
            apiKey: apiKey,
            systemPrompt: prompt
        )
        return AIProviderResponse(
            text: text,
            promptTokenCount: nil,
            responseTokenCount: nil
        )
    }

    func stream(
        request: AIProviderRequest,
        apiKey: String,
        model: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let response = try await generate(
                        request: request,
                        apiKey: apiKey,
                        model: model
                    )
                    continuation.yield(response.text)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
