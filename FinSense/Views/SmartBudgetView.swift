import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

struct SmartBudgetView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var tutorialManager: TutorialManager
    @Query private var budgets: [Budget]
    @Query private var transactions: [Transaction]
    
    @State private var isGenerating = false
    @State private var showingAddBudget = false
    @State private var alertMessage = ""
    @State private var showAlert = false
    
    // Collaborative Flow
    @State private var suggestedProposals: [BudgetProposal] = []
    @State private var showingSuggestions = false
    
    // For manual add/edit
    @State private var editingBudget: Budget?
    
    // Bulk Selection
    @State private var selection = Set<Budget>()
    @State private var editMode: EditMode = .inactive
    
    var currentMonthTransactions: [Transaction] {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        return transactions.filter { $0.date >= startOfMonth && MonthlyStats.isSpending($0) }
    }
    
    func spentAmount(for category: String) -> Double {
        currentMonthTransactions
            .filter { $0.category == category }
            .reduce(0) { $0 + $1.amount }
    }
    
    var body: some View {
        NavigationView {
            List(selection: $selection) {
                Section {
                    Button(action: {
                        tutorialManager.completeStep(.budgeting)
                        generateBudgets()
                    }) {
                        HStack {
                            Image(systemName: "wand.and.stars")
                                .foregroundColor(.indigo)
                            Text(isGenerating ? "Analyzing Spending..." : "Generate AI Budgets")
                                .fontWeight(.medium)
                            if isGenerating {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isGenerating)
                    .tutorialTarget(.budgeting)
                } footer: {
                    Text("AI analyzes your current month's expenses to suggest realistic monthly limits.")
                }
                
                Section("Your Budgets") {
                    if budgets.isEmpty {
                        Text("No active budgets. Tap + to add manual or use AI.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(budgets) { budget in
                            BudgetRow(
                                category: budget.category,
                                limit: budget.monthlyLimit,
                                spent: spentAmount(for: budget.category)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if editMode == .active {
                                    if selection.contains(budget) {
                                        selection.remove(budget)
                                    } else {
                                        selection.insert(budget)
                                    }
                                } else {
                                    editingBudget = budget
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    modelContext.delete(budget)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    editingBudget = budget
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                            .tag(budget)
                        }
                        .onDelete(perform: deleteBudgets)
                    }
                }
            }
            .navigationTitle("Smart Budget")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if editMode == .active {
                        Button(role: .destructive) {
                            deleteSelection()
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .disabled(selection.isEmpty)
                    } else {
                        Button {
                            showingAddBudget = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .sheet(item: $editingBudget) { budget in
                BudgetEditView(budget: budget)
            }
            .sheet(isPresented: $showingAddBudget) {
                BudgetEditView(budget: nil)
            }
            .sheet(isPresented: $showingSuggestions) {
                BudgetSuggestionView(proposals: suggestedProposals)
            }
            .alert("AI Budget", isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
            .onChange(of: budgets.count) { oldCount, newCount in
                if newCount > oldCount {
                    tutorialManager.completeStep(.budgeting)
                }
            }
            .onChange(of: budgets.count) { oldCount, newCount in
                // Track budget count
            }
        }
    }
    
    private func generateBudgets() {
        isGenerating = true
        Task {
            let provider = UserDefaults.standard.string(forKey: "aiProvider") ?? "gemini"
            let keyAccount = provider == "openai" ? "openai_api_key" : "gemini_api_key"
            let apiKey = KeychainHelper.shared.read(for: keyAccount) ?? ""
            if apiKey.isEmpty {
                await MainActor.run {
                    alertMessage = "Please set your selected AI provider's API key in Settings first."
                    showAlert = true
                    isGenerating = false
                }
                return
            }
            
            do {
                let jsonString = try await AIManager.shared.generateBudgetSuggestions(history: transactions)
                
                guard let data = jsonString.data(using: .utf8) else { throw NSError(domain: "App", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid data"]) }
                
                
                // Decode directly to retrieval model
                let suggestions = try JSONDecoder().decode([BudgetProposal].self, from: data)
                
                await MainActor.run {
                    self.suggestedProposals = suggestions
                    self.showingSuggestions = true
                    self.isGenerating = false
                }
            } catch {
                await MainActor.run {
                    alertMessage = "Failed to generate budgets: \(error.localizedDescription)"
                    showAlert = true
                    isGenerating = false
                }
            }
        }
    }
    
    private func deleteBudgets(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(budgets[index])
        }
    }
    
    private func deleteSelection() {
        for budget in selection {
            modelContext.delete(budget)
        }
        selection.removeAll()
        editMode = .inactive
    }
}

struct BudgetRow: View {
    let category: String
    let limit: Double
    let spent: Double
    
    var progress: Double {
        guard limit > 0 else { return 1.0 }
        return min(spent / limit, 1.0)
    }
    
    var progressColor: Color {
        if spent > limit { return .red }
        if spent > limit * 0.8 { return .orange }
        return .green
    }
    
    var percentText: String {
        guard limit > 0 else { return "—" }
        return "\(Int(spent / limit * 100))%"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: Category.icon(for: category))
                        .font(.body)
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Category.color(for: category).opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text(category)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                Spacer()
                Text("\(spent, format: .currency(code: "INR")) / \(limit, format: .currency(code: "INR"))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 8) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .frame(width: geometry.size.width, height: 10)
                            .foregroundColor(Color(.systemGray5))
                        
                        Capsule()
                            .frame(width: max(geometry.size.width * progress, 6), height: 10)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [progressColor.opacity(0.7), progressColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .animation(.easeInOut(duration: 0.6), value: progress)
                    }
                }
                .frame(height: 10)
                
                Text(percentText)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(progressColor)
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .padding(.vertical, 6)
    }
}

struct BudgetEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    var budget: Budget?
    
    @State private var category: String = "Food & Dining"
    @State private var limit: Double = 0.0
    
    let categories = Category.expenseCategories
    
    var body: some View {
        NavigationView {
            Form {
                Picker("Category", selection: $category) {
                    ForEach(categories, id: \.self) { cat in
                        Text(cat).tag(cat)
                    }
                }
                // Allowed category editing as requested
                // .disabled(budget != nil) 
                
                TextField("Monthly Limit", value: $limit, format: .currency(code: "INR"))
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
            }
            .navigationTitle(budget == nil ? "New Budget" : "Edit Budget")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let existing = budget {
                            existing.category = category
                            existing.monthlyLimit = limit
                        } else {
                            let new = Budget(category: category, monthlyLimit: limit)
                            modelContext.insert(new)
                        }
                        dismiss()
                    }
                    .disabled(limit == 0)
                }
                
                if budget != nil {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Delete", role: .destructive) {
                            if let existing = budget {
                                modelContext.delete(existing)
                                dismiss()
                            }
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .onAppear {
                if let b = budget {
                    category = b.category
                    limit = b.monthlyLimit
                }
            }
        }
    }
}
