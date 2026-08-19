import Foundation
import SwiftData

enum ChatMode: String, Codable, CaseIterable {
    case financial
    case help
}

extension FinSenseSchemaV2 {
@Model
final class ChatThread {
    @Attribute(.unique) var id: UUID
    var title: String
    var modeRawValue: String
    var createdAt: Date
    var updatedAt: Date
    var rollingSummary: String
    var summaryThroughDate: Date?
    var lastQueryData: Data?
    var isArchived: Bool

    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.thread)
    var messages: [ChatMessage]

    init(
        id: UUID = UUID(),
        title: String = "New chat",
        mode: ChatMode = .financial,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        rollingSummary: String = "",
        summaryThroughDate: Date? = nil,
        lastQueryData: Data? = nil,
        isArchived: Bool = false,
        messages: [ChatMessage] = []
    ) {
        self.id = id
        self.title = title
        self.modeRawValue = mode.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.rollingSummary = rollingSummary
        self.summaryThroughDate = summaryThroughDate
        self.lastQueryData = lastQueryData
        self.isArchived = isArchived
        self.messages = messages
    }

    var mode: ChatMode {
        get { ChatMode(rawValue: modeRawValue) ?? .financial }
        set { modeRawValue = newValue.rawValue }
    }

    var lastQuery: FinanceQuery? {
        get {
            guard let lastQueryData else { return nil }
            return try? JSONDecoder().decode(FinanceQuery.self, from: lastQueryData)
        }
        set {
            if let newValue {
                lastQueryData = try? JSONEncoder().encode(newValue)
            } else {
                lastQueryData = nil
            }
        }
    }

    func touch(at date: Date = Date()) {
        updatedAt = date
    }
}
}

typealias ChatThread = FinSenseSchemaV2.ChatThread
