import SwiftUI
import SwiftData

struct BudgetProposal: Identifiable, Codable {
    var id: String { category }
    let category: String
    var suggestedLimit: Double
    let currentAverage: Double
    let reason: String
    var isIncluded: Bool = true
    
    enum CodingKeys: String, CodingKey {
        case category, suggestedLimit, currentAverage, reason
    }
}

struct BudgetSuggestionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var existingBudgets: [Budget]
    
    // Accept proposals to edit/review
    @State var proposals: [BudgetProposal]
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    Text("Finlytics has analyzed your spending and suggests the following changes.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                }
                
                ForEach($proposals) { $proposal in
                    Section {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(proposal.category)
                                    .font(.headline)
                                Text(proposal.reason)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                
                                HStack {
                                    Text("Avg: \(proposal.currentAverage, format: .currency(code: "INR"))")
                                        .font(.caption2)
                                        .padding(4)
                                        .background(Color.gray.opacity(0.1))
                                        .cornerRadius(4)
                                }
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: $proposal.isIncluded)
                                .labelsHidden()
                        }
                        
                        if proposal.isIncluded {
                            HStack {
                                Text("Limit:")
                                TextField("Limit", value: $proposal.suggestedLimit, format: .currency(code: "INR"))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Review Suggestions")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply (\(proposals.filter(\.isIncluded).count))") {
                        applyChanges()
                    }
                }
            }
        }
    }
    
    private func applyChanges() {
        let toApply = proposals.filter { $0.isIncluded }
        
        for proposal in toApply {
            if let existing = existingBudgets.first(where: { $0.category == proposal.category }) {
                existing.monthlyLimit = proposal.suggestedLimit
            } else {
                let newBudget = Budget(category: proposal.category, monthlyLimit: proposal.suggestedLimit)
                modelContext.insert(newBudget)
            }
        }
        dismiss()
    }
}
