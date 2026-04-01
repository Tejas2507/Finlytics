import SwiftUI
import SwiftData

struct TransactionsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var tutorialManager: TutorialManager
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \Project.dateCreated, order: .reverse) private var projects: [Project]
    
    @State private var searchText = ""
    @State private var selectedCategory: String?
    @State private var editingTransaction: Transaction?
    @State private var showingAddSheet = false
    
    // Bulk Selection State
    @State private var selection = Set<Transaction>()
    @State private var projectTagTransaction: Transaction? = nil
    
    var filteredTransactions: [Transaction] {
        transactions.filter { tx in
            let isVisible = !tx.isHidden  // Hidden transactions stay in data, just not shown here
            let matchesSearch = searchText.isEmpty || tx.merchant.localizedCaseInsensitiveContains(searchText) || tx.category.localizedCaseInsensitiveContains(searchText)
            let matchesCategory = selectedCategory == nil || tx.category == selectedCategory
            return isVisible && matchesSearch && matchesCategory
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Selection mode banner
                if isSelectionMode {
                    HStack {
                        Text("\(selection.count) selected")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Button("Cancel") {
                            exitSelectionMode()
                        }
                        .foregroundColor(.blue)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                }
                
                // Category Filter ScrollView
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        FilterButton(title: "All", isSelected: selectedCategory == nil) {
                            selectedCategory = nil
                        }
                        
                        ForEach(Category.expenseCategories, id: \.self) { cat in
                            FilterButton(title: cat, isSelected: selectedCategory == cat) {
                                selectedCategory = cat
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
                
                List {
                    ForEach(filteredTransactions) { transaction in
                        HStack {
                            if isSelectionMode {
                                Image(systemName: selection.contains(transaction) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selection.contains(transaction) ? .blue : .gray)
                                    .font(.title2)
                            }
                            
                            TransactionRow(transaction: transaction)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isSelectionMode {
                                toggleSelection(transaction)
                            } else {
                                editingTransaction = transaction
                            }
                        }
                        .onLongPressGesture {
                            if !isSelectionMode {
                                isSelectionMode = true
                            }
                            toggleSelection(transaction)
                        }
                        .swipeActions(edge: .trailing) {
                            if !isSelectionMode {
                                Button(role: .destructive) {
                                    modelContext.delete(transaction)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if !isSelectionMode {
                                Button {
                                    withAnimation {
                                        transaction.isHidden = true
                                    }
                                } label: {
                                    Label("Hide", systemImage: "eye.slash.fill")
                                }
                                .tint(.purple)
                                
                                Button {
                                    projectTagTransaction = transaction
                                } label: {
                                    Label("Project", systemImage: "flag.fill")
                                }
                                .tint(.indigo)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                
                // Delete bar at bottom when in selection mode
                if isSelectionMode && !selection.isEmpty {
                    Button(action: deleteSelection) {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text("Delete \(selection.count) Transaction\(selection.count > 1 ? "s" : "")")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                    }
                }
            }
            .navigationTitle("Transactions")
            .searchable(text: $searchText, prompt: "Search merchants or categories")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !isSelectionMode {
                        Button {
                            showingAddSheet = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                        }
                        .tutorialTarget(.addTransaction)
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                NavigationView {
                    AddTransactionView()
                }
            }
            .sheet(item: $editingTransaction) { transaction in
                NavigationView {
                    AddTransactionView(existingTransaction: transaction)
                }
            }
            .onChange(of: transactions.count) { oldCount, newCount in
                if newCount > oldCount {
                    tutorialManager.completeStep(.addTransaction)
                }
            }
            .sheet(item: $projectTagTransaction) { tx in
                ProjectTagSheet(transaction: tx, projects: projects.filter { !$0.isArchived && !$0.isHidden })
            }
        }
    }
    
    // MARK: - Selection Helpers
    @State private var isSelectionMode = false
    
    private func toggleSelection(_ transaction: Transaction) {
        if selection.contains(transaction) {
            selection.remove(transaction)
        } else {
            selection.insert(transaction)
        }
    }
    
    private func exitSelectionMode() {
        selection.removeAll()
        isSelectionMode = false
    }
    
    private func deleteSelection() {
        for transaction in selection {
            modelContext.delete(transaction)
        }
        exitSelectionMode()
    }
}

struct TransactionRow: View {
    let transaction: Transaction
    @Query private var allProjects: [Project]
    
    // Dictionary mapping project name to emoji
    private var emojiCache: [String: String] {
        return Dictionary(uniqueKeysWithValues: allProjects.map { ($0.name, $0.emoji) })
    }
    
    var body: some View {
        HStack {
            Image(systemName: Category.icon(for: transaction.category))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Category.color(for: transaction.category))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.merchant)
                    .font(.headline)
                
                HStack(spacing: 4) {
                    Text(transaction.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if !transaction.projectNames.isEmpty {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        let uniqueProjects = Array(Set(transaction.projectNames))
                        let visibleProjects = uniqueProjects.prefix(3)
                        
                        HStack(spacing: 2) {
                            ForEach(visibleProjects, id: \.self) { name in
                                Text(emojiCache[name] ?? "🎯")
                                    .font(.caption2)
                            }
                            if uniqueProjects.count > 3 {
                                Text("...")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            
            Spacer()
            
            Text(transaction.amount, format: .currency(code: "INR"))
                .font(.body)
                .bold()
                .foregroundColor(transaction.type == .income ? .green : .primary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    TransactionsView()
        .modelContainer(for: Transaction.self, inMemory: true)
}

struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    isSelected ?
                    AnyShapeStyle(LinearGradient(colors: [.indigo, .purple], startPoint: .leading, endPoint: .trailing)) :
                    AnyShapeStyle(Color(.systemGray5))
                )
                .foregroundColor(isSelected ? .white : .secondary)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Project Tag Sheet (Multi-Select)
struct ProjectTagSheet: View {
    @Environment(\.dismiss) private var dismiss
    let transaction: Transaction
    let projects: [Project]
    @State private var searchText = ""
    
    var filteredProjects: [Project] {
        if searchText.isEmpty { return projects }
        return projects.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        NavigationView {
            List {
                ForEach(filteredProjects) { project in
                    Button {
                        if transaction.projectNames.contains(project.name) {
                            transaction.projectNames.removeAll { $0 == project.name }
                        } else {
                            transaction.projectNames.append(project.name)
                        }
                    } label: {
                        HStack {
                            Text(project.emoji)
                            Text(project.name)
                                .foregroundColor(.primary)
                            Spacer()
                            if transaction.projectNames.contains(project.name) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.indigo)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundColor(.secondary.opacity(0.4))
                            }
                        }
                    }
                }
                
                if !transaction.projectNames.isEmpty {
                    Button(role: .destructive) {
                        transaction.projectNames.removeAll()
                        dismiss()
                    } label: {
                        Label("Remove All Tags", systemImage: "xmark.circle")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search Projects")
            .navigationTitle("Tag to Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
