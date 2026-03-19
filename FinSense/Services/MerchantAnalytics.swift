import Foundation

/// Pre-computes rich per-merchant and per-category analytics from raw transactions.
/// Zero API cost — all done on-device.
class MerchantAnalytics {
    static let shared = MerchantAnalytics()
    private init() {}
    
    // MARK: - Data Structures
    
    struct MerchantStats {
        let name: String
        let totalSpent: Double
        let visitCount: Int
        let avgPerVisit: Double
        let avgMonthlySpend: Double
        let lastVisitDate: Date
        let primaryCategory: String
        let monthlyBreakdown: [(month: String, amount: Double)] // last 3 months
    }
    
    struct CategoryStats {
        let name: String
        let totalSpent: Double
        let avgMonthly: Double
        let transactionCount: Int
        let topMerchant: String
        let monthOverMonthTrend: Double // percentage change
        let monthlyBreakdown: [(month: String, amount: Double)] // last 3 months
    }
    
    struct MonthStats {
        let label: String // "Jan 2026"
        let totalSpent: Double
        let totalIncome: Double
        let savings: Double
        let topMerchant: String
        let topCategory: String
    }
    
    // MARK: - Compute Analytics
    
    func computeMerchantStats(from transactions: [Transaction]) -> [MerchantStats] {
        let expenses = transactions.filter { $0.type == .expense }
        let byMerchant = Dictionary(grouping: expenses) { $0.merchant.lowercased().trimmingCharacters(in: .whitespaces) }
        
        let calendar = Calendar.current
        let now = Date()
        
        // Count distinct months in data for avg calculation
        let distinctMonths = Set(expenses.map { calendar.dateComponents([.year, .month], from: $0.date) }).count
        let monthDivisor = max(Double(distinctMonths), 1.0)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        
        return byMerchant.map { (merchantKey, txns) in
            let total = txns.reduce(0) { $0 + $1.amount }
            let count = txns.count
            let displayName = txns.first?.merchant ?? merchantKey
            
            // Primary category = most frequent
            let cats = Dictionary(grouping: txns) { $0.category }
            let primaryCat = cats.max(by: { $0.value.count < $1.value.count })?.key ?? "Unknown"
            
            // Last 3 months breakdown
            let last3Months: [(String, Double)] = (0..<3).compactMap { offset in
                guard let month = calendar.date(byAdding: .month, value: -offset, to: now) else { return nil }
                let comps = calendar.dateComponents([.year, .month], from: month)
                let monthTxns = txns.filter { calendar.dateComponents([.year, .month], from: $0.date) == comps }
                let sum = monthTxns.reduce(0) { $0 + $1.amount }
                return (formatter.string(from: month), sum)
            }
            
            return MerchantStats(
                name: displayName,
                totalSpent: total,
                visitCount: count,
                avgPerVisit: count > 0 ? total / Double(count) : 0,
                avgMonthlySpend: total / monthDivisor,
                lastVisitDate: txns.max(by: { $0.date < $1.date })?.date ?? now,
                primaryCategory: primaryCat,
                monthlyBreakdown: last3Months
            )
        }.sorted { $0.totalSpent > $1.totalSpent }
    }
    
    func computeCategoryStats(from transactions: [Transaction]) -> [CategoryStats] {
        let expenses = transactions.filter { $0.type == .expense }
        let byCategory = Dictionary(grouping: expenses) { $0.category }
        
        let calendar = Calendar.current
        let now = Date()
        let distinctMonths = Set(expenses.map { calendar.dateComponents([.year, .month], from: $0.date) }).count
        let monthDivisor = max(Double(distinctMonths), 1.0)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        
        // Current & previous month for trend
        let currentMonthComps = calendar.dateComponents([.year, .month], from: now)
        let prevMonthDate = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        let prevMonthComps = calendar.dateComponents([.year, .month], from: prevMonthDate)
        
        return byCategory.map { (category, txns) in
            let total = txns.reduce(0) { $0 + $1.amount }
            
            // Top merchant in this category
            let merchantGroups = Dictionary(grouping: txns) { $0.merchant }
            let topMerchant = merchantGroups.max(by: {
                $0.value.reduce(0) { $0 + $1.amount } < $1.value.reduce(0) { $0 + $1.amount }
            })?.key ?? "Various"
            
            // Month-over-month trend
            let curMonthTotal = txns.filter { calendar.dateComponents([.year, .month], from: $0.date) == currentMonthComps }.reduce(0) { $0 + $1.amount }
            let prevMonthTotal = txns.filter { calendar.dateComponents([.year, .month], from: $0.date) == prevMonthComps }.reduce(0) { $0 + $1.amount }
            let trend = prevMonthTotal > 0 ? ((curMonthTotal - prevMonthTotal) / prevMonthTotal) * 100 : 0
            
            // Last 3 months
            let last3: [(String, Double)] = (0..<3).compactMap { offset in
                guard let month = calendar.date(byAdding: .month, value: -offset, to: now) else { return nil }
                let comps = calendar.dateComponents([.year, .month], from: month)
                let sum = txns.filter { calendar.dateComponents([.year, .month], from: $0.date) == comps }.reduce(0) { $0 + $1.amount }
                return (formatter.string(from: month), sum)
            }
            
            return CategoryStats(
                name: category,
                totalSpent: total,
                avgMonthly: total / monthDivisor,
                transactionCount: txns.count,
                topMerchant: topMerchant,
                monthOverMonthTrend: trend,
                monthlyBreakdown: last3
            )
        }.sorted { $0.totalSpent > $1.totalSpent }
    }
    
    func computeMonthlyStats(from transactions: [Transaction]) -> [MonthStats] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        
        let byMonth = Dictionary(grouping: transactions) {
            calendar.dateComponents([.year, .month], from: $0.date)
        }
        
        return byMonth.map { (comps, txns) in
            let expenses = txns.filter { $0.type == .expense }
            let income = txns.filter { $0.type == .income }
            let totalSpent = expenses.reduce(0) { $0 + $1.amount }
            let totalIncome = income.reduce(0) { $0 + $1.amount }
            
            let topMerchant = Dictionary(grouping: expenses) { $0.merchant }
                .max(by: { $0.value.reduce(0) { $0 + $1.amount } < $1.value.reduce(0) { $0 + $1.amount } })?.key ?? "None"
            let topCategory = Dictionary(grouping: expenses) { $0.category }
                .max(by: { $0.value.reduce(0) { $0 + $1.amount } < $1.value.reduce(0) { $0 + $1.amount } })?.key ?? "None"
            
            let date = calendar.date(from: comps) ?? Date()
            return MonthStats(
                label: formatter.string(from: date),
                totalSpent: totalSpent,
                totalIncome: totalIncome,
                savings: totalIncome - totalSpent,
                topMerchant: topMerchant,
                topCategory: topCategory
            )
        }.sorted { $0.label > $1.label } // newest first
    }
    
    // MARK: - Build Rich Context String for AI Chat
    
    func buildRichContext(transactions: [Transaction], userQuery: String) -> String {
        let merchantStats = computeMerchantStats(from: transactions)
        let categoryStats = computeCategoryStats(from: transactions)
        let monthlyStats = computeMonthlyStats(from: transactions)
        
        let queryLower = userQuery.lowercased()
        
        var sections: [String] = []
        
        // --- SECTION 1: Overall Summary ---
        let totalExpenses = transactions.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
        let totalIncome = transactions.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        sections.append("""
        FINANCIAL OVERVIEW:
        • Total Income: ₹\(Int(totalIncome))
        • Total Expenses: ₹\(Int(totalExpenses))
        • Net Balance: ₹\(Int(totalIncome - totalExpenses))
        """)
        
        // --- SECTION 2: Targeted Merchant Data (if query mentions a merchant) ---
        let matchedMerchants = merchantStats.filter { stat in
            let nameLower = stat.name.lowercased()
            // Fuzzy: check if query contains merchant name OR merchant name contains query keywords
            return queryLower.contains(nameLower) || nameLower.split(separator: " ").contains(where: { queryLower.contains($0.lowercased()) })
        }
        
        if !matchedMerchants.isEmpty {
            let merchantDetail = matchedMerchants.prefix(3).map { m in
                let monthlyStr = m.monthlyBreakdown.map { "\($0.month): ₹\(Int($0.amount))" }.joined(separator: ", ")
                return """
                📍 \(m.name):
                  Total: ₹\(Int(m.totalSpent)) | \(m.visitCount) visits | Avg/visit: ₹\(Int(m.avgPerVisit))
                  Avg/month: ₹\(Int(m.avgMonthlySpend)) | Category: \(m.primaryCategory)
                  Monthly: \(monthlyStr)
                """
            }.joined(separator: "\n")
            sections.append("TARGETED MERCHANT DATA:\n\(merchantDetail)")
        }
        
        // --- SECTION 3: Targeted Category Data (if query mentions a category) ---
        let matchedCategories = categoryStats.filter { stat in
            queryLower.contains(stat.name.lowercased())
        }
        
        if !matchedCategories.isEmpty {
            let catDetail = matchedCategories.prefix(3).map { c in
                let trendStr = c.monthOverMonthTrend > 0 ? "+\(Int(c.monthOverMonthTrend))%" : "\(Int(c.monthOverMonthTrend))%"
                let monthlyStr = c.monthlyBreakdown.map { "\($0.month): ₹\(Int($0.amount))" }.joined(separator: ", ")
                return """
                📂 \(c.name):
                  Total: ₹\(Int(c.totalSpent)) | \(c.transactionCount) txns | Avg/month: ₹\(Int(c.avgMonthly))
                  Trend: \(trendStr) vs last month | Top Merchant: \(c.topMerchant)
                  Monthly: \(monthlyStr)
                """
            }.joined(separator: "\n")
            sections.append("TARGETED CATEGORY DATA:\n\(catDetail)")
        }
        
        // --- SECTION 4: Top Merchants (always provide as context) ---
        let topMerchants = merchantStats.prefix(5).map { m in
            "\(m.name): ₹\(Int(m.totalSpent)) (\(m.visitCount) visits, ₹\(Int(m.avgPerVisit))/visit)"
        }.joined(separator: "\n")
        sections.append("TOP 5 MERCHANTS:\n\(topMerchants)")
        
        // --- SECTION 5: Top Categories (always provide) ---
        let topCategories = categoryStats.prefix(5).map { c in
            let trendStr = c.monthOverMonthTrend > 0 ? "↑\(Int(c.monthOverMonthTrend))%" : (c.monthOverMonthTrend < 0 ? "↓\(Int(abs(c.monthOverMonthTrend)))%" : "→")
            return "\(c.name): ₹\(Int(c.totalSpent)) (avg ₹\(Int(c.avgMonthly))/mo, \(trendStr))"
        }.joined(separator: "\n")
        sections.append("TOP 5 CATEGORIES:\n\(topCategories)")
        
        // --- SECTION 6: Monthly Summary (last 3 months) ---
        let recentMonths = monthlyStats.prefix(3).map { m in
            "  \(m.label): Spent ₹\(Int(m.totalSpent)) | Earned ₹\(Int(m.totalIncome)) | Top: \(m.topMerchant) (\(m.topCategory))"
        }.joined(separator: "\n")
        sections.append("LAST 3 MONTHS:\n\(recentMonths)")
        
        return sections.joined(separator: "\n\n")
    }
}
