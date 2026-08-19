import Foundation
import SwiftData

extension FinSenseSchemaV2 {
@Model
final class MerchantProfile {
    @Attribute(.unique) var canonicalKey: String
    var displayName: String
    var aliases: [String]
    var tags: [String]
    var defaultCategory: String?
    var confidence: Double
    var isUserOverride: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        canonicalKey: String,
        displayName: String,
        aliases: [String] = [],
        tags: [String] = [],
        defaultCategory: String? = nil,
        confidence: Double = 1,
        isUserOverride: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.canonicalKey = canonicalKey
        self.displayName = displayName
        self.aliases = aliases
        self.tags = tags
        self.defaultCategory = defaultCategory
        self.confidence = confidence
        self.isUserOverride = isUserOverride
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
}

typealias MerchantProfile = FinSenseSchemaV2.MerchantProfile
