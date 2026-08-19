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
        let secondCategory: (name: String, amount: Double, percent: Int)?  // NEW
        let avgDailySpend: Double
        let highestExpense: (merchant: String, amount: Double)?
        let daysSinceInvestment: Int?
        let spendingTrend: Int // % change vs last month
        let daysLeftInMonth: Int
        let projectedMonthEnd: Double
        let totalThisMonth: Double
        // NEW FIELDS
        let weekendSpend: Double
        let weekdaySpend: Double
        let mostFrequentMerchant: (name: String, count: Int)?
        let transactionCount: Int
        let avgTransactionSize: Double
        let incomeThisMonth: Double
        let savingsRate: Int  // (income - expenses) / income * 100
        let biggestSpendingDay: (day: String, amount: Double)?
        let projectStats: String // NEW: Pre-rendered project string
    }
    
    // MARK: - Dynamic Outlier Detection
    private func computeDynamicOutlierThreshold(for transactions: [Transaction]) -> Double {
        let expenses = transactions.filter { MonthlyStats.isSpending($0) }
        guard expenses.count > 2 else { return 15000.0 } // Default fallback if not enough data
        
        let mean = expenses.reduce(0) { $0 + $1.amount } / Double(expenses.count)
        let variance = expenses.reduce(0) { $0 + pow($1.amount - mean, 2.0) } / Double(expenses.count)
        let standardDeviation = sqrt(variance)
        
        // Outlier is anything more than mean + 2 standard deviations
        // Floor it at 5000 so small standard deviations don't catch normal expenses
        return max(5000.0, mean + (2 * standardDeviation))
    }
    
    // MARK: - Build Context from Transactions
    func buildContext(from transactions: [Transaction], projects: [Project]) -> FinancialContext {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let startOfLastMonth = calendar.date(byAdding: .month, value: -1, to: startOfMonth) ?? now
        
        // This month's expenses (spending only, exclude investments)
        let thisMonthExpenses = transactions.filter { $0.date >= startOfMonth && MonthlyStats.isSpending($0) }
        let lastMonthExpenses = transactions.filter { $0.date >= startOfLastMonth && $0.date < startOfMonth && MonthlyStats.isSpending($0) }
        let thisMonthIncome = transactions.filter { $0.date >= startOfMonth && $0.type == .income }
        
        let thisMonthTotal = thisMonthExpenses.reduce(0) { $0 + $1.amount }
        let lastMonthTotal = lastMonthExpenses.reduce(0) { $0 + $1.amount }
        let incomeTotal = thisMonthIncome.reduce(0) { $0 + $1.amount }
        
        // Dynamic Outlier Separation
        let outlierThreshold = computeDynamicOutlierThreshold(for: transactions)
        let thisMonthOutliers = thisMonthExpenses.filter { $0.amount > outlierThreshold }
        let thisMonthVariables = thisMonthExpenses.filter { $0.amount <= outlierThreshold }
        
        let outlierTotal = thisMonthOutliers.reduce(0) { $0 + $1.amount }
        let variableTotal = thisMonthVariables.reduce(0) { $0 + $1.amount }
        
        // Top categories (1st and 2nd)
        let grouped = Dictionary(grouping: thisMonthExpenses) { $0.category }
        let sortedCategories = grouped.map { ($0.key, $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.1 > $1.1 }
        
        let topCat = sortedCategories.first
        let topCatPercent = thisMonthTotal > 0 ? Int((topCat?.1 ?? 0) / thisMonthTotal * 100) : 0
        let secondCat = sortedCategories.count > 1 ? sortedCategories[1] : nil
        let secondCatPercent = thisMonthTotal > 0 && secondCat != nil ? Int(secondCat!.1 / thisMonthTotal * 100) : 0
        
        // Average daily spend (VARIABLE ONLY)
        let dayOfMonth = calendar.component(.day, from: now)
        let avgDaily = dayOfMonth > 0 ? variableTotal / Double(dayOfMonth) : 0
        
        // Highest single expense (VARIABLE ONLY - stop roasting rent!)
        let highest = thisMonthVariables.max(by: { $0.amount < $1.amount })
        
        // Days since investment
        let investments = transactions.filter { $0.category.lowercased().contains("invest") && $0.type == .expense }
        let lastInvestment = investments.max(by: { $0.date < $1.date })
        let daysSinceInvest: Int? = lastInvestment.map { calendar.dateComponents([.day], from: $0.date, to: now).day ?? 0 }
        
        // Spending trend
        let trend = lastMonthTotal > 0 ? Int(((thisMonthTotal - lastMonthTotal) / lastMonthTotal) * 100) : 0
        
        // Days left & projection (Projected Variables + Fixed Outliers)
        let range = calendar.range(of: .day, in: .month, for: now)
        let daysInMonth = range?.count ?? 30
        let daysLeft = daysInMonth - dayOfMonth
        let projected = (avgDaily * Double(daysInMonth)) + outlierTotal
        
        // NEW: Weekend vs Weekday spending
        let weekendExpenses = thisMonthExpenses.filter {
            let weekday = calendar.component(.weekday, from: $0.date)
            return weekday == 1 || weekday == 7 // Sunday = 1, Saturday = 7
        }
        let weekendTotal = weekendExpenses.reduce(0) { $0 + $1.amount }
        let weekdayTotal = thisMonthTotal - weekendTotal
        
        // NEW: Most frequent merchant
        let merchantCounts = Dictionary(grouping: thisMonthExpenses) { $0.merchant }
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
        let topMerchant = merchantCounts.first
        
        // NEW: Transaction stats
        let txCount = thisMonthExpenses.count
        let avgTxSize = txCount > 0 ? thisMonthTotal / Double(txCount) : 0
        
        // Savings rate: use monthlySalary from Settings - projected spending (not earned income)
        let monthlySalary = UserDefaults.standard.double(forKey: "monthlySalary")
        let savingsRate = monthlySalary > 0 ? Int(((monthlySalary - projected) / monthlySalary) * 100) : 0
        
        // NEW: Biggest spending day
        let dailySpending = Dictionary(grouping: thisMonthExpenses) { 
            calendar.startOfDay(for: $0.date) 
        }.mapValues { $0.reduce(0) { $0 + $1.amount } }
        let biggestDay = dailySpending.max(by: { $0.value < $1.value })
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE" // Day name
        let biggestDayName = biggestDay.map { dayFormatter.string(from: $0.key) }
        
        return FinancialContext(
            topCategory: (topCat?.0 ?? "Unknown", topCat?.1 ?? 0, topCatPercent),
            secondCategory: secondCat.map { ($0.0, $0.1, secondCatPercent) },
            avgDailySpend: avgDaily,
            highestExpense: highest.map { ($0.merchant, $0.amount) },
            daysSinceInvestment: daysSinceInvest,
            spendingTrend: trend,
            daysLeftInMonth: daysLeft,
            projectedMonthEnd: projected,
            totalThisMonth: thisMonthTotal,
            weekendSpend: weekendTotal,
            weekdaySpend: weekdayTotal,
            mostFrequentMerchant: topMerchant.map { ($0.key, $0.value) },
            transactionCount: txCount,
            avgTransactionSize: avgTxSize,
            incomeThisMonth: incomeTotal,
            savingsRate: savingsRate,
            biggestSpendingDay: biggestDay.map { (biggestDayName ?? "Unknown", $0.value) },
            projectStats: MerchantAnalytics.shared.buildProjectContext(transactions: transactions, projects: projects)
        )
    }
    
    // MARK: - Simple Cache System
    private let cacheMessageKey = "cachedInsightMessage"
    private let cacheTimestampKey = "cachedInsightTimestamp"
    private let cacheTitleKey = "cachedInsightTitle"
    
    private func getCachedInsight() -> (title: String, message: String)? {
        guard let message = UserDefaults.standard.string(forKey: cacheMessageKey),
              let title = UserDefaults.standard.string(forKey: cacheTitleKey),
              let timestamp = UserDefaults.standard.object(forKey: cacheTimestampKey) as? Date else {
            print("DEBUG CACHE: No cached insight found")
            return nil
        }
        
        let hoursSince = Calendar.current.dateComponents([.hour], from: timestamp, to: Date()).hour ?? 99
        print("DEBUG CACHE: Found cached insight from \(hoursSince) hours ago")
        
        if hoursSince < 4 {
            print("DEBUG CACHE: Cache is VALID (< 4 hours) - returning cached insight")
            return (title, message)
        } else {
            print("DEBUG CACHE: Cache EXPIRED (>= 4 hours) - will fetch new")
            clearCache()
            return nil
        }
    }
    
    private func saveToCache(title: String, message: String) {
        UserDefaults.standard.set(message, forKey: cacheMessageKey)
        UserDefaults.standard.set(title, forKey: cacheTitleKey)
        UserDefaults.standard.set(Date(), forKey: cacheTimestampKey)
        UserDefaults.standard.synchronize()
        print("DEBUG CACHE: Saved new insight to cache")
    }
    
    private func clearCache() {
        UserDefaults.standard.removeObject(forKey: cacheMessageKey)
        UserDefaults.standard.removeObject(forKey: cacheTitleKey)
        UserDefaults.standard.removeObject(forKey: cacheTimestampKey)
        UserDefaults.standard.synchronize()
    }
    
    // MARK: - Main Fetch Method
    func fetchTodaysInsight(context: ModelContext, transactions: [Transaction], apiKey: String) async -> Insight? {
        
        // STEP 1: Check cache FIRST - if valid, return immediately (NO API CALL)
        if let cached = getCachedInsight() {
            return Insight(
                title: cached.title,
                message: cached.message,
                category: .savingsTip,
                relevanceScore: 1.0
            )
        }
        
        // STEP 2: Cache empty or expired - generate new insight via API
        print("DEBUG: Making API call for new insight...")
        guard !transactions.isEmpty else {
            let welcomeInsight = Insight(
                title: "Welcome",
                message: "Add transactions to see personalized insights here!",
                category: .savingsTip,
                relevanceScore: 1.0
            )
            context.insert(welcomeInsight)
            try? context.save()
            print("DEBUG: Created Welcome insight")
            return welcomeInsight
        }
        
        guard !apiKey.isEmpty else {
            let setupInsight = Insight(
                title: "Setup",
                message: "Add your selected AI provider's API key in Settings to unlock AI-powered insights!",
                category: .savingsTip,
                relevanceScore: 1.0
            )
            context.insert(setupInsight)
            try? context.save()
            print("DEBUG: Created Setup insight")
            return setupInsight
        }
        
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        let financialContext = buildContext(from: transactions, projects: projects)
        
        do {
            // 70% chance for Personal Insight, 30% for General Tip
            let isPersonalized = Int.random(in: 1...100) <= 70 && financialContext.totalThisMonth > 0
            
            let message: String
            let category: InsightCategory
            
            print("DEBUG: Calling AI provider for \(isPersonalized ? "personalized" : "general") insight...")
            
            if isPersonalized {
                message = try await AIManager.shared.generateSmartInsight(context: financialContext)
                category = .optimization
            } else {
                message = try await AIManager.shared.generateGeneralTip()
                category = .savingsTip
            }
            
            print("DEBUG: Got response: \(message.prefix(50))...")
            
            // If empty response, create error insight instead of returning nil
            guard !message.isEmpty else {
                let emptyInsight = Insight(
                    title: "System",
                    message: "AI returned empty response. Try again later.",
                    category: .savingsTip,
                    relevanceScore: 0.0
                )
                context.insert(emptyInsight)
                try? context.save()
                return emptyInsight
            }
            
            let newInsight = Insight(
                title: isPersonalized ? "Insight" : "Tip",
                message: message,
                category: category,
                relevanceScore: 1.0
            )
            
            context.insert(newInsight)
            try? context.save()
            
            // SAVE TO CACHE for 4 hours
            let title = isPersonalized ? "Insight" : "Tip"
            saveToCache(title: title, message: message)
            
            print("DEBUG: Successfully created and cached insight: \(title)")
            return newInsight
        } catch {
            print("DEBUG: Error generating insight: \(error)")
            let errorInsight = Insight(
                title: "System",
                message: "Couldn't contact AI service. Please check your internet or API Key settings.",
                category: .savingsTip,
                relevanceScore: 0.0
            )
            context.insert(errorInsight)
            try? context.save()
            return errorInsight
        }
    }
}
