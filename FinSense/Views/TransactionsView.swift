import SwiftUI
import SwiftData

struct TransactionsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var tutorialManager: TutorialManager
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    
    @State private var searchText = ""
    @State private var selectedCategory: String?
    @State private var editingTransaction: Transaction?
    @State private var showingAddSheet = false
    
    // Bulk Selection State
    @State private var selection = Set<Transaction>()
    
    var filteredTransactions: [Transaction] {
        transactions.filter { tx in
            let matchesSearch = searchText.isEmpty || tx.merchant.localizedCaseInsensitiveContains(searchText) || tx.category.localizedCaseInsensitiveContains(searchText)
            let matchesCategory = selectedCategory == nil || tx.category == selectedCategory
            return matchesSearch && matchesCategory
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
                        .swipeActions {
                            if !isSelectionMode {
                                Button(role: .destructive) {
                                    modelContext.delete(transaction)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
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
                AddTransactionView()
            }
            .sheet(item: $editingTransaction) { transaction in
                AddTransactionView(existingTransaction: transaction)
            }
            .onChange(of: transactions.count) { oldCount, newCount in
                if newCount > oldCount {
                    tutorialManager.completeStep(.addTransaction)
                }
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
    
    var body: some View {
        HStack {
            Image(systemName: Category.icon(for: transaction.category))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Category.color(for: transaction.category))
                .clipShape(Circle())
            
            VStack(alignment: .leading) {
                Text(transaction.merchant)
                    .font(.headline)
                Text(transaction.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
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
                .font(.footnote)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.indigo : Color.gray.opacity(0.1))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(20)
        }
    }
}
