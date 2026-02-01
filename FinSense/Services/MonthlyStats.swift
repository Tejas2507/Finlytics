import Foundation
import SwiftData

/// Helper for monthly statistics calculations - reused by budget generator and ThisMonthSheet
@MainActor
class MonthlyStats {
    static let shared = MonthlyStats()
    private init() {}
    
    /// Check if a transaction is spending (expense but not investment)
    /// nonisolated so it can be called from any context
    nonisolated static func isSpending(_ tx: Transaction) -> Bool {
        tx.type == .expense && !tx.category.lowercased().contains("invest")
    }
    
    /// Get all distinct months that have transaction data
    func getMonthsWithData(from transactions: [Transaction]) -> [Date] {
        let calendar = Calendar.current
        let spending = transactions.filter { MonthlyStats.isSpending($0) }
        
        let months = Set(spending.compactMap { tx -> Date? in
            calendar.date(from: calendar.dateComponents([.year, .month], from: tx.date))
        })
        
        return months.sorted(by: >)  // Most recent first
    }
    
    /// Get category averages per actual calendar month (excludes investments)
    func getCategoryMonthlyAverages(from transactions: [Transaction]) -> [(category: String, monthlyAvg: Double, totalTxns: Int)] {
        let calendar = Calendar.current
        let spending = transactions.filter { MonthlyStats.isSpending($0) }
        guard !spending.isEmpty else { return [] }
        
        // Group all spending by calendar month
        let byMonth = Dictionary(grouping: spending) { tx in
            calendar.date(from: calendar.dateComponents([.year, .month], from: tx.date)) ?? tx.date
        }
        let monthCount = max(1, byMonth.keys.count)
        
        // Group by category and calculate monthly average
        let byCategory = Dictionary(grouping: spending) { $0.category }
        
        return byCategory.map { category, txns in
            let total = txns.reduce(0) { $0 + $1.amount }
            let monthlyAvg = total / Double(monthCount)
            return (category: category, monthlyAvg: monthlyAvg, totalTxns: txns.count)
        }.sorted { $0.monthlyAvg > $1.monthlyAvg }
    }
    
    /// Get overall monthly average spending (excludes investments)
    func getOverallMonthlyAverage(from transactions: [Transaction]) -> Double {
        let calendar = Calendar.current
        let spending = transactions.filter { MonthlyStats.isSpending($0) }
        guard !spending.isEmpty else { return 0 }
        
        let byMonth = Dictionary(grouping: spending) { tx in
            calendar.date(from: calendar.dateComponents([.year, .month], from: tx.date)) ?? tx.date
        }
        let monthCount = max(1, byMonth.keys.count)
        let total = spending.reduce(0) { $0 + $1.amount }
        
        return total / Double(monthCount)
    }
    
    /// Get transactions for a specific month
    func getTransactions(for month: Date, from transactions: [Transaction]) -> [Transaction] {
        let calendar = Calendar.current
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        guard let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) else {
            return []
        }
        
        return transactions.filter { $0.date >= startOfMonth && $0.date < endOfMonth }
    }
    
    /// Get spending for a specific month (excludes investments)
    func getSpending(for month: Date, from transactions: [Transaction]) -> [Transaction] {
        getTransactions(for: month, from: transactions).filter { MonthlyStats.isSpending($0) }
    }
    
    /// Get category breakdown for a specific month (excludes investments)
    func getCategoryBreakdown(for month: Date, from transactions: [Transaction]) -> [(name: String, amount: Double)] {
        let spending = getSpending(for: month, from: transactions)
        
        let grouped = Dictionary(grouping: spending) { $0.category }
        return grouped.map { (name: $0.key, amount: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.amount > $1.amount }
    }
    
    /// Format month for display (e.g., "January 2026")
    func formatMonth(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
    
    /// Format short month (e.g., "Jan")
    func formatShortMonth(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: date)
    }
}
