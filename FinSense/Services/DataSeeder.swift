import Foundation
import SwiftData

class DataSeeder {
    static let shared = DataSeeder()
    
    @MainActor
    func generateDemoData(modelContext: ModelContext) {
        // Clear existing data? Maybe better to just add to it or let user clear manually.
        // For a "Demo" button, usually we append or users manually clear.
        // Let's just append for safety, but ensure we cover 3 months.
        
        let calendar = Calendar.current
        let now = Date()
        
        // Generate for last 3 months
        for i in 0..<3 {
            guard let monthDate = calendar.date(byAdding: .month, value: -i, to: now) else { continue }
            
            // 1. ADD SALARY (~40k)
            // Randomize day between 1st and 5th
            if let salaryDate = calendar.date(byAdding: .day, value: Int.random(in: 0...4), to: startOfMonth(for: monthDate)) {
                let salary = Transaction(
                    amount: 40000,
                    date: salaryDate,
                    merchant: "Tech Corp",
                    notes: "Monthly Salary",
                    type: .income,
                    category: "Salary"
                )
                modelContext.insert(salary)
            }
            
            // 2. ADD EXPENSES
            // Generate distinct expenses to look realistic
            
            // Rent/Utilities
            createTransaction(context: modelContext, amount: 12000, date: randomDate(in: monthDate), merchant: "Landlord", category: "Bills & Utilities", type: .expense)
            createTransaction(context: modelContext, amount: 1500, date: randomDate(in: monthDate), merchant: "Electricity Board", category: "Bills & Utilities", type: .expense)
            
            // Food (Multiple)
            for _ in 0..<5 {
                createTransaction(context: modelContext, amount: Double.random(in: 200...800), date: randomDate(in: monthDate), merchant: ["Swiggy", "Zomato", "Grocery Store", "Cafe"].randomElement()!, category: "Food & Dining", type: .expense)
            }
            
            // Transport
            for _ in 0..<4 {
                createTransaction(context: modelContext, amount: Double.random(in: 50...300), date: randomDate(in: monthDate), merchant: ["Uber", "Ola", "Metro"].randomElement()!, category: "Transportation", type: .expense)
            }
            
            // Shopping
            createTransaction(context: modelContext, amount: Double.random(in: 1000...3000), date: randomDate(in: monthDate), merchant: "Amazon", category: "Shopping", type: .expense)
            
            // Investment
             createTransaction(context: modelContext, amount: 5000, date: randomDate(in: monthDate), merchant: "SIP Fund", category: "Investment", type: .expense)
        }
    }
    
    private func startOfMonth(for date: Date) -> Date {
        let calendar = Calendar.current
        return calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }
    
    private func randomDate(in month: Date) -> Date {
        let calendar = Calendar.current
        let start = startOfMonth(for: month)
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? Date()
        
        let timeInterval = end.timeIntervalSince(start)
        let randomInterval = TimeInterval(arc4random_uniform(UInt32(timeInterval)))
        
        return start.addingTimeInterval(randomInterval)
    }
    
    @MainActor
    private func createTransaction(context: ModelContext, amount: Double, date: Date, merchant: String, category: String, type: TransactionType) {
        let tx = Transaction(amount: amount, date: date, merchant: merchant, type: type, category: category)
        context.insert(tx)
    }
}
