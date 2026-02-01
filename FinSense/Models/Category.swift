import Foundation
import SwiftUI

struct Category {
    static let expenseCategories = [
        "Food & Dining",
        "Shopping",
        "Transportation",
        "Entertainment",
        "Bills & Utilities",
        "Healthcare",
        "Education",
        "Personal Care",
        "Travel",
        "Investment",
        "Gift",
        "Other"
    ]
    
    static let incomeCategories = [
        "Salary",
        "Freelance",
        "Business",
        "Investment",
        "Gift",
        "Other"
    ]
    
    static func color(for category: String) -> Color {
        switch category {
        case "Food & Dining": return .orange
        case "Shopping": return .pink
        case "Transportation": return .blue
        case "Entertainment": return .purple
        case "Bills & Utilities": return .red
        case "Healthcare": return .mint
        case "Salary": return .green
        case "Freelance": return .teal
        case "Investment": return .green
        case "Gift": return .yellow
        default: return .gray
        }
    }
    
    static func icon(for category: String) -> String {
        switch category {
        case "Food & Dining": return "fork.knife"
        case "Shopping": return "bag.fill"
        case "Transportation": return "car.fill"
        case "Entertainment": return "tv.fill"
        case "Bills & Utilities": return "bolt.fill"
        case "Healthcare": return "cross.case.fill"
        case "Salary": return "banknote.fill"
        case "Investment": return "chart.line.uptrend.xyaxis"
        case "Gift": return "gift.fill"
        default: return "tag.fill"
        }
    }
}
