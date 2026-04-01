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
    @AppStorage("lastPersonaUpdate") private var lastPersonaUpdate: Double = 0.0
    
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
    @AppStorage("startingBalanceDate") private var startingBalanceDate: Double = 0.0 // Store as timestamp
    @State private var balanceInput: String = ""
    
    // Transaction-based change (income - expenses from transactions AFTER startingBalanceDate)
    var transactionChange: Double {
        let referenceDate = startingBalanceDate > 0 ? Date(timeIntervalSince1970: startingBalanceDate) : Date.distantPast
        let relevantTransactions = transactions.filter { $0.date >= referenceDate }
        
        let income = relevantTransactions.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        let expense = relevantTransactions.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
        
        return income - expense
    }
    
    // Displayed balance = Starting balance + all transaction changes
    var displayedBalance: Double {
        startingBalance + transactionChange
    }
    
    var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 24) {
                        // Header with stats + This Month button
                        DashboardHeader(balance: displayedBalance, spent: monthlyExpense, monthlyIncome: monthlyIncome, insight: dailyInsight, showThisMonth: $showThisMonth, hasTransactions: !transactions.isEmpty, showBalanceEdit: $showBalanceEdit)
                        
                        // Spending Trends (months)
                        SpendingTrendsView(transactions: transactions)
                        
                        // Lifetime Expenses
                        LifetimeExpensesView(transactions: transactions)
                        
                        // Projects Summary
                        ProjectsSummarySection(transactions: transactions)
                            .id("projectsSection")
                            .tutorialTarget(.projects)
                        
                        // Recent Transactions
                        RecentTransactionsView(transactions: transactions)
                    }
                }
                .onChange(of: tutorialManager.currentStep) { _, newStep in
                    if newStep == .projects {
                        withAnimation {
                            proxy.scrollTo("projectsSection", anchor: .center)
                        }
                    }
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
                
                // Triggers AI Behavioral Profiling in background once a week
                let now = Date().timeIntervalSince1970
                if now - lastPersonaUpdate > 7 * 86400 {
                    AIPersonaEngine.shared.archiveCurrentPersona() // snapshot the old one first
                    await AIPersonaEngine.shared.generatePersona(transactions: transactions)
                    lastPersonaUpdate = now
                }
                
                // 30-day fallback: summarize chat signals even if user chats infrequently
                AIPersonaEngine.shared.summarizeIfStale()
            }
            // When the chat summarizer fires, immediately sync persona with the fresh signals
            .onReceive(NotificationCenter.default.publisher(for: .chatSignalsUpdated)) { _ in
                Task {
                    print("🔄 chatSignalsUpdated received — refreshing persona immediately")
                    AIPersonaEngine.shared.archiveCurrentPersona()
                    await AIPersonaEngine.shared.generatePersona(transactions: transactions)
                    lastPersonaUpdate = Date().timeIntervalSince1970
                }
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
                                startingBalanceDate = Date().timeIntervalSince1970 // Save current time
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
        transactions.filter { !$0.isHidden }.sorted { $0.date > $1.date }.prefix(3).map { $0 }
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
// Projects Summary Section for Dashboard
struct ProjectsSummarySection: View {
    let transactions: [Transaction]
    @Query(sort: \Project.dateCreated, order: .reverse) private var projects: [Project]
    @State private var showCreateSheet = false
    
    var activeProjects: [Project] {
        projects.filter { !$0.isArchived && !$0.isHidden }
    }
    
    func spent(for project: Project) -> Double {
        transactions
            .filter { $0.projectNames.contains(project.name) && $0.type == .expense }
            .reduce(0) { $0 + $1.amount }
    }
    
    var body: some View {
        if !activeProjects.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Projects")
                        .font(.headline)
                    Spacer()
                    NavigationLink(destination: ProjectsListView()) {
                        Text("See All")
                            .font(.caption)
                            .foregroundColor(.indigo)
                    }
                }
                .padding(.horizontal)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(activeProjects.prefix(5)) { project in
                            NavigationLink(destination: ProjectDetailView(project: project)) {
                                ProjectDashboardCard(project: project, spent: spent(for: project))
                            }
                            .buttonStyle(.plain)
                        }
                        
                        // Add new project button
                        Button { showCreateSheet = true } label: {
                            VStack {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title)
                                    .foregroundColor(.indigo.opacity(0.7))
                                Text("New")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .frame(width: 80, height: 100)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                CreateProjectSheet()
            }
        } else {
            // Prompt to create first project
            VStack(alignment: .leading, spacing: 12) {
                Text("Projects")
                    .font(.headline)
                    .padding(.horizontal)
                
                NavigationLink(destination: ProjectsListView()) {
                    HStack(spacing: 12) {
                        Image(systemName: "tray.2.fill")
                            .font(.title2)
                            .foregroundColor(.indigo)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Create a Project")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            Text("Track spending for trips, events, or projects")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal)
            }
        }
    }
}

// Inline Create Project Sheet
struct CreateProjectSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji = "🎯"
    @State private var budget: String = ""
    
    let emojis = ["✈️","🎯","🏠","🎉","💼","🛍️","🎓","🏖️","🚗","💍","🎄","🏕️","🎸","⚽","🍽️"]
    
    var body: some View {
        NavigationView {
            Form {
                Section("Details") {
                    TextField("Project name", text: $name)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(emojis, id: \.self) { e in
                                Button { emoji = e } label: {
                                    Text(e).font(.title2)
                                        .padding(6)
                                        .background(emoji == e ? Color.indigo.opacity(0.3) : Color.clear)
                                        .clipShape(Circle())
                                }
                            }
                        }
                    }
                }
                Section {
                    TextField("₹ Budget (optional)", text: $budget)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Budget Limit")
                } footer: {
                    Text("Set a spending limit to track progress. Leave empty for no limit.")
                }
            }
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let project = Project(name: name, emoji: emoji, targetBudget: Double(budget) ?? 0)
                        modelContext.insert(project)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct ProjectDashboardCard: View {
    let project: Project
    let spent: Double
    
    var progress: Double {
        guard project.targetBudget > 0 else { return 0 }
        return min(spent / project.targetBudget, 1.0)
    }
    
    var progressColor: Color {
        if project.targetBudget <= 0 { return .indigo }
        if spent > project.targetBudget { return .red }
        if spent > project.targetBudget * 0.8 { return .orange }
        return .green
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(project.emoji)
                    .font(.title2)
                Spacer()
                if project.targetBudget > 0 {
                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(progressColor)
                } else {
                    Text(" ")
                        .font(.caption2)
                }
            }
            
            Text(project.name)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(1)
            
            Text(spent, format: .currency(code: "INR"))
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            
            if project.targetBudget > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.systemGray5)).frame(height: 5)
                        Capsule()
                            .fill(LinearGradient(colors: [progressColor.opacity(0.7), progressColor], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(geo.size.width * progress, 4), height: 5)
                    }
                }
                .frame(height: 5)
            } else {
                Spacer()
                    .frame(height: 5)
            }
        }
        .padding(14)
        .frame(width: 150)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
