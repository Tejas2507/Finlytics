import SwiftUI
import Charts

// MARK: - Month Picker Sheet
struct MonthPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let availableMonths: [Date]
    let transactions: [Transaction]
    let monthlySalary: Double
    
    @State private var selectedMonth: Date? = nil
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Select a Month")
                    .font(.headline)
                    .padding(.top)
                
                // Calendar-style month grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                    ForEach(availableMonths, id: \.self) { month in
                        MonthCell(month: month, isSelected: selectedMonth == month)
                            .onTapGesture {
                                selectedMonth = month
                            }
                    }
                }
                .padding()
                
                Spacer()
            }
            .navigationTitle("Previous Months")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: Binding(
                get: { selectedMonth.map { IdentifiableDate(date: $0) } },
                set: { selectedMonth = $0?.date }
            )) { identifiable in
                PastMonthDetailView(
                    targetMonth: identifiable.date,
                    transactions: transactions,
                    monthlySalary: monthlySalary
                )
            }
        }
    }
}

// Helper for sheet presentation
struct IdentifiableDate: Identifiable {
    let date: Date
    var id: Date { date }
}

// MARK: - Month Cell
struct MonthCell: View {
    let month: Date
    let isSelected: Bool
    
    var monthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: month)
    }
    
    var year: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.string(from: month)
    }
    
    var body: some View {
        VStack(spacing: 4) {
            Text(monthName)
                .font(.headline)
            Text(year)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(isSelected ? Color.blue.opacity(0.2) : Color(.systemGray6))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - Past Month Detail View
struct PastMonthDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let targetMonth: Date
    let transactions: [Transaction]
    let monthlySalary: Double
    
    // Computed properties for the target month
    var monthTransactions: [Transaction] {
        MonthlyStats.shared.getTransactions(for: targetMonth, from: transactions)
    }
    
    var monthExpenses: [Transaction] { monthTransactions.filter { MonthlyStats.isSpending($0) } }
    var monthIncome: [Transaction] { monthTransactions.filter { $0.type == .income } }
    var monthInvestments: [Transaction] { 
        monthTransactions.filter { $0.type == .expense && $0.category.lowercased().contains("invest") } 
    }
    
    var totalExpense: Double { monthExpenses.reduce(0) { $0 + $1.amount } }
    var totalIncome: Double { monthIncome.reduce(0) { $0 + $1.amount } }
    var totalInvested: Double { monthInvestments.reduce(0) { $0 + $1.amount } }
    
    var monthName: String {
        MonthlyStats.shared.formatMonth(targetMonth)
    }
    
    // Category breakdown
    var categoryBreakdown: [(name: String, amount: Double)] {
        MonthlyStats.shared.getCategoryBreakdown(for: targetMonth, from: transactions)
    }
    
    // Top merchants
    var topMerchants: [(name: String, amount: Double)] {
        let grouped = Dictionary(grouping: monthExpenses) { $0.merchant }
        return grouped.map { (name: $0.key, amount: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.amount > $1.amount }
            .prefix(5)
            .map { $0 }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Hero Stats
                    VStack(spacing: 8) {
                        Text("₹\(Int(totalExpense).formatted())")
                            .font(.system(size: 42, weight: .bold))
                        Text("Total Spent")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical)
                    
                    // Quick Stats - Show Invested instead of Save Rate
                    HStack(spacing: 12) {
                        StatPill(title: "Income", value: "₹\(Int(totalIncome).formatted())", color: .green)
                        StatPill(title: "Invested", value: "₹\(Int(totalInvested).formatted())", color: .indigo)
                    }
                    
                    // Category Breakdown
                    if !categoryBreakdown.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Categories")
                                .font(.headline)
                            
                            HStack(spacing: 16) {
                                Chart(categoryBreakdown.prefix(6), id: \.name) { item in
                                    SectorMark(
                                        angle: .value("Amount", item.amount),
                                        innerRadius: .ratio(0.55),
                                        angularInset: 1
                                    )
                                    .foregroundStyle(Category.color(for: item.name))
                                    .cornerRadius(4)
                                }
                                .frame(width: 120, height: 120)
                                
                                VStack(alignment: .leading, spacing: 5) {
                                    ForEach(categoryBreakdown.prefix(6), id: \.name) { item in
                                        HStack(spacing: 6) {
                                            Circle().fill(Category.color(for: item.name)).frame(width: 8, height: 8)
                                            Text(item.name).font(.caption).lineLimit(1)
                                            Spacer()
                                            Text("₹\(Int(item.amount).formatted())")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(16)
                    }
                    
                    // Top Merchants
                    if !topMerchants.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Top Merchants")
                                .font(.headline)
                            
                            ForEach(topMerchants, id: \.name) { merchant in
                                HStack {
                                    Text(merchant.name)
                                    Spacer()
                                    Text("₹\(Int(merchant.amount).formatted())")
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(16)
                    }
                }
                .padding()
            }
            .navigationTitle(monthName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
