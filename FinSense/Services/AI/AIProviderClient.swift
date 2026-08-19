import Foundation

enum AIMessageRole: String, Codable {
    case user
    case model
}

struct AIProviderMessage: Codable {
    let role: AIMessageRole
    let text: String
}

final class AIJSONSchema: Encodable {
    let type: String
    var description: String?
    var properties: [String: AIJSONSchema]?
    var items: AIJSONSchema?
    var required: [String]?
    var enumValues: [String]?
    var nullable: Bool?

    init(
        type: String,
        description: String? = nil,
        properties: [String: AIJSONSchema]? = nil,
        items: AIJSONSchema? = nil,
        required: [String]? = nil,
        enumValues: [String]? = nil,
        nullable: Bool? = nil
    ) {
        self.type = type
        self.description = description
        self.properties = properties
        self.items = items
        self.required = required
        self.enumValues = enumValues
        self.nullable = nullable
    }

    enum CodingKeys: String, CodingKey {
        case type
        case description
        case properties
        case items
        case required
        case enumValues = "enum"
        case nullable
    }

    static func string(
        description: String? = nil,
        values: [String]? = nil,
        nullable: Bool? = nil
    ) -> AIJSONSchema {
        AIJSONSchema(
            type: "STRING",
            description: description,
            enumValues: values,
            nullable: nullable
        )
    }

    static func integer(description: String? = nil) -> AIJSONSchema {
        AIJSONSchema(type: "INTEGER", description: description)
    }

    static func number(description: String? = nil) -> AIJSONSchema {
        AIJSONSchema(type: "NUMBER", description: description)
    }

    static func boolean(description: String? = nil) -> AIJSONSchema {
        AIJSONSchema(type: "BOOLEAN", description: description)
    }

    static func array(
        of items: AIJSONSchema,
        description: String? = nil
    ) -> AIJSONSchema {
        AIJSONSchema(type: "ARRAY", description: description, items: items)
    }

    static func object(
        properties: [String: AIJSONSchema],
        required: [String],
        description: String? = nil
    ) -> AIJSONSchema {
        AIJSONSchema(
            type: "OBJECT",
            description: description,
            properties: properties,
            required: required
        )
    }
}

struct AIProviderRequest {
    let systemInstruction: String
    let messages: [AIProviderMessage]
    let responseSchema: AIJSONSchema?
    let temperature: Double
    let maxOutputTokens: Int

    init(
        systemInstruction: String,
        messages: [AIProviderMessage],
        responseSchema: AIJSONSchema? = nil,
        temperature: Double = 0.2,
        maxOutputTokens: Int = 1_024
    ) {
        self.systemInstruction = systemInstruction
        self.messages = messages
        self.responseSchema = responseSchema
        self.temperature = temperature
        self.maxOutputTokens = maxOutputTokens
    }
}

struct AIProviderResponse {
    let text: String
    let promptTokenCount: Int?
    let responseTokenCount: Int?
}

protocol AIProviderClient {
    func generate(
        request: AIProviderRequest,
        apiKey: String,
        model: String
    ) async throws -> AIProviderResponse

    func stream(
        request: AIProviderRequest,
        apiKey: String,
        model: String
    ) -> AsyncThrowingStream<String, Error>
}

enum AIProviderError: LocalizedError {
    case missingAPIKey
    case authenticationFailed
    case quotaExceeded(retryAfter: TimeInterval?)
    case invalidRequest(String)
    case serverError(String)
    case invalidResponse
    case emptyResponse
    case cancelled
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add your selected AI provider's API key in Settings."
        case .authenticationFailed:
            return "The API key is invalid or no longer active."
        case .quotaExceeded(let retryAfter):
            if let retryAfter {
                return "The AI provider's quota is temporarily exhausted. Try again in \(Int(retryAfter.rounded(.up))) seconds."
            }
            return "The AI provider's quota is temporarily exhausted. Please try again later."
        case .invalidRequest(let message):
            return "The AI provider could not process this request: \(message)"
        case .serverError:
            return "The AI provider is temporarily unavailable. Please try again."
        case .invalidResponse:
            return "The AI provider returned an unreadable response."
        case .emptyResponse:
            return "The AI provider returned an empty response."
        case .cancelled:
            return "The response was cancelled."
        case .network:
            return "Could not reach the AI provider. Check your internet connection."
        }
    }
}
