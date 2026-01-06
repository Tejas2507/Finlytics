import Foundation
import SwiftData

enum InsightCategory: String, Codable {
    case forecast
    case optimization
    case anomaly
    case savingsTip
}

@Model
class Insight {
    var id: String = UUID().uuidString
    var title: String
    var message: String
    var category: InsightCategory
    var generatedDate: Date = Date()
    var isRead: Bool = false
    var relevanceScore: Double
    
    init(title: String, message: String, category: InsightCategory, relevanceScore: Double) {
        self.title = title
        self.message = message
        self.category = category
        self.relevanceScore = relevanceScore
    }
}
