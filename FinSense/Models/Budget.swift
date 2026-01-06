import Foundation
import SwiftData

@Model
class Budget {
    @Attribute(.unique) var category: String
    var monthlyLimit: Double
    var createdAt: Date
    
    init(category: String, monthlyLimit: Double) {
        self.category = category
        self.monthlyLimit = monthlyLimit
        self.createdAt = Date()
    }
}
