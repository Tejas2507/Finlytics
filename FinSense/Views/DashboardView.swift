import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Query private var transactions: [Transaction]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var tutorialManager: TutorialManager
    @AppStorage("monthlySalary") private var monthlySalary: Double = 0.0
    @State private var apiKey: String = ""
    @State private var showThisMonth = false
    @State private var dailyInsight: Insight? = nil  // Direct state instead of @Query
    
    // Current month's transactions
    var currentMonthTransactions: [Transaction] {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        return transactions.filter { $0.date >= startOfMonth }
    }
    
    // Lifetime totals
    var lifetimeIncome: Double {
        transactions.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
    }
    
    // Lifetime expense includes investments (affects balance)
    var lifetimeExpense: Double {
        transactions.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
    }
    
    var netBalance: Double {
        lifetimeIncome - lifetimeExpense
    }
    
    // Monthly stats
    var monthlyIncome: Double {
        currentMonthTransactions.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
    }
    
    var monthlyExpense: Double {
        currentMonthTransactions.filter { MonthlyStats.isSpending($0) }.reduce(0) { $0 + $1.amount }
    }
    
    @State private var showBalanceEdit = false
    @AppStorage("startingBalance") private var startingBalance: Double = 0.0
    @State private var balanceInput: String = ""
    
    // Transaction-based change (income - expenses from all transactions)
    var transactionChange: Double {
        lifetimeIncome - lifetimeExpense
    }
    
    // Displayed balance = Starting balance + all transaction changes
    var displayedBalance: Double {
        startingBalance + transactionChange
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header with stats + This Month button
                    // Header with stats + This Month button
                    DashboardHeader(balance: displayedBalance, spent: monthlyExpense, monthlyIncome: monthlyIncome, insight: dailyInsight, showThisMonth: $showThisMonth, hasTransactions: !transactions.isEmpty, showBalanceEdit: $showBalanceEdit)
                    
                    // Spending Trends (months)
                    SpendingTrendsView(transactions: transactions)
                        .tutorialTarget(.spendingTrends)
                    
                    // Lifetime Expenses
                    LifetimeExpensesView(transactions: transactions)
                    
                    // Recent Transactions
                    RecentTransactionsView(transactions: transactions)
                }
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .onAppear {
                apiKey = KeychainHelper.shared.read(for: "gemini_api_key") ?? ""
                balanceInput = startingBalance > 0 ? String(format: "%.0f", startingBalance) : ""
            }
            .task {
                // Only fetch once when view appears - InsightEngine handles cooldown internally
                let key = KeychainHelper.shared.read(for: "gemini_api_key") ?? ""
                let insight = await InsightEngine.shared.fetchTodaysInsight(context: modelContext, transactions: transactions, apiKey: key)
                dailyInsight = insight
                print("DEBUG DASHBOARD: Set dailyInsight to: \(insight?.title ?? "nil")")
            }
            .sheet(isPresented: $showThisMonth) {
                ThisMonthSheet(transactions: transactions)
            }
            .sheet(isPresented: $showBalanceEdit) {
                NavigationView {
                    Form {
                        Section("Set Your Balance") {
                            Text("Enter your current actual balance. Future transactions will be added/subtracted from this.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Text("₹")
                                    .foregroundColor(.secondary)
                                TextField("Enter amount", text: $balanceInput)
                                    #if os(iOS)
                                    .keyboardType(.numberPad)
                                    #endif
                            }
                        }
                        
                        Section("How it works") {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Your balance = Starting balance + Income − Expenses")
                                    .font(.caption)
                                Text("Transaction change so far: \(transactionChange >= 0 ? "+" : "")\(transactionChange, format: .currency(code: "INR"))")
                                    .font(.caption)
                                    .foregroundColor(transactionChange >= 0 ? .green : .red)
                            }
                        }
                    }
                    .navigationTitle("Edit Balance")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showBalanceEdit = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                startingBalance = Double(balanceInput) ?? 0
                                showBalanceEdit = false
                                tutorialManager.completeStep(.editBalance)
                            }
                        }
                    }
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
        let month: String
        let amount: Double
    }
    
    var spendingTrends: [TrendData] {
        let calendar = Calendar.current
        let now = Date()
        var result: [TrendData] = []
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        
        // Last 6 months
        for i in (0..<6).reversed() {
            guard let monthDate = calendar.date(byAdding: .month, value: -i, to: now) else { continue }
            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: monthDate)) ?? monthDate
            let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) ?? monthDate
            
            let expenses = transactions.filter { $0.date >= startOfMonth && $0.date < endOfMonth && MonthlyStats.isSpending($0) }
            let total = expenses.reduce(0) { $0 + $1.amount }
            
            result.append(TrendData(month: formatter.string(from: monthDate), amount: total))
        }
        return result
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spending Trends")
                .font(.headline)
                .padding(.horizontal)
            
            if spendingTrends.allSatisfy({ $0.amount == 0 }) {
                Text("No spending data yet")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                    .padding(.horizontal)
            } else {
                Chart {
                    ForEach(spendingTrends) { trend in
                        AreaMark(
                            x: .value("Month", trend.month),
                            y: .value("Amount", trend.amount)
                        )
                        .foregroundStyle(LinearGradient(colors: [.indigo.opacity(0.6), .indigo.opacity(0.1)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                        
                        LineMark(
                            x: .value("Month", trend.month),
                            y: .value("Amount", trend.amount)
                        )
                        .foregroundStyle(.indigo)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        
                        PointMark(
                            x: .value("Month", trend.month),
                            y: .value("Amount", trend.amount)
                        )
                        .foregroundStyle(.indigo)
                    }
                }
                .frame(height: 160)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(16)
                .padding(.horizontal)
            }
        }
    }
}

// Lifetime Expenses (replaces CategoryBreakdownView)
struct LifetimeExpensesView: View {
    let transactions: [Transaction]
    
    struct CategoryData: Identifiable {
        var id: String { name }
        let name: String
        let amount: Double
    }
    
    var lifetimeTotalExpense: Double {
        transactions.filter { MonthlyStats.isSpending($0) }.reduce(0) { $0 + $1.amount }
    }
    
    var categoryBreakdown: [CategoryData] {
        let expenses = transactions.filter { MonthlyStats.isSpending($0) }
        let grouped = Dictionary(grouping: expenses) { $0.category }
        return grouped.map { CategoryData(name: $0.key, amount: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.amount > $1.amount }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overall Expenses")
                .font(.headline)
                .padding(.horizontal)
            
            if categoryBreakdown.isEmpty {
                Text("No expenses recorded yet")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                    .padding(.horizontal)
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
                    .frame(width: 140, height: 140)
                    
                    // Legend
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(categoryBreakdown.prefix(6)) { item in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Category.color(for: item.name))
                                    .frame(width: 8, height: 8)
                                Text(item.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(Int(item.amount / lifetimeTotalExpense * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(16)
                .padding(.horizontal)
            }
        }
    }
}

struct RecentTransactionsView: View {
    let transactions: [Transaction]
    
    var recentTransactions: [Transaction] {
        transactions.sorted { $0.date > $1.date }.prefix(3).map { $0 }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Recent")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)
            
            // Show 3 most recent transactions
            ForEach(recentTransactions) { tx in
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
