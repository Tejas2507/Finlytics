import Foundation
import SwiftData
import SwiftUI

@MainActor
class InsightEngine {
    static let shared = InsightEngine()
    
    private init() {}
    
    // MARK: - Rich Financial Context
    struct FinancialContext {
        let topCategory: (name: String, amount: Double, percent: Int)
        let avgDailySpend: Double
        let highestExpense: (merchant: String, amount: Double)?
        let daysSinceInvestment: Int?
        let spendingTrend: Int // % change vs last month
        let daysLeftInMonth: Int
        let projectedMonthEnd: Double
        let totalThisMonth: Double
    }
    
    // MARK: - Build Context from Transactions
    func buildContext(from transactions: [Transaction]) -> FinancialContext {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let startOfLastMonth = calendar.date(byAdding: .month, value: -1, to: startOfMonth) ?? now
        
        // This month's expenses
        let thisMonthExpenses = transactions.filter { $0.date >= startOfMonth && $0.type == .expense }
        let lastMonthExpenses = transactions.filter { $0.date >= startOfLastMonth && $0.date < startOfMonth && $0.type == .expense }
        
        let thisMonthTotal = thisMonthExpenses.reduce(0) { $0 + $1.amount }
        let lastMonthTotal = lastMonthExpenses.reduce(0) { $0 + $1.amount }
        
        // Top category
        let grouped = Dictionary(grouping: thisMonthExpenses) { $0.category }
        let topCat = grouped.max(by: { $0.value.reduce(0) { $0 + $1.amount } < $1.value.reduce(0) { $0 + $1.amount } })
        let topCatAmount = topCat?.value.reduce(0) { $0 + $1.amount } ?? 0
        let topCatPercent = thisMonthTotal > 0 ? Int((topCatAmount / thisMonthTotal) * 100) : 0
        
        // Average daily spend
        let dayOfMonth = calendar.component(.day, from: now)
        let avgDaily = dayOfMonth > 0 ? thisMonthTotal / Double(dayOfMonth) : 0
        
        // Highest single expense
        let highest = thisMonthExpenses.max(by: { $0.amount < $1.amount })
        
        // Days since investment
        let investments = transactions.filter { $0.category.lowercased().contains("invest") && $0.type == .expense }
        let lastInvestment = investments.max(by: { $0.date < $1.date })
        let daysSinceInvest: Int? = lastInvestment.map { calendar.dateComponents([.day], from: $0.date, to: now).day ?? 0 }
        
        // Spending trend
        let trend = lastMonthTotal > 0 ? Int(((thisMonthTotal - lastMonthTotal) / lastMonthTotal) * 100) : 0
        
        // Days left & projection
        let range = calendar.range(of: .day, in: .month, for: now)
        let daysInMonth = range?.count ?? 30
        let daysLeft = daysInMonth - dayOfMonth
        let projected = avgDaily * Double(daysInMonth)
        
        return FinancialContext(
            topCategory: (topCat?.key ?? "Unknown", topCatAmount, topCatPercent),
            avgDailySpend: avgDaily,
            highestExpense: highest.map { ($0.merchant, $0.amount) },
            daysSinceInvestment: daysSinceInvest,
            spendingTrend: trend,
            daysLeftInMonth: daysLeft,
            projectedMonthEnd: projected,
            totalThisMonth: thisMonthTotal
        )
    }
    
    // MARK: - Check if New Insight Needed (6-hour rotation)
    private func shouldGenerateNewInsight() -> Bool {
        let lastTime = UserDefaults.standard.object(forKey: "lastInsightTime") as? Date ?? .distantPast
        let hoursSince = Calendar.current.dateComponents([.hour], from: lastTime, to: Date()).hour ?? 99
        return hoursSince >= 6
    }
    
    private func markInsightGenerated() {
        UserDefaults.standard.set(Date(), forKey: "lastInsightTime")
    }
    
    // MARK: - Main Fetch Method
    func fetchTodaysInsight(context: ModelContext, transactions: [Transaction], apiKey: String) async -> Insight? {
        // 1. Check for recent valid insight (within 6 hours)
        let descriptor = FetchDescriptor<Insight>(
            sortBy: [SortDescriptor(\.generatedDate, order: .reverse)]
        )
        
        do {
            let existingInsights = try context.fetch(descriptor)
            
            // Clean up error insights
            for insight in existingInsights {
                if insight.message.lowercased().contains("api key") || insight.message.lowercased().contains("configure") {
                    context.delete(insight)
                }
            }
            
            // Check if we have a valid recent insight
            if !shouldGenerateNewInsight(), let recent = existingInsights.first(where: { !$0.message.lowercased().contains("api key") }) {
                return recent
            }
        } catch {
            print("Error fetching insights: \(error)")
        }
        
        // 2. Generate new insight
        guard !transactions.isEmpty else {
            return Insight(
                title: "Welcome",
                message: "Add transactions to see personalized insights here!",
                category: .savingsTip,
                relevanceScore: 1.0
            )
        }
        
        guard !apiKey.isEmpty else {
            return nil // Don't show error, just hide insight
        }
        
        let financialContext = buildContext(from: transactions)
        
        do {
            let message = try await GeminiService.shared.generateSmartInsight(context: financialContext, apiKey: apiKey)
            
            // Validate response
            if message.lowercased().contains("api key") || message.isEmpty {
                return nil
            }
            
            let newInsight = Insight(
                title: "Insight",
                message: message,
                category: .savingsTip,
                relevanceScore: 1.0
            )
            
            context.insert(newInsight)
            markInsightGenerated()
            return newInsight
        } catch {
            print("Error generating insight: \(error)")
            return nil
        }
    }
}
