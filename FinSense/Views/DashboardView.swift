import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Query private var transactions: [Transaction]
    @Environment(\.modelContext) private var modelContext
    @AppStorage("monthlySalary") private var monthlySalary: Double = 0.0
    @State private var apiKey: String = ""
    @Query(sort: \Insight.generatedDate, order: .reverse) private var insights: [Insight]
    
    var dailyInsight: Insight? { insights.first }
    
    // Compute current month's transactions
    var currentMonthTransactions: [Transaction] {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        return transactions.filter { $0.date >= startOfMonth }
    }
    
    // Summary Calculations
    var netBalance: Double {
        let income = transactions.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        let expense = transactions.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
        return income - expense
    }
    
    var monthlyIncome: Double {
        currentMonthTransactions.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
    }
    
    var monthlyExpense: Double {
        currentMonthTransactions.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Unified Header with Insight + 4 Stat Cards
                    DashboardHeader(balance: netBalance, spent: monthlyExpense, monthlyIncome: monthlyIncome, insight: dailyInsight)
                    
                    SpendingTrendsView(transactions: transactions)
                    
                    MonthlyFlowChartView(monthlyIncome: monthlyIncome, monthlyExpense: monthlyExpense)
                    
                    CategoryBreakdownView(transactions: currentMonthTransactions, monthlyExpense: monthlyExpense)
                    
                    RecentTransactionsView(transactions: transactions)
                }
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .onAppear {
                // Read API key from Keychain
                apiKey = KeychainHelper.shared.read(for: "gemini_api_key") ?? ""
            }
            .task {
                // Ensure key is loaded before fetching
                let key = KeychainHelper.shared.read(for: "gemini_api_key") ?? ""
                if !transactions.isEmpty && !key.isEmpty {
                    _ = await InsightEngine.shared.fetchTodaysInsight(context: modelContext, transactions: transactions, apiKey: key)
                }
            }
        }
    }
}

// Subviews

struct SpendingTrendsView: View {
    let transactions: [Transaction]
    
    struct TrendData: Identifiable {
        let id = UUID()
        let month: Date
        let amount: Double
    }
    
    var spendingTrends: [TrendData] {
        let calendar = Calendar.current
        let now = Date()
        guard let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now) else { return [] }
        
        // Filter last 6 months expenses
        let recentExpenses = transactions.filter { $0.date >= sixMonthsAgo && $0.type == .expense }
        
        // Group by Month
        let grouped = Dictionary(grouping: recentExpenses) { tx in
            calendar.date(from: calendar.dateComponents([.year, .month], from: tx.date)) ?? tx.date
        }
        
        // Map to sorted array
        var result: [TrendData] = []
        for i in 0..<6 {
            if let date = calendar.date(byAdding: .month, value: -i, to: now) {
                 let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
                 let amount = grouped[startOfMonth]?.reduce(0) { $0 + $1.amount } ?? 0
                 result.append(TrendData(month: startOfMonth, amount: amount))
            }
        }
        return result.sorted { $0.month < $1.month }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Spending Trends")
                .font(.headline)
                .padding(.horizontal)
            
            Chart {
                ForEach(spendingTrends) { trend in
                    AreaMark(
                        x: .value("Month", trend.month, unit: .month),
                        y: .value("Amount", trend.amount)
                    )
                    .foregroundStyle(LinearGradient(colors: [.indigo, .indigo.opacity(0.1)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                    
                    LineMark(
                        x: .value("Month", trend.month, unit: .month),
                        y: .value("Amount", trend.amount)
                    )
                    .foregroundStyle(.indigo)
                    .interpolationMethod(.catmullRom)
                }
            }
            .frame(height: 180)
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }
}

struct MonthlyFlowChartView: View {
    let monthlyIncome: Double
    let monthlyExpense: Double
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("This Month's Flow")
                .font(.headline)
                .padding(.horizontal)
            
            Chart {
                BarMark(x: .value("Type", "Income"), y: .value("Amount", monthlyIncome))
                    .foregroundStyle(.green.gradient)
                BarMark(x: .value("Type", "Expense"), y: .value("Amount", monthlyExpense))
                    .foregroundStyle(.red.gradient)
            }
            .frame(height: 150)
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }
}

struct CategoryBreakdownView: View {
    let transactions: [Transaction]
    let monthlyExpense: Double
    
    struct CategoryData: Identifiable {
        var id: String { name }
        let name: String
        let amount: Double
    }
    
    var categoryBreakdown: [CategoryData] {
        let expenses = transactions.filter { $0.type == .expense }
        let grouped = Dictionary(grouping: expenses, by: { $0.category })
        return grouped.map { (key, transactions) in
            let total = transactions.reduce(0) { $0 + $1.amount }
            return CategoryData(name: key, amount: total)
        }
        .sorted { $0.amount > $1.amount }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Top Expenses")
                .font(.headline)
                .padding(.horizontal)
            
            if categoryBreakdown.isEmpty {
                Text("No expenses this month")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
            } else {
                Chart(categoryBreakdown.prefix(5)) { item in
                    SectorMark(
                        angle: .value("Amount", item.amount),
                        innerRadius: .ratio(0.6),
                        angularInset: 1.5
                    )
                    .cornerRadius(5)
                    .foregroundStyle(Category.color(for: item.name))
                    .annotation(position: .overlay) {
                        if item.amount / monthlyExpense > 0.1 { // Only show label if > 10%
                            Text(item.name.prefix(1)) // Just first letter to save space
                                .font(.caption2)
                                .foregroundColor(.white)
                                .bold()
                        }
                    }
                }
                .frame(height: 200)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // Legend
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 10) {
                    ForEach(categoryBreakdown.prefix(5)) { item in
                        HStack(spacing: 4) {
                            Circle().fill(Category.color(for: item.name)).frame(width: 8, height: 8)
                            Text("\(item.name) (\(Int(item.amount / monthlyExpense * 100))%)")
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct RecentTransactionsView: View {
    let transactions: [Transaction]
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Recent")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)
            
            // Just show top 3 for brevity in dashboard
            ForEach(transactions.prefix(3)) { tx in
                TransactionRow(transaction: tx)
            }
            .padding(.horizontal)
        }
    }
}

struct SummaryCard: View {
    let title: String
    let amount: Double
    let icon: String
    let color: Color
    var prefix: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(prefix)\(amount, format: .currency(code: "INR"))")
                    .font(.system(.body, design: .rounded))
                    .bold()
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}
