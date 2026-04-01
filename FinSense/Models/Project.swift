import Foundation
import SwiftData

@Model
class Project {
    var id: UUID
    var name: String
    var emoji: String
    var targetBudget: Double
    var dateCreated: Date
    var isArchived: Bool = false
    var isHidden: Bool = false
    
    init(name: String, emoji: String = "🎯", targetBudget: Double = 0, dateCreated: Date = Date(), isArchived: Bool = false) {
        self.id = UUID()
        self.name = name
        self.emoji = emoji
        self.targetBudget = targetBudget
        self.dateCreated = dateCreated
        self.isArchived = isArchived
    }
}
