import SwiftUI
import SwiftData
import Charts

struct ThisMonthSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("monthlySalary") private var monthlySalary: Double = 0.0
    let transactions: [Transaction]
    
    @State private var wrappedText: String = ""
    @State private var isLoadingWrapped = false
    @State private var showWrapped = false
    
    // Check if first day of month (show wrapped for previous month)
    var isWrappedTime: Bool {
        let calendar = Calendar.current
        let dayOfMonth = calendar.component(.day, from: Date())
        return dayOfMonth == 1
    }
    
    // Previous month for wrapped
    var previousMonth: Date? {
        Calendar.current.date(byAdding: .month, value: -1, to: Date())
    }
    
    var currentMonthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter.string(from: Date())
    }
    
    // Current month's transactions
    var currentMonthTransactions: [Transaction] {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        return transactions.filter { $0.date >= startOfMonth }
    }
    
    // Last month's expense for comparison
    var lastMonthExpense: Double {
        let calendar = Calendar.current
        let now = Date()
        guard let lastMonth = calendar.date(byAdding: .month, value: -1, to: now) else { return 0 }
        let startOfLastMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: lastMonth)) ?? lastMonth
        let endOfLastMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        return transactions.filter { $0.date >= startOfLastMonth && $0.date < endOfLastMonth && MonthlyStats.isSpending($0) }.reduce(0) { $0 + $1.amount }
    }
    
    var vsLastMonthPercent: Int {
        guard lastMonthExpense > 0 else { return 0 }
        return Int(((totalMonthlyExpense - lastMonthExpense) / lastMonthExpense) * 100)
    }
    
    var monthlyExpenses: [Transaction] { currentMonthTransactions.filter { MonthlyStats.isSpending($0) } }
    var monthlyIncome: [Transaction] { currentMonthTransactions.filter { $0.type == .income } }
    var monthlyInvestments: [Transaction] { 
        currentMonthTransactions.filter { $0.type == .expense && $0.category.lowercased().contains("invest") } 
    }
    
    var totalMonthlyExpense: Double { monthlyExpenses.reduce(0) { $0 + $1.amount } }
    var totalMonthlyIncome: Double { monthlyIncome.reduce(0) { $0 + $1.amount } }
    var totalMonthlyInvested: Double { monthlyInvestments.reduce(0) { $0 + $1.amount } }
    
    // Biggest expense
    var biggestExpense: Transaction? {
        monthlyExpenses.max(by: { $0.amount < $1.amount })
    }
    
    // Average monthly expense (from all history)
    var averageMonthlyExpense: Double {
        let calendar = Calendar.current
        let spending = transactions.filter { MonthlyStats.isSpending($0) }
        guard !spending.isEmpty else { return 0 }
        
        let grouped = Dictionary(grouping: spending) { tx in
            calendar.date(from: calendar.dateComponents([.year, .month], from: tx.date)) ?? tx.date
        }
        let monthlyTotals = grouped.map { $0.value.reduce(0) { $0 + $1.amount } }
        return monthlyTotals.reduce(0, +) / Double(max(monthlyTotals.count, 1))
    }
    
    var comparisonPercent: Int {
        guard averageMonthlyExpense > 0 else { return 0 }
        return Int(((totalMonthlyExpense - averageMonthlyExpense) / averageMonthlyExpense) * 100)
    }
    
    // Dynamic Outlier Detection
    func computeDynamicOutlierThreshold(for txs: [Transaction]) -> Double {
        let expenses = txs.filter { MonthlyStats.isSpending($0) }
        guard expenses.count > 2 else { return 15000.0 }
        
        let mean = expenses.reduce(0) { $0 + $1.amount } / Double(expenses.count)
        let variance = expenses.reduce(0) { $0 + pow($1.amount - mean, 2.0) } / Double(expenses.count)
        let standardDeviation = sqrt(variance)
        return max(5000.0, mean + (2 * standardDeviation))
    }
    
    // Stats
    var transactionCount: Int { currentMonthTransactions.count }
    var avgTransactionSize: Double { transactionCount > 0 ? totalMonthlyExpense / Double(monthlyExpenses.count) : 0 }
    var daysInMonth: Int { Calendar.current.range(of: .day, in: .month, for: Date())?.count ?? 30 }
    var currentDayOfMonth: Int { Calendar.current.component(.day, from: Date()) }
    
    var projectedMonthEnd: Double {
        guard currentDayOfMonth > 0 else { return 0 }
        let threshold = computeDynamicOutlierThreshold(for: transactions)
        
        let outliers = monthlyExpenses.filter { $0.amount > threshold }
        let variables = monthlyExpenses.filter { $0.amount <= threshold }
        
        let outlierTotal = outliers.reduce(0) { $0 + $1.amount }
        let variableTotal = variables.reduce(0) { $0 + $1.amount }
        
        let avgDailyVariable = variableTotal / Double(currentDayOfMonth)
        return (avgDailyVariable * Double(daysInMonth)) + outlierTotal
    }
    // Save Rate = (monthly salary - actual spent) / monthly salary
    var savingsRate: Double { monthlySalary > 0 ? ((monthlySalary - totalMonthlyExpense) / monthlySalary) * 100 : 0 }
    
    // Category breakdown
    struct CategoryData: Identifiable {
        var id: String { name }
        let name: String
        let amount: Double
    }
    
    var categoryBreakdown: [CategoryData] {
        let grouped = Dictionary(grouping: monthlyExpenses) { $0.category }
        return grouped.map { CategoryData(name: $0.key, amount: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.amount > $1.amount }
    }
    
    // Top merchants
    struct MerchantData: Identifiable {
        var id: String { name }
        let name: String
        let amount: Double
        let count: Int
    }
    
    var topMerchants: [MerchantData] {
        let grouped = Dictionary(grouping: monthlyExpenses) { $0.merchant }
        return grouped.map { MerchantData(name: $0.key, amount: $0.value.reduce(0) { $0 + $1.amount }, count: $0.value.count) }
            .sorted { $0.amount > $1.amount }
            .prefix(5).map { $0 }
    }
    
    // Week-wise spending (better than day-wise)
    struct WeekData: Identifiable {
        var id: Int { week }
        let week: Int
        let label: String
        let amount: Double
    }
    
    var weekWiseSpending: [WeekData] {
        let calendar = Calendar.current
        var result: [WeekData] = []
        
        for week in 1...5 {
            let startDay = (week - 1) * 7 + 1
            let endDay = min(week * 7, daysInMonth)
            
            let weekExpenses = monthlyExpenses.filter {
                let day = calendar.component(.day, from: $0.date)
                return day >= startDay && day <= endDay
            }
            let total = weekExpenses.reduce(0) { $0 + $1.amount }
            let label = "W\(week)"
            result.append(WeekData(week: week, label: label, amount: total))
        }
        return result.filter { $0.week <= Int(ceil(Double(currentDayOfMonth) / 7.0)) || $0.amount > 0 }
    }
    @State private var showMonthPicker = false
    @State private var selectedHistoryMonth: Date? = nil
    
    // Get available months with data
    var availableMonths: [Date] {
        MonthlyStats.shared.getMonthsWithData(from: transactions)
            .filter { month in
                // Exclude current month
                let calendar = Calendar.current
                let now = Date()
                let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))
                return month != currentMonth
            }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Wrapped Banner (shows all day on first of month)
                    if isWrappedTime, let prev = previousMonth {
                        Button(action: { showWrapped = true }) {
                            HStack {
                                Text("🎊")
                                    .font(.title)
                                Text("View \(MonthlyStats.shared.formatMonth(prev)) Wrapped")
                                    .fontWeight(.semibold)
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .foregroundColor(.white)
                            .padding()
                            .background(
                                LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing)
                            )
                            .cornerRadius(16)
                        }
                    }
                    
                    // Hero Stats Row
                    heroStatsSection
                    
                    // Quick Stats Grid
                    quickStatsSection
                    
                    // Category Breakdown (like dashboard)
                    categorySection
                    
                    // Weekly Spending (better than daily)
                    weeklySpendingSection
                    
                    // Top Merchants
                    topMerchantsSection
                    
                    // Previous Months Section
                    if !availableMonths.isEmpty {
                        previousMonthsButton
                    }
                }
                .padding()
            }
            .navigationTitle("This Month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showWrapped) {
                if let prev = previousMonth {
                    WrappedView(
                        transactions: transactions,
                        monthlySalary: monthlySalary,
                        targetMonth: prev
                    )
                }
            }
        }
    }
    
    // MARK: - Wrapped Section
    var wrappedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("🎉 Your \(currentMonthName) Wrapped")
                    .font(.headline)
                Spacer()
            }
            
            if isLoadingWrapped {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Generating your personalized summary...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if !wrappedText.isEmpty {
                Text(wrappedText)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(nil)
            } else {
                Text("Tap to generate your month's story!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(LinearGradient(colors: [.purple.opacity(0.2), .indigo.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .cornerRadius(16)
        .onTapGesture {
            if wrappedText.isEmpty && !isLoadingWrapped {
                Task { await loadWrapped() }
            }
        }
    }
    
    func loadWrapped() async {
        isLoadingWrapped = true
        defer { isLoadingWrapped = false }
        
        let stats = AIManager.MonthlyStats(
            monthName: currentMonthName,
            totalSpent: totalMonthlyExpense,
            totalEarned: totalMonthlyIncome,
            savingsRate: savingsRate,
            topCategories: categoryBreakdown.prefix(3).map { ($0.name, $0.amount) },
            topMerchants: topMerchants.prefix(3).map { ($0.name, $0.amount, $0.count) },
            biggestExpense: biggestExpense.map { ($0.merchant, $0.amount) },
            transactionCount: transactionCount,
            vsLastMonth: vsLastMonthPercent
        )
        
        do {
            wrappedText = try await AIManager.shared.generateMonthlyWrapped(stats: stats)
        } catch {
            wrappedText = "Couldn't generate your wrapped. Try again!"
        }
    }
    
    // MARK: - Hero Stats
    var heroStatsSection: some View {
        HStack(spacing: 12) {
            // Spent
            VStack(spacing: 4) {
                Text("Spent")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(totalMonthlyExpense, format: .currency(code: "INR"))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.red)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.red.opacity(0.1))
            .cornerRadius(12)
            
            // Earned
            VStack(spacing: 4) {
                Text("Earned")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(totalMonthlyIncome, format: .currency(code: "INR"))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.green.opacity(0.1))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Quick Stats
    var quickStatsSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatPill(title: "Invested", value: "₹\(Int(totalMonthlyInvested).formatted())", color: .indigo)
                StatPill(title: "Projected", value: "₹\(Int(projectedMonthEnd).formatted())", color: .orange)
            }
            HStack(spacing: 12) {
                StatPill(title: "Transactions", value: "\(transactionCount)", color: .blue)
                StatPill(title: "Save Rate", value: "\(Int(savingsRate))%", color: savingsRate > 0 ? .teal : .red)
            }
        }
    }
    
    // MARK: - Category Section (like dashboard)
    var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Categories")
                .font(.headline)
            
            if categoryBreakdown.isEmpty {
                Text("No expenses this month")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                HStack(spacing: 16) {
                    // Pie Chart
                    Chart(categoryBreakdown.prefix(6)) { item in
                        SectorMark(
                            angle: .value("Amount", item.amount),
                            innerRadius: .ratio(0.55),
                            angularInset: 1
                        )
                        .foregroundStyle(Category.color(for: item.name))
                        .cornerRadius(4)
                    }
                    .frame(width: 120, height: 120)
                    
                    // Legend
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(categoryBreakdown.prefix(6)) { item in
                            HStack(spacing: 6) {
                                Circle().fill(Category.color(for: item.name)).frame(width: 8, height: 8)
                                Text(item.name).font(.caption).lineLimit(1)
                                Spacer()
                                Text(item.amount, format: .currency(code: "INR"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
    
    // MARK: - Weekly Spending with hold-to-drill-down
    @State private var holdingWeek: Int? = nil
    
    // Daily spending for selected week
    func dailySpendingForWeek(_ week: Int) -> [(day: Int, dayName: String, amount: Double)] {
        let calendar = Calendar.current
        let startDay = (week - 1) * 7 + 1
        let endDay = min(week * 7, daysInMonth)
        let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        
        var result: [(day: Int, dayName: String, amount: Double)] = []
        for day in startDay...endDay {
            let dayExpenses = monthlyExpenses.filter { calendar.component(.day, from: $0.date) == day }
            let total = dayExpenses.reduce(0) { $0 + $1.amount }
            
            let now = Date()
            let components = calendar.dateComponents([.year, .month], from: now)
            if let dateInMonth = calendar.date(from: DateComponents(year: components.year, month: components.month, day: day)) {
                let weekdayIndex = calendar.component(.weekday, from: dateInMonth) - 1
                let dayName = weekdays[weekdayIndex]
                result.append((day, dayName, total))
            }
        }
        return result
    }
    
    var weeklySpendingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly Spending")
                .font(.headline)
            
            if weekWiseSpending.allSatisfy({ $0.amount == 0 }) {
                Text("No spending data yet")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else if let week = holdingWeek {
                // Daily breakdown - tap to go back
                let dailyData = dailySpendingForWeek(week)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Week \(week) · Days \((week-1)*7+1)-\(min(week*7, daysInMonth))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Tap to go back")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                    
                    Chart(dailyData, id: \.day) { item in
                        BarMark(
                            x: .value("Day", "\(item.day)\n\(item.dayName)"),
                            y: .value("Amount", item.amount)
                        )
                        .foregroundStyle(Color.cyan.gradient)
                        .cornerRadius(4)
                        .annotation(position: .top, alignment: .center) {
                            Text(item.amount.formatted(.number.notation(.compactName)))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .chartYAxis(.hidden)
                    .frame(height: 140)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    holdingWeek = nil
                }
                .transition(.opacity)
            } else {
                // Weekly overview with hold gesture
                ZStack {
                    Chart(weekWiseSpending) { item in
                        BarMark(
                            x: .value("Week", item.label),
                            y: .value("Amount", item.amount)
                        )
                        .foregroundStyle(
                            LinearGradient(colors: [.indigo, .purple.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                        )
                        .cornerRadius(6)
                        .annotation(position: .top, alignment: .center) {
                            Text(item.amount.formatted(.number.notation(.compactName)))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .chartYAxis(.hidden)
                    .frame(height: 140)
                    
                    // Overlay for gesture detection per bar
                    HStack(spacing: 0) {
                        ForEach(weekWiseSpending) { week in
                            Rectangle()
                                .fill(Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    holdingWeek = week.week
                                }
                        }
                    }
                    .frame(height: 140)
                }
                
                Text("Tap a bar to see daily breakdown")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
        .animation(.easeInOut(duration: 0.2), value: holdingWeek)
    }
    
    // MARK: - Top Merchants
    var topMerchantsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Merchants")
                .font(.headline)
            
            if topMerchants.isEmpty {
                Text("No transactions this month")
                    .foregroundColor(.secondary)
            } else {
                ForEach(topMerchants) { merchant in
                    HStack {
                        Text(merchant.name).font(.subheadline)
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(merchant.amount, format: .currency(code: "INR"))
                                .font(.subheadline).fontWeight(.medium)
                            Text("\(merchant.count) txns")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                    if merchant.id != topMerchants.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
    
    // MARK: - Previous Months Button
    var previousMonthsButton: some View {
        VStack(spacing: 12) {
            Button(action: { showMonthPicker = true }) {
                HStack {
                    Image(systemName: "calendar")
                    Text("View Previous Months")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .foregroundColor(.primary)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
        .sheet(isPresented: $showMonthPicker) {
            MonthPickerSheet(
                availableMonths: availableMonths,
                transactions: transactions,
                monthlySalary: monthlySalary
            )
        }
    }
}

// MARK: - Stat Pill
struct StatPill: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }
}
