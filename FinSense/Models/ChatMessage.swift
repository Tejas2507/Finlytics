import Foundation
import SwiftData

enum ChatRole: String, Codable {
    case user
    case assistant
    case system
}

enum ChatDeliveryStatus: String, Codable {
    case pending
    case streaming
    case completed
    case failed
    case cancelled
    case superseded
}

extension FinSenseSchemaV2 {
@Model
final class ChatMessage {
    @Attribute(.unique) var id: UUID
    var roleRawValue: String
    var content: String
    var createdAt: Date
    var statusRawValue: String
    var provider: String?
    var model: String?
    var errorCode: String?
    var errorMessage: String?
    var replyToMessageID: UUID?
    var regenerationGroupID: UUID?
    var queryPlanData: Data?
    var evidenceData: Data?
    var promptTokenCount: Int?
    var responseTokenCount: Int?
    var thread: ChatThread?

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        createdAt: Date = Date(),
        status: ChatDeliveryStatus = .completed,
        provider: String? = nil,
        model: String? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil,
        replyToMessageID: UUID? = nil,
        regenerationGroupID: UUID? = nil,
        queryPlanData: Data? = nil,
        evidenceData: Data? = nil,
        promptTokenCount: Int? = nil,
        responseTokenCount: Int? = nil,
        thread: ChatThread? = nil
    ) {
        self.id = id
        self.roleRawValue = role.rawValue
        self.content = content
        self.createdAt = createdAt
        self.statusRawValue = status.rawValue
        self.provider = provider
        self.model = model
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.replyToMessageID = replyToMessageID
        self.regenerationGroupID = regenerationGroupID
        self.queryPlanData = queryPlanData
        self.evidenceData = evidenceData
        self.promptTokenCount = promptTokenCount
        self.responseTokenCount = responseTokenCount
        self.thread = thread
    }

    var role: ChatRole {
        get { ChatRole(rawValue: roleRawValue) ?? .assistant }
        set { roleRawValue = newValue.rawValue }
    }

    var status: ChatDeliveryStatus {
        get { ChatDeliveryStatus(rawValue: statusRawValue) ?? .completed }
        set { statusRawValue = newValue.rawValue }
    }

    var queryPlan: FinanceQueryPlan? {
        get {
            guard let queryPlanData else { return nil }
            return try? JSONDecoder().decode(FinanceQueryPlan.self, from: queryPlanData)
        }
        set {
            if let newValue {
                queryPlanData = try? JSONEncoder().encode(newValue)
            } else {
                queryPlanData = nil
            }
        }
    }

    var evidence: FinanceQueryResult? {
        get {
            guard let evidenceData else { return nil }
            return try? JSONDecoder().decode(FinanceQueryResult.self, from: evidenceData)
        }
        set {
            if let newValue {
                evidenceData = try? JSONEncoder().encode(newValue)
            } else {
                evidenceData = nil
            }
        }
    }
}
}

typealias ChatMessage = FinSenseSchemaV2.ChatMessage
