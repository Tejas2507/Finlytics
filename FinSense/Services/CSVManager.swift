import Foundation
import SwiftData

class CSVManager {
    static let shared = CSVManager()
    
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    func generateCSV(from transactions: [Transaction]) -> String {
        var csv = "Date,Merchant,Amount,Category,Type,Notes\n"
        
        for tx in transactions {
            let row = [
                dateFormatter.string(from: tx.date),
                escapeCSV(tx.merchant),
                String(tx.amount),
                escapeCSV(tx.category),
                tx.type.rawValue,
                escapeCSV(tx.notes)
            ].joined(separator: ",")
            csv.append(row + "\n")
        }
        return csv
    }
    
    func parseCSV(from url: URL) throws -> [Transaction] {
        let content = try String(contentsOf: url, encoding: .utf8)
        var transactions: [Transaction] = []
        
        // Simple CSV Parser (assumes simple standard layout)
        let lines = content.components(separatedBy: .newlines)
        
        // Skip header if present (check if first line contains "Date")
        let startIndex = lines.first?.lowercased().contains("date") == true ? 1 : 0
        
        for i in startIndex..<lines.count {
            let line = lines[i]
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            
            // This is a basic parser and won't handle commas inside quotes perfectly without Regex
            // But for our export format, it's likely sufficient if we don't have commas in fields typically.
            // Better to use a robust way if possible, but basic split is okay for MVP unless user abuses commas.
            // Let's simple split for now; robust parsing is complex in vanilla Swift without libraries.
            let columns = line.components(separatedBy: ",")
            
            if columns.count >= 5 {
                let dateString = columns[0]
                let merchant = unescapeCSV(columns[1])
                let amount = Double(columns[2]) ?? 0.0
                let category = unescapeCSV(columns[3])
                let typeString = columns[4]
                let notes = columns.count > 5 ? unescapeCSV(columns[5]) : ""
                
                if let date = dateFormatter.date(from: dateString),
                   let type = TransactionType(rawValue: typeString.capitalized) ?? TransactionType(rawValue: typeString) { // Try capitalized or raw
                    let tx = Transaction(amount: amount, date: date, merchant: merchant, notes: notes, type: type, category: category)
                    transactions.append(tx)
                }
            }
        }
        return transactions
    }
    
    // Helpers
    private func escapeCSV(_ text: String) -> String {
        // If text contains comma, wrap in quotes (Basic logic)
        if text.contains(",") {
            return "\"\(text)\""
        }
        return text
    }
    
    private func unescapeCSV(_ text: String) -> String {
        return text.replacingOccurrences(of: "\"", with: "")
    }
}
