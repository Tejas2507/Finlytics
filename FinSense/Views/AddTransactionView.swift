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
    @Query private var merchantProfiles: [MerchantProfile]
    
    // Optional transaction for editing
    var existingTransaction: Transaction? = nil
    var preselectedProject: String? = nil
    
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
    @State private var selectedProjects: Set<String> = []
    @State private var showingProjectPicker = false
    
    @Query(sort: \Project.dateCreated, order: .reverse) private var projects: [Project]
    
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
                
                DatePicker("Date & Time", selection: $date, displayedComponents: [.date, .hourAndMinute])
                
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
            
            // Project Tagger
            if !projects.filter({ !$0.isArchived && !$0.isHidden }).isEmpty {
                let activeProjects = projects.filter({ !$0.isArchived && !$0.isHidden })
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(activeProjects.prefix(5)) { project in
                                ProjectChip(
                                    project: project,
                                    isSelected: selectedProjects.contains(project.name)
                                ) {
                                    if selectedProjects.contains(project.name) {
                                        selectedProjects.remove(project.name)
                                    } else {
                                        selectedProjects.insert(project.name)
                                    }
                                }
                            }
                            
                            if activeProjects.count > 5 {
                                Button {
                                    showingProjectPicker = true
                                } label: {
                                    Text("See All (\(activeProjects.count))")
                                        .font(.caption)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color(.systemGray6))
                                        .foregroundColor(.indigo)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    HStack {
                        Text("Tag to Projects")
                        Spacer()
                        if activeProjects.count <= 5 {
                            Button("See All") { showingProjectPicker = true }
                                .font(.caption)
                                .textCase(.none)
                        }
                    }
                } footer: {
                    Text("Link this transaction to one or more projects (trips, events, etc.).")
                }
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
                selectedProjects = Set(tx.projectNames)
            } else if let preProject = preselectedProject {
                selectedProjects = [preProject]
            }
        }
        .alert("Smart Paste", isPresented: $showPasteAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(pastedContent)
        }
        .sheet(isPresented: $showingProjectPicker) {
            NavigationView {
                ProjectPickerSheet(
                    selectedProjects: $selectedProjects,
                    projects: projects.filter { !$0.isArchived && !$0.isHidden }
                )
            }
        }
    }
    
    private func saveTransaction() {
        let canonicalMerchantKey = MerchantResolver.shared.resolveOrCreateKey(
            for: merchant,
            defaultCategory: selectedCategory,
            profiles: merchantProfiles,
            modelContext: modelContext
        )
        if let tx = existingTransaction {
            // Update existing
            tx.amount = amount
            tx.merchant = merchant
            tx.date = date
            tx.notes = notes
            tx.type = selectedType
            tx.category = selectedCategory
            tx.isHidden = isHidden
            tx.projectNames = Array(selectedProjects)
            tx.canonicalMerchantKey = canonicalMerchantKey
        } else {
            // Create new
            let transaction = Transaction(
                amount: amount,
                date: date,
                merchant: merchant,
                notes: notes,
                type: selectedType,
                category: selectedCategory,
                isHidden: isHidden,
                canonicalMerchantKey: canonicalMerchantKey
            )
            transaction.projectNames = Array(selectedProjects)
            modelContext.insert(transaction)
        }
        try? modelContext.save()
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

// MARK: - Project Chip
struct ProjectChip: View {
    let project: Project
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(project.emoji)
                Text(project.name)
                    .lineLimit(1)
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.indigo.opacity(0.15) : Color(.systemGray6))
            .foregroundColor(isSelected ? .indigo : .primary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.indigo : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Project Picker Sheet
struct ProjectPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedProjects: Set<String>
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
                        if selectedProjects.contains(project.name) {
                            selectedProjects.remove(project.name)
                        } else {
                            selectedProjects.insert(project.name)
                        }
                    } label: {
                        HStack {
                            Text(project.emoji)
                            Text(project.name)
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedProjects.contains(project.name) {
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
            .searchable(text: $searchText, prompt: "Search Projects")
            .navigationTitle("Select Projects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
#Preview {
    AddTransactionView()
        .modelContainer(for: Transaction.self, inMemory: true)
}

