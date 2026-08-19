import Foundation
import SwiftData

extension FinSenseSchemaV2 {
@Model
final class Budget {
    @Attribute(.unique) var category: String
    var monthlyLimit: Double
    var createdAt: Date
    
    init(category: String, monthlyLimit: Double) {
        self.category = category
        self.monthlyLimit = monthlyLimit
        self.createdAt = Date()
    }
}
}

typealias Budget = FinSenseSchemaV2.Budget
