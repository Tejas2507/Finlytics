import Foundation
import SwiftData

enum FinSenseSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Transaction.self, Budget.self, Project.self]
    }

    @Model
    final class Transaction {
        var id: UUID
        var amount: Double
        var date: Date
        var merchant: String
        var notes: String
        var type: TransactionType
        var category: String
        var isHidden: Bool = false
        var projectNames: [String] = []

        init(
            amount: Double,
            date: Date = Date(),
            merchant: String,
            notes: String = "",
            type: TransactionType = .expense,
            category: String = "Uncategorized",
            isHidden: Bool = false
        ) {
            id = UUID()
            self.amount = amount
            self.date = date
            self.merchant = merchant
            self.notes = notes
            self.type = type
            self.category = category
            self.isHidden = isHidden
        }
    }

    @Model
    final class Budget {
        @Attribute(.unique) var category: String
        var monthlyLimit: Double
        var createdAt: Date

        init(category: String, monthlyLimit: Double) {
            self.category = category
            self.monthlyLimit = monthlyLimit
            createdAt = Date()
        }
    }

    @Model
    final class Project {
        var id: UUID
        var name: String
        var emoji: String
        var targetBudget: Double
        var dateCreated: Date
        var isArchived: Bool = false
        var isHidden: Bool = false

        init(
            name: String,
            emoji: String = "🎯",
            targetBudget: Double = 0,
            dateCreated: Date = Date(),
            isArchived: Bool = false
        ) {
            id = UUID()
            self.name = name
            self.emoji = emoji
            self.targetBudget = targetBudget
            self.dateCreated = dateCreated
            self.isArchived = isArchived
        }
    }
}

enum FinSenseSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Transaction.self,
            Budget.self,
            Project.self,
            Insight.self,
            MerchantProfile.self,
            ChatThread.self,
            ChatMessage.self
        ]
    }
}

enum FinSenseMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [FinSenseSchemaV1.self, FinSenseSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: FinSenseSchemaV1.self,
        toVersion: FinSenseSchemaV2.self
    )
}
