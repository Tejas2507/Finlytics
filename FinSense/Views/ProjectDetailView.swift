import SwiftUI
import SwiftData
import Charts

struct ProjectDetailView: View {
    let project: Project
    
    @Environment(\.dismiss) private var dismiss
    @Query private var allTransactions: [Transaction]
    @State private var showingAddTransaction = false
    @State private var showingBulkTag = false
    @State private var showingEditBudget = false
    @State private var newBudgetAmount: Double = 0.0
    @State private var searchText = ""
    
    private var projectTransactions: [Transaction] {
        allTransactions.filter { $0.projectNames.contains(project.name) }
    }
    
    var filteredProjectTransactions: [Transaction] {
        let sorted = projectTransactions.sorted { $0.date > $1.date }
        if searchText.isEmpty { return sorted }
        return sorted.filter { 
            $0.merchant.localizedCaseInsensitiveContains(searchText) || 
            $0.category.localizedCaseInsensitiveContains(searchText) 
        }
    }
    
    var totalSpent: Double {
        projectTransactions
            .filter { $0.type == .expense }
            .reduce(0) { $0 + $1.amount }
    }
    
    var totalIncome: Double {
        projectTransactions
            .filter { $0.type == .income }
            .reduce(0) { $0 + $1.amount }
    }
    
    // Category breakdown
    struct CategorySlice: Identifiable {
        var id: String { name }
        let name: String
        let amount: Double
    }
    
    var categoryBreakdown: [CategorySlice] {
        let expenses = projectTransactions.filter { $0.type == .expense }
        let grouped = Dictionary(grouping: expenses) { $0.category }
        return grouped.map { CategorySlice(name: $0.key, amount: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.amount > $1.amount }
    }
    
    // Monthly trend data
    struct MonthData: Identifiable {
        let id = UUID()
        let month: String
        let amount: Double
    }
    
    var monthlyTrend: [MonthData] {
        let calendar = Calendar.current
        let expenses = projectTransactions.filter { $0.type == .expense }
        
        // Group by year-month
        let grouped = Dictionary(grouping: expenses) { tx -> String in
            let comps = calendar.dateComponents([.year, .month], from: tx.date)
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM yy"
            return formatter.string(from: calendar.date(from: comps) ?? tx.date)
        }
        
        // Sort by date
        let sorted = grouped.sorted { pair1, pair2 in
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM yy"
            let d1 = formatter.date(from: pair1.key) ?? Date.distantPast
            let d2 = formatter.date(from: pair2.key) ?? Date.distantPast
            return d1 < d2
        }
        
        return sorted.map { MonthData(month: $0.key, amount: $0.value.reduce(0) { $0 + $1.amount }) }
    }
    
    var body: some View {
        List {
            Section {
                headerCard
            }
            .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 8, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            
            Section {
                statsGrid
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            
            if !categoryBreakdown.isEmpty {
                Section {
                    categorySection
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            
            if monthlyTrend.count > 1 {
                Section {
                    trendSection
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            
            transactionsSection
            
            Section {
                VStack(spacing: 0) {
                    Button {
                        withAnimation { project.isArchived = true }
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Label("End Project (Archive)", systemImage: "archivebox.fill")
                                .foregroundColor(.orange)
                            Spacer()
                        }
                    }
                    .padding(.vertical, 12)
                    
                    Divider()
                    
                    Button {
                        withAnimation { project.isHidden = true }
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Hide Project from UI", systemImage: "eye.slash")
                                .foregroundColor(.purple)
                            Spacer()
                        }
                    }
                    .padding(.vertical, 12)
                }
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Search in \(project.name)")
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showingAddTransaction = true
                    } label: {
                        Label("New Transaction", systemImage: "plus")
                    }
                    Button {
                        showingBulkTag = true
                    } label: {
                        Label("Tag Existing", systemImage: "tag.fill")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
            }
        }
        .sheet(isPresented: $showingAddTransaction) {
            NavigationView {
                AddTransactionView(preselectedProject: project.name)
            }
        }
        .sheet(isPresented: $showingBulkTag) {
            BulkTagSheet(projectName: project.name)
        }
        .alert("Project Budget", isPresented: $showingEditBudget) {
            TextField("Amount (0 to remove)", value: $newBudgetAmount, format: .number)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                project.targetBudget = newBudgetAmount
            }
        } message: {
            Text("Set a spending limit for this project.")
        }
    }
    
    // MARK: - Header
    private var headerCard: some View {
        VStack(spacing: 14) {
            Text(project.emoji)
                .font(.system(size: 48))
            
            Text(project.name)
                .font(.title2)
                .fontWeight(.bold)
            
            // Budget progress
            if project.targetBudget > 0 {
                let progress = min(totalSpent / project.targetBudget, 1.0)
                let progressColor: Color = totalSpent > project.targetBudget ? .red :
                    (totalSpent > project.targetBudget * 0.8 ? .orange : .green)
                
                VStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(.systemGray5))
                                .frame(height: 10)
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [progressColor.opacity(0.7), progressColor],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(geo.size.width * progress, 6), height: 10)
                                .animation(.easeInOut(duration: 0.6), value: progress)
                        }
                    }
                    .frame(height: 10)
                    
                    HStack {
                        Text("\(totalSpent, format: .currency(code: "INR")) spent")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button {
                            newBudgetAmount = project.targetBudget
                            showingEditBudget = true
                        } label: {
                            Text("Budget: \(project.targetBudget, format: .currency(code: "INR"))")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(progressColor)
                                .underline()
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                HStack {
                    Text("\(totalSpent, format: .currency(code: "INR")) total spent")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        newBudgetAmount = project.targetBudget
                        showingEditBudget = true
                    } label: {
                        Text("Add Budget")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.indigo.opacity(0.1))
                            .foregroundColor(.indigo)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Stats Grid
    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ProjectStatCard(title: "Transactions", value: "\(projectTransactions.count)", icon: "list.bullet", color: .indigo)
            ProjectStatCard(title: "Categories", value: "\(categoryBreakdown.count)", icon: "square.grid.2x2", color: .purple)
            ProjectStatCard(title: "Months", value: "\(monthlyTrend.count)", icon: "calendar", color: .teal)
        }
    }
    
    // MARK: - Category Breakdown
    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Category Breakdown")
                .font(.headline)
            
            HStack(spacing: 16) {
                Chart(categoryBreakdown.prefix(6)) { item in
                    SectorMark(
                        angle: .value("Amount", item.amount),
                        innerRadius: .ratio(0.55),
                        angularInset: 1
                    )
                    .foregroundStyle(Category.color(for: item.name))
                    .cornerRadius(4)
                }
                .frame(width: 130, height: 130)
                
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
                            Text(item.amount, format: .currency(code: "INR"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
    
    // MARK: - Trend Chart
    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spending Over Time")
                .font(.headline)
            
            Chart {
                ForEach(monthlyTrend) { data in
                    AreaMark(
                        x: .value("Month", data.month),
                        y: .value("Amount", data.amount)
                    )
                    .foregroundStyle(
                        LinearGradient(colors: [.indigo.opacity(0.6), .indigo.opacity(0.1)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .interpolationMethod(.catmullRom)
                    
                    LineMark(
                        x: .value("Month", data.month),
                        y: .value("Amount", data.amount)
                    )
                    .foregroundStyle(.indigo)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    
                    PointMark(
                        x: .value("Month", data.month),
                        y: .value("Amount", data.amount)
                    )
                    .foregroundStyle(.indigo)
                }
            }
            .frame(height: 160)
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
    
    // MARK: - Transactions
    @ViewBuilder
    private var transactionsSection: some View {
        Section {
            if filteredProjectTransactions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No transactions found.")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Tag transactions or add new ones using the + button.")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .padding(.horizontal)
            }
        }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            
            if !filteredProjectTransactions.isEmpty {
                ForEach(filteredProjectTransactions) { tx in
                    NavigationLink(destination: AddTransactionView(existingTransaction: tx)) {
                        TransactionRow(transaction: tx)
                            .padding(.vertical, 8)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            tx.projectNames.removeAll(where: { $0 == project.name })
                        } label: {
                            Label("Remove Tag", systemImage: "minus.circle")
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.visible)
                .listRowBackground(Color.clear)
            }
        }
    }

// MARK: - Stat Card
struct ProjectStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Bulk Tag Sheet
struct BulkTagSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    let projectName: String
    @State private var selected = Set<UUID>()
    
    var untagged: [Transaction] {
        transactions.filter { !$0.projectNames.contains(projectName) && $0.type == .expense }
    }
    
    var body: some View {
        NavigationView {
            List {
                if untagged.isEmpty {
                    Text("All expense transactions are already tagged to this project.")
                        .foregroundColor(.secondary)
                } else {
                    Section(footer: Text("Select transactions to add to this project.")) {
                        ForEach(untagged) { tx in
                            Button {
                                if selected.contains(tx.id) {
                                    selected.remove(tx.id)
                                } else {
                                    selected.insert(tx.id)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: Category.icon(for: tx.category))
                                        .foregroundColor(.white)
                                        .frame(width: 32, height: 32)
                                        .background(Category.color(for: tx.category))
                                        .clipShape(Circle())
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tx.merchant)
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                        Text(tx.date.formatted(date: .abbreviated, time: .omitted))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Text(tx.amount, format: .currency(code: "INR"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    if selected.contains(tx.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.indigo)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundColor(.secondary.opacity(0.4))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tag to Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tag \(selected.count)") {
                        for tx in untagged where selected.contains(tx.id) {
                            tx.projectNames.append(projectName)
                        }
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
    }
}
