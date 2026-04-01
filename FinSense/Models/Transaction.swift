import Foundation
import SwiftData

enum TransactionType: String, Codable, CaseIterable {
    case income = "Income"
    case expense = "Expense"
}

@Model
class Transaction {
    var id: UUID
    var amount: Double
    var date: Date
    var merchant: String
    var notes: String
    var type: TransactionType
    var category: String
    var isHidden: Bool = false
    var projectNames: [String] = []
    
    init(amount: Double, date: Date = Date(), merchant: String, notes: String = "", type: TransactionType = .expense, category: String = "Uncategorized", isHidden: Bool = false) {
        self.id = UUID()
        self.amount = amount
        self.date = date
        self.merchant = merchant
        self.notes = notes
        self.type = type
        self.category = category
        self.isHidden = isHidden
    }
    
    // Smart Parsing Logic
    static func parse(from text: String) -> (amount: Double?, merchant: String?, type: TransactionType?) {
        // Simple regex heuristics for Indian finance SMS
        // e.g., "Rs 450 debited for Swiggy", "Credited Rs 10000 salary"
        
        let lowered = text.lowercased()
        var type: TransactionType = .expense
        if lowered.contains("credited") || lowered.contains("received") || lowered.contains("deposited") {
            type = .income
        }
        
        // Extract Amount (looks for patterns like Rs. 123, INR 123, 123.00)
        let amountPattern = "(?:Rs\\.?|INR|₹)\\s*([0-9,]+(?:\\.[0-9]{2})?)"
        var amount: Double? = nil
        if let regex = try? NSRegularExpression(pattern: amountPattern, options: .caseInsensitive) {
            if let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range(at: 1), in: text) {
                    let amountString = text[range].replacingOccurrences(of: ",", with: "")
                    amount = Double(amountString)
                }
            }
        }
        
        // Extract Merchant (very basic heuristic: look for 'at' or 'to' or 'from')
        var merchant: String? = nil
        let merchantPattern = "(?:at|to|from)\\s+([A-Za-z0-9 ]+?)(?:\\s+(?:on|via|ref|bal)|$)"
        if let regex = try? NSRegularExpression(pattern: merchantPattern, options: .caseInsensitive) {
            if let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range(at: 1), in: text) {
                    merchant = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        
        return (amount, merchant, type)
    }
}
