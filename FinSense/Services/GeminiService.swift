import Foundation
import SwiftData
import GoogleGenerativeAI // User must add this package

// Placeholder until package is added
class GeminiService {
    static let shared = GeminiService()
    
    // Parsed result structure
    struct ParsedTransaction: Codable {
        let amount: Double?
        let merchant: String?
        let category: String?
        let type: String? // "Income" or "Expense"
    }
    
    // Chat with Financial Agent
    func generateResponse(for prompt: String, context: [Transaction], budgets: [Budget] = [], monthlySalary: Double = 0.0, apiKey: String) async throws -> String {
        guard !apiKey.isEmpty else { return "Please set your Google Gemini API Key in Settings to chat." }
        
        // Read model selection from UserDefaults (SettingsView uses AppStorage)
        let selectedModel = UserDefaults.standard.string(forKey: "aiModel") ?? "gemini-2.5-flash"
        let model = GenerativeModel(name: selectedModel, apiKey: apiKey)
        
        // Calculate Financial Context
        let totalIncome = context.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        let totalExpense = context.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
        let balance = totalIncome - totalExpense
        
        // Recent Transactions (Optimized Format for Token Efficiency)
        // Format: Date|Merchant|Amt|Cat|Type
        let recentTx = context.prefix(40).map {
            "\($0.date.formatted(date: .numeric, time: .omitted))|\($0.merchant)|\($0.amount)|\($0.category)|\($0.type == .income ? "IN" : "EX")"
        }.joined(separator: "\n")
        
        // Budget Context
        let budgetContext = budgets.map { budget in
            let spent = context.filter { $0.category == budget.category && $0.type == .expense }.reduce(0) { $0 + $1.amount }
            let pct = budget.monthlyLimit > 0 ? Int((spent / budget.monthlyLimit) * 100) : 0
            return "\(budget.category): \(Int(spent))/\(Int(budget.monthlyLimit)) (\(pct)%)"
        }.joined(separator: "; ")
        
        let salaryContext = monthlySalary > 0 ? "Monthly Salary: \(monthlySalary)" : "Monthly Salary: Not set"
        
        let systemPrompt = """
    You are Finlytics, a smart financial assistant for Indian users. ALL amounts are in Indian Rupees (₹ INR).
    
    ## Financial Context (All in ₹ INR)
    - Total Balance: ₹\(Int(balance))
    - Total Income: ₹\(Int(totalIncome))
    - Total Expenses: ₹\(Int(totalExpense))
    - \(salaryContext)
    
    ## Budgets
    \(budgetContext.isEmpty ? "No active budgets." : budgetContext)
    
    ## Recent Transactions (Last 30)
    \(recentTx)
    
    User Question: \(prompt)
    
    **Instructions:**
    - Always respond with amounts in ₹ (Indian Rupees).
    - Answer concisely and helpfully.
    - **ALWAYS use Markdown tables** when presenting lists of numbers, comparisons, or expense breakdowns.
    - Use **bold** for key figures and important takeaways.
    - If suggesting cuts, look at the highest expense categories.
    """
        
        let response = try await model.generateContent(systemPrompt)
        return response.text ?? "I couldn't generate a response."
    }
    
    // Smart Paste: Parse text into transaction details
    func parseTransaction(from text: String, apiKey: String) async throws -> ParsedTransaction {
        guard !apiKey.isEmpty else { throw NSError(domain: "GeminiService", code: 401, userInfo: [NSLocalizedDescriptionKey: "API Key missing"]) }
        
        let selectedModel = UserDefaults.standard.string(forKey: "aiModel") ?? "gemini-2.5-flash"
        let model = GenerativeModel(name: selectedModel, apiKey: apiKey)
        
        let prompt = """
        Extract the following transaction details from this text: "\(text)"
        
        Return JSON with these keys:
        - "amount": Double (numeric only)
        - "merchant": String (name of place/person)
        - "category": String (best guess category e.g., Food, Transport, Salary)
        - "type": String ("Income" or "Expense")
        
        If a field is missing, use null.
        Example: {"amount": 500.0, "merchant": "Uber", "category": "Transport", "type": "Expense"}
        """
        
        let response = try await model.generateContent(prompt)
        guard let jsonString = response.text else { throw NSError(domain: "GeminiService", code: 500, userInfo: [NSLocalizedDescriptionKey: "No response"]) }
        
        // Clean markdown code blocks if present
        let cleanedJson = jsonString.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
        
        guard let data = cleanedJson.data(using: .utf8) else { throw NSError(domain: "GeminiService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid data"]) }
        
        return try JSONDecoder().decode(ParsedTransaction.self, from: data)
    }
    
    // Smart Budgeting: Analyze CURRENT MONTH history and suggest monthly budgets
    func generateBudgetSuggestions(history: [Transaction], apiKey: String) async throws -> String {
        guard !apiKey.isEmpty else { return "" }
        let model = GenerativeModel(name: "gemini-2.5-flash", apiKey: apiKey)
        
        // Filter to current month expenses only
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let currentMonthExpenses = history.filter { $0.date >= startOfMonth && $0.type == .expense }
        
        let contextString = currentMonthExpenses.map {
            "\($0.category): ₹\(Int($0.amount))"
        }.joined(separator: "\n")
        
        let totalSpent = currentMonthExpenses.reduce(0) { $0 + $1.amount }
        
        let prompt = """
        Analyze this user's CURRENT MONTH expenses (total: ₹\(Int(totalSpent))) and suggest MONTHLY budget limits for the top 3 spending categories.
        
        CURRENT MONTH EXPENSES (₹ INR):
        \(contextString.isEmpty ? "No expenses this month yet." : contextString)
        
        IMPORTANT: These are MONTHLY budgets. Suggest reasonable limits slightly above current spending to allow flexibility.
        
        OUTPUT FORMAT:
        Return ONLY a raw JSON array. No markdown, no explanations.
        [
            {
                "category": "String",
                "suggestedLimit": Double (monthly limit in INR),
                "currentAverage": Double (this month's spending in that category),
                "reason": "Short reason"
            }
        ]
        """
        
        let response = try await model.generateContent(prompt)
        let rawText = response.text ?? "[]"
        
        let cleaned = rawText
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            
        print("DEBUG: Gemini Budget Response -> \(cleaned)")
        return cleaned
    }
    
    // Insight Generation (Legacy)
    func generateInsight(context: [Transaction], promptTemplate: String, apiKey: String) async throws -> String {
        guard !apiKey.isEmpty else { return "Please configure API Key." }
        let model = GenerativeModel(name: "gemini-2.5-flash", apiKey: apiKey)
        
        // Prepare context
        let recentTx = context.prefix(50).map {
            "\($0.date.formatted(date: .numeric, time: .omitted)): \($0.merchant) (\($0.amount))"
        }.joined(separator: "\n")
        
        let fullPrompt = """
        Analyze these transactions:
        \(recentTx)
        
        Task: \(promptTemplate)
        
        Keep the response short, under 40 words. No markdown formatting like bold/italic unless specified.
        """
        
        let response = try await model.generateContent(fullPrompt)
        return response.text ?? "Could not generate insight."
    }
    
    // MARK: - Smart Insight (Rich Context)
    func generateSmartInsight(context: InsightEngine.FinancialContext, apiKey: String) async throws -> String {
        guard !apiKey.isEmpty else { throw NSError(domain: "GeminiService", code: 401, userInfo: [NSLocalizedDescriptionKey: "API Key missing"]) }
        
        let selectedModel = UserDefaults.standard.string(forKey: "aiModel") ?? "gemini-2.5-flash"
        let model = GenerativeModel(name: selectedModel, apiKey: apiKey)
        
        let prompt = """
        You are a witty financial coach who gives SHORT, punchy insights. 
        
        USER'S FINANCIAL SNAPSHOT:
        - Top spending category: \(context.topCategory.name) at ₹\(Int(context.topCategory.amount)) (\(context.topCategory.percent)% of total)
        - Average daily spend: ₹\(Int(context.avgDailySpend))
        - Highest single expense: \(context.highestExpense.map { "₹\(Int($0.amount)) at \($0.merchant)" } ?? "None")
        - Days since last investment: \(context.daysSinceInvestment.map { String($0) } ?? "No investments tracked")
        - Spending trend vs last month: \(context.spendingTrend > 0 ? "+\(context.spendingTrend)%" : "\(context.spendingTrend)%")
        - Projected month-end spend: ₹\(Int(context.projectedMonthEnd))
        - Days left in month: \(context.daysLeftInMonth)
        
        INSTRUCTIONS:
        Write ONE insight (max 100 characters). Use specific numbers. Be memorable, slightly funny. 
        Include future projection if relevant (e.g., "invest this and get X in Y years").
        Don't be preachy. No emojis. No markdown. Just plain text.
        
        Examples of good insights:
        - "₹3K/mo on Zomato = ₹14L in 20 years if invested"
        - "Shopping at 40%? Your wallet needs therapy"
        - "18 days, zero investing. Your future self is watching"
        
        Now write YOUR unique insight based on the data above:
        """
        
        let response = try await model.generateContent(prompt)
        let text = response.text ?? ""
        
        // Clean up response
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "*", with: "")
        
        // Ensure it's short enough
        if cleaned.count > 120 {
            return String(cleaned.prefix(117)) + "..."
        }
        return cleaned
    }
}

