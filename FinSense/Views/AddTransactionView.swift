import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
#endif

struct AddTransactionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allTransactions: [Transaction]
    
    // Optional transaction for editing
    var existingTransaction: Transaction? = nil
    
    @State private var amount: Double = 0.0
    @State private var merchant: String = ""
    @State private var date: Date = Date()
    @State private var notes: String = ""
    @State private var selectedType: TransactionType = .expense
    @State private var selectedCategory: String = "Food & Dining"
    @State private var showMerchantSuggestions = false
    
    // For Smart Paste alert
    @State private var showPasteAlert = false
    @State private var pastedContent = ""
    @State private var isProcessingPaste = false
    @State private var isHidden = false
    
    var categories: [String] {
        selectedType == .expense ? Category.expenseCategories : Category.incomeCategories
    }
    
    // Unique merchants from history with their most common category
    var merchantHistory: [(merchant: String, category: String)] {
        let merchants = Dictionary(grouping: allTransactions) { $0.merchant.lowercased() }
        return merchants.compactMap { key, transactions in
            guard let first = transactions.first else { return nil }
            // Find most common category for this merchant
            let categoryCounts = Dictionary(grouping: transactions) { $0.category }
            let mostCommon = categoryCounts.max(by: { $0.value.count < $1.value.count })?.key ?? first.category
            return (first.merchant, mostCommon)
        }.sorted { $0.merchant < $1.merchant }
    }
    
    var filteredMerchants: [(merchant: String, category: String)] {
        guard !merchant.isEmpty else { return [] }
        return merchantHistory.filter { $0.merchant.lowercased().contains(merchant.lowercased()) }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    Picker("Type", selection: $selectedType) {
                        ForEach(TransactionType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedType) {
                        // Reset category only if it doesn't match the new type group
                        if !categories.contains(selectedCategory) {
                            selectedCategory = categories.first ?? "Other"
                        }
                    }
                }
                
                Section("Details") {
                    TextField("Amount", value: $amount, format: .currency(code: "INR"))
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .font(.title3)
                    
                    // Merchant with autocomplete
                    VStack(alignment: .leading, spacing: 0) {
                        TextField("Merchant / Source", text: $merchant)
                            .onChange(of: merchant) {
                                showMerchantSuggestions = !filteredMerchants.isEmpty && merchant.count >= 2
                            }
                        
                        if showMerchantSuggestions {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(filteredMerchants.prefix(5), id: \.merchant) { item in
                                        Button {
                                            merchant = item.merchant
                                            // Auto-select category
                                            if categories.contains(item.category) {
                                                selectedCategory = item.category
                                            }
                                            showMerchantSuggestions = false
                                        } label: {
                                            HStack {
                                                Image(systemName: Category.icon(for: item.category))
                                                    .foregroundColor(Category.color(for: item.category))
                                                    .frame(width: 24)
                                                VStack(alignment: .leading) {
                                                    Text(item.merchant)
                                                        .foregroundColor(.primary)
                                                    Text(item.category)
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                                Spacer()
                                            }
                                            .padding(.vertical, 8)
                                            .padding(.horizontal, 4)
                                        }
                                        Divider()
                                    }
                                }
                            }
                            .frame(maxHeight: 150)
                            .background(Color(.systemBackground))
                            .cornerRadius(8)
                            .shadow(radius: 2)
                        }
                    }
                    
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(categories, id: \.self) { category in
                            HStack {
                                Image(systemName: Category.icon(for: category))
                                Text(category)
                            }
                            .tag(category)
                        }
                    }
                }
                
                Section("Notes") {
                    TextField("Optional notes", text: $notes)
                }
                
                if existingTransaction != nil {
                    Section {
                        Toggle(isOn: $isHidden) {
                            Label("Hide Transaction", systemImage: "eye.slash")
                        }
                        .tint(.purple)
                    } footer: {
                        Text("Hidden transactions are excluded from the transactions list but still counted in all calculations.")
                    }
                }
                
                Section {
                    Button(action: performSmartPaste) {
                        if isProcessingPaste {
                            HStack {
                                Text("Analyzing Clipboard...")
                                Spacer()
                                ProgressView()
                            }
                        } else {
                            Text("Read from Clipboard (Smart Paste)")
                        }
                    }
                    .disabled(isProcessingPaste)
                    .foregroundColor(.blue)
                }
            }
            .navigationTitle(existingTransaction == nil ? "Add Transaction" : "Edit Transaction")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                if let tx = existingTransaction {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Delete", role: .destructive) {
                            modelContext.delete(tx)
                            dismiss()
                        }
                        .foregroundColor(.red)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTransaction()
                    }
                    .disabled(merchant.isEmpty || amount == 0)
                }
            }
            .onAppear {
                if let tx = existingTransaction {
                    // Pre-fill fields
                    amount = tx.amount
                    merchant = tx.merchant
                    date = tx.date
                    notes = tx.notes
                    selectedType = tx.type
                    selectedCategory = tx.category
                    isHidden = tx.isHidden
                }
            }
            .alert("Smart Paste", isPresented: $showPasteAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(pastedContent)
            }
        }
    }
    
    private func saveTransaction() {
        if let tx = existingTransaction {
            // Update existing
            tx.amount = amount
            tx.merchant = merchant
            tx.date = date
            tx.notes = notes
            tx.type = selectedType
            tx.category = selectedCategory
            tx.isHidden = isHidden
        } else {
            // Create new
            let transaction = Transaction(
                amount: amount,
                date: date,
                merchant: merchant,
                notes: notes,
                type: selectedType,
                category: selectedCategory
            )
            modelContext.insert(transaction)
        }
        dismiss()
    }
    
    private func performSmartPaste() {
        var clipboardContent: String? = nil
        
        #if os(iOS)
        if let string = UIPasteboard.general.string {
            clipboardContent = string
        }
        #elseif os(macOS)
        if let string = NSPasteboard.general.string(forType: .string) {
            clipboardContent = string
        }
        #endif
        
        guard let string = clipboardContent else {
            pastedContent = "Clipboard is empty"
            showPasteAlert = true
            return
        }
        
        isProcessingPaste = true
        Task {
            do {
                let parsed = try await AIManager.shared.parseTransaction(from: string)
                
                await MainActor.run {
                    if let newAmount = parsed.amount { self.amount = newAmount }
                    if let newMerchant = parsed.merchant { self.merchant = newMerchant }
                    
                    if let typeString = parsed.type, let type = TransactionType(rawValue: typeString.capitalized) {
                        self.selectedType = type
                    }
                    
                    if let cat = parsed.category {
                        // Basic category matching or fallback
                        if categories.contains(cat) {
                            self.selectedCategory = cat
                        } else {
                            // Try to match partial string or default
                             self.selectedCategory = categories.first(where: { $0.contains(cat) || cat.contains($0) }) ?? (self.selectedType == .expense ? "Other" : "Salary")
                        }
                    }
                    
                    pastedContent = "Parsed: \(parsed.merchant ?? "?") - \(parsed.amount ?? 0)"
                    isProcessingPaste = false
                    showPasteAlert = true
                }
            } catch {
                await MainActor.run {
                    pastedContent = "Smart Parse Failed: \(error.localizedDescription). Falling back to basic parser."
                    // Fallback to basic regex
                    let basic = Transaction.parse(from: string)
                    if let am = basic.amount { self.amount = am }
                    if let merch = basic.merchant { self.merchant = merch }
                    if let tp = basic.type { self.selectedType = tp }
                    
                    isProcessingPaste = false
                    showPasteAlert = true
                }
            }
        }
    }
}

#Preview {
    AddTransactionView()
        .modelContainer(for: Transaction.self, inMemory: true)
}
