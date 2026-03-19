import Foundation
import SwiftData
import GoogleGenerativeAI // User must add this package

// Placeholder until package is added
class AIManager {
    static let shared = AIManager()
    
    // Parsed result structure
    struct ParsedTransaction: Codable {
        let amount: Double?
        let merchant: String?
        let category: String?
        let type: String? // "Income" or "Expense"
    }
    
    // Unified Generation logic with AI Provider routing and Persona Injection
    func generateContent(systemPrompt: String) async throws -> String {
        let aiProvider = UserDefaults.standard.string(forKey: "aiProvider") ?? "gemini"
        let persona = UserDefaults.standard.string(forKey: "userAIPersona") ?? ""
        let personaInjection = persona.isEmpty ? "" : """
        
        
        --- HIDDEN BEHAVIORAL DOSSIER (The user does NOT see this) ---
        The following is a psychological profile of the user, generated from their spending patterns, onboarding answers, and chat history. Use it to deeply personalize your tone, advice, and approach.
        
        IMPORTANT RULES FOR USING THIS DOSSIER:
        • Use it NATURALLY — let it inform your tone and advice, but don't reference it explicitly.
        • Focus especially on 'Communication Guide' and 'Agent Instructions' for HOW to talk.
        • Only mention specific dossier insights when directly relevant to the user's question.
        • NEVER tell the user you have this profile. It should feel like you just "get" them.
        
        \(persona)
        --- END DOSSIER ---
        """
        let finalPrompt = systemPrompt + personaInjection
        
        if aiProvider == "gemini" {
            let apiKey = KeychainHelper.shared.read(for: "gemini_api_key") ?? ""
            guard !apiKey.isEmpty else { throw NSError(domain: "AIManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Gemini API Key missing"]) }
            return try await generateContentWithFallback(apiKey: apiKey, systemPrompt: finalPrompt)
        } else {
            let apiKey = KeychainHelper.shared.read(for: "openai_api_key") ?? ""
            guard !apiKey.isEmpty else { throw NSError(domain: "AIManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "OpenAI API Key missing"]) }
            return try await OpenAIService.shared.generateContent(apiKey: apiKey, systemPrompt: finalPrompt)
        }
    }

    // Helper to try selected model, then fallback to 2.5-flash if it fails
    private func generateContentWithFallback(apiKey: String, systemPrompt: String) async throws -> String {
        // Migration: Reset any old/invalid model values to default
        let validModels = ["gemini-flash-lite-latest", "gemini-2.5-flash"]
        var selectedModel = UserDefaults.standard.string(forKey: "aiModel") ?? "gemini-flash-lite-latest"
        
        if !validModels.contains(selectedModel) {
            selectedModel = "gemini-flash-lite-latest"
            UserDefaults.standard.set(selectedModel, forKey: "aiModel")
        }
        
        print("DEBUG: Using model \(selectedModel). Key length: \(apiKey.count)")
        
        let model = GenerativeModel(name: selectedModel, apiKey: apiKey)
        
        do {
            let response = try await model.generateContent(systemPrompt)
            return response.text ?? ""
        } catch {
            print("DEBUG: Primary model \(selectedModel) failed. Error: \(error.localizedDescription)")
            
            // If PRIMARY model fails, fallback to 2.5-flash
            print("DEBUG: Falling back to gemini-2.5-flash")
            let fallbackModel = GenerativeModel(name: "gemini-2.5-flash", apiKey: apiKey)
            do {
                let fallbackResponse = try await fallbackModel.generateContent(systemPrompt)
                return fallbackResponse.text ?? ""
            } catch {
                 throw NSError(domain: "GeminiService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Primary (\(selectedModel)) & Fallback (2.5) failed. Error: \(error.localizedDescription)"])
            }
        }
    }
    
    // Chat with Financial Agent — uses structured analytics + fuzzy TF-IDF fallback
    func generateResponse(for prompt: String, context: [Transaction], budgets: [Budget] = [], monthlySalary: Double = 0.0) async throws -> String {
        
        // ── LAYER 1: Structured Analytics (pre-computed, accurate) ──
        let richContext = MerchantAnalytics.shared.buildRichContext(
            transactions: context,
            userQuery: prompt
        )
        
        // ── LAYER 2: Fuzzy TF-IDF fallback (catches typos, niche queries) ──
        let keywords = extractKeywords(from: prompt)
        var rankedTransactions: [(Transaction, Int)] = context.map { tx in
            var score = 0
            let searchableText = "\(tx.merchant) \(tx.category) \(tx.type)".lowercased()
            for word in keywords {
                if searchableText.contains(word) { score += 1 }
            }
            let daysAgo = Calendar.current.dateComponents([.day], from: tx.date, to: Date()).day ?? 0
            if daysAgo < 30 { score += 1 }
            return (tx, score)
        }
        rankedTransactions.sort {
            if $0.1 == $1.1 { return $0.0.date > $1.0.date }
            return $0.1 > $1.1
        }
        
        // Only include fuzzy-matched rows that actually scored > 0 (relevant), max 20
        let fuzzyMatches = rankedTransactions.filter { $0.1 > 0 }.prefix(20).map { $0.0 }
        let fuzzyTxStr = fuzzyMatches.isEmpty ? "" : """
        
        FUZZY-MATCHED TRANSACTIONS (backup for typos/edge cases):
        \(fuzzyMatches.map { "\($0.date.formatted(date: .numeric, time: .omitted))|\($0.merchant)|₹\(Int($0.amount))|\($0.category)|\($0.type == .income ? "IN" : "EX")" }.joined(separator: "\n"))
        """
        
        // ── Budget Context ──
        let calendar = Calendar.current
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))!
        let currentMonthTx = context.filter { $0.date >= startOfMonth }
        let budgetContext = budgets.map { budget in
            let spent = currentMonthTx.filter { $0.category == budget.category && $0.type == .expense }.reduce(0) { $0 + $1.amount }
            let pct = budget.monthlyLimit > 0 ? Int((spent / budget.monthlyLimit) * 100) : 0
            return "\(budget.category): ₹\(Int(spent))/₹\(Int(budget.monthlyLimit)) (\(pct)%)"
        }.joined(separator: "; ")
        
        let salaryContext = monthlySalary > 0 ? "Monthly Salary: ₹\(Int(monthlySalary))" : "Monthly Salary: Not set"
        
        // ── THE PROMPT ──
        let systemPrompt = """
    You are Finlytics — a sharp, friendly financial advisor for Indian users. All amounts in ₹ (INR).
    
    ## Pre-Computed Analytics (USE THESE NUMBERS — they are accurate)
    \(richContext)
    \(fuzzyTxStr)
    
    ## Budgets
    \(budgetContext.isEmpty ? "No active budgets." : budgetContext)
    \(salaryContext)
    
    ## User Question
    \(prompt)
    
    ## RESPONSE RULES (VERY IMPORTANT):
    1. **BE CONCISE** — Answer in 3-5 bullet points. Max 120 words total. No fluff.
    2. **USE PRE-COMPUTED DATA** — The analytics above are pre-calculated and accurate. Use those numbers directly instead of trying to count raw transactions. 
    3. **POINTWISE FORMAT** — Use bullet points (•), not paragraphs. Each bullet = one clear insight.
    4. **TABLES** — Only use a simple 2-column vertical table (Label | Value) when the user asks for a comparison. Never use wide multi-column tables. Keep tables under 6 rows.
    5. **TONE** — Be a smart, witty financial friend. Not a corporate robot. Not a professor.
    6. **₹ ALWAYS** — All amounts in ₹ with no decimal places.
    7. **ADMIT GAPS** — If the data doesn't cover what the user asked, say so honestly. Don't hallucinate.
    8. **NO HISTORY DUMPS** — Never list raw transactions unless the user explicitly asks "show me every transaction at X".
    """
        
        do {
            let text = try await generateContent(systemPrompt: systemPrompt)
            if text.isEmpty { return "I couldn't generate a response." }
            return text
        } catch {
            if error.localizedDescription.contains("400") || error.localizedDescription.contains("403") {
                 let model = UserDefaults.standard.string(forKey: "aiModel") ?? "unknown"
                 return "Unable to access the selected AI model (\(model)). Attempted fallback failed. Please check your API Key."
            }
            return "Error: \(error.localizedDescription)"
        }
    }
    
    // Smart Paste: Parse text into transaction details
    func parseTransaction(from text: String) async throws -> ParsedTransaction {
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
        
        do {
            let jsonString = try await generateContent(systemPrompt: prompt)
            
            // Clean markdown code blocks if present
            let cleanedJson = jsonString.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
            
            guard let data = cleanedJson.data(using: .utf8) else { throw NSError(domain: "GeminiService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid data"]) }
            
            return try JSONDecoder().decode(ParsedTransaction.self, from: data)
        } catch {
            print("Smart Paste failed: \(error)")
            throw error
        }
    }
    
    // Smart Budgeting: Analyze history and suggest monthly budgets
    // Uses historical averages per actual calendar month
    func generateBudgetSuggestions(history: [Transaction]) async throws -> String {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        
        // Get all expenses
        let allExpenses = history.filter { $0.type == .expense && !$0.category.lowercased().contains("invest") }
        let currentMonthExpenses = allExpenses.filter { $0.date >= startOfMonth }
        
        // IMPORTANT: Only use PAST completed months for averages (exclude current running month)
        let pastExpenses = allExpenses.filter { $0.date < startOfMonth }
        let byMonth = Dictionary(grouping: pastExpenses) { tx in
            calendar.date(from: calendar.dateComponents([.year, .month], from: tx.date)) ?? tx.date
        }
        let completedMonthCount = byMonth.keys.count
        let hasHistoricalData = completedMonthCount >= 1  // At least 1 completed month
        
        let spendingData: String
        let dataSource: String
        let monthlyAverage: Double
        
        if hasHistoricalData {
            // Calculate per-category monthly averages using PAST months only
            let byCategory = Dictionary(grouping: pastExpenses) { $0.category }
            let categoryAverages = byCategory.map { category, txns in
                let total = txns.reduce(0) { $0 + $1.amount }
                let monthlyAvg = total / Double(completedMonthCount)
                return "\(category): ₹\(Int(monthlyAvg))/month (avg from \(completedMonthCount) months)"
            }.sorted { $0 > $1 }
            
            spendingData = categoryAverages.joined(separator: "\n")
            dataSource = "Actual averages from \(completedMonthCount) completed months"
            monthlyAverage = pastExpenses.reduce(0) { $0 + $1.amount } / Double(completedMonthCount)
        } else {
            // Fall back to current month projected to 30 days
            let dayOfMonth = calendar.component(.day, from: now)
            let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
            let totalSpent = currentMonthExpenses.reduce(0) { $0 + $1.amount }
            monthlyAverage = dayOfMonth > 0 ? (totalSpent / Double(dayOfMonth)) * Double(daysInMonth) : totalSpent
            
            spendingData = currentMonthExpenses.map {
                "\($0.category): ₹\(Int($0.amount))"
            }.joined(separator: "\n")
            dataSource = "Current month projected (\(dayOfMonth) days so far)"
        }
        
        // Get salary from UserDefaults
        let salary = UserDefaults.standard.double(forKey: "monthlySalary")
        
        let prompt = """
        Analyze this user's spending and suggest MONTHLY budget limits. All amounts in ₹ INR.
        
        DATA SOURCE: \(dataSource)
        - Monthly recurring income: \(salary > 0 ? "₹\(Int(salary))" : "Not set")
        - Estimated monthly spend: ₹\(Int(monthlyAverage))
        
        CATEGORY BREAKDOWN:
        \(spendingData.isEmpty ? "No expenses recorded yet - suggest starter budgets based on salary." : spendingData)
        
        INSTRUCTIONS:
        1. Be REALISTIC, not aggressive. Suggest limits the user can actually stick to.
        2. If a category average is reasonable for their income level, set the budget AT or slightly below the average — not 15% below.
        3. Only suggest meaningful cuts on categories that are clearly inflated (e.g., Dining > 20% of income).
        4. If salary is set: Aim for total budgets around 75-85% of salary (leaving 15-25% for savings). Adjust based on their actual behavior — don't force an unrealistic savings rate.
        5. Suggest budgets for the top 3-5 spending categories.
        6. If the user is already spending conservatively, ACKNOWLEDGE it and set budgets that protect their good habits rather than demanding more cuts.
        7. Keep suggestions practical — don't tell someone spending ₹2,000/month on Food to cut to ₹1,200. That's unrealistic.
        
        OUTPUT: Return ONLY a raw JSON array (no markdown):
        [
            {
                "category": "String",
                "suggestedLimit": Double,
                "currentAverage": Double,
                "reason": "Short reason — be encouraging, not punishing"
            }
        ]
        """
        
        do {
            let rawText = try await generateContent(systemPrompt: prompt)
            let cleaned = rawText
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                
            print("DEBUG: Gemini Budget Response -> \(cleaned)")
            return cleaned
        } catch {
            print("Budget generation failed: \(error)")
            return "[]"
        }
    }
    
    // Insight Generation (Legacy)
    func generateInsight(context: [Transaction], promptTemplate: String) async throws -> String {
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
        
        do {
            return try await generateContent(systemPrompt: fullPrompt)
        } catch {
            return "Could not generate insight."
        }
    }
    // MARK: - TF-IDF Helpers
    private func extractKeywords(from text: String) -> [String] {
        let stopWords: Set<String> = ["a", "an", "the", "and", "but", "or", "for", "nor", "on", "at", "to", "from", "by", "what", "is", "how", "much", "did", "i", "spend", "show", "me", "my", "transactions"]
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !stopWords.contains($0) && $0.count > 2 }
        return Array(Set(words)) // Unique keywords
    }
    
    // MARK: - Smart Insight (Rich Context)
    func generateSmartInsight(context: InsightEngine.FinancialContext) async throws -> String {
        // Pick a random angle to ensure variety
        let angles = [
            "daily_spending", "category_breakdown", "monthly_trend", 
            "projection", "savings_rate", "weekend_habits", 
            "frequent_merchant", "transaction_patterns", "biggest_day"
        ]
        let angle = angles.randomElement() ?? "random_observation"
        
        // Generate a random seed to force different outputs each time
        let randomSeed = Int.random(in: 1...1000)
        
        // Get monthly salary from Settings
        let monthlySalary = UserDefaults.standard.double(forKey: "monthlySalary")
        
        let prompt = """
        You're the user's witty money friend. Give ONE fresh, unique insight.
        
        THEIR FULL DATA (pick something interesting!):
        • Monthly recurring income: \(monthlySalary > 0 ? "₹\(Int(monthlySalary))" : "Not set")
        • Top category: \(context.topCategory.name) (₹\(Int(context.topCategory.amount)), \(context.topCategory.percent)%)
        • Second category: \(context.secondCategory.map { "\($0.name) (₹\(Int($0.amount)), \($0.percent)%)" } ?? "none")
        • Daily avg spend: ₹\(Int(context.avgDailySpend))
        • Biggest single expense: \(context.highestExpense.map { "\($0.merchant) - ₹\(Int($0.amount))" } ?? "none")
        • vs Last month: \(context.spendingTrend > 0 ? "+\(context.spendingTrend)%" : "\(context.spendingTrend)%")
        • Month projection: ₹\(Int(context.projectedMonthEnd))
        • Days remaining: \(context.daysLeftInMonth)
        • Weekend spend: ₹\(Int(context.weekendSpend)) | Weekday: ₹\(Int(context.weekdaySpend))
        • Most visited place: \(context.mostFrequentMerchant.map { "\($0.name) (\($0.count)x)" } ?? "varied")
        • Transactions this month: \(context.transactionCount) (avg ₹\(Int(context.avgTransactionSize)) each)
        • Savings rate: \(context.savingsRate)%
        • Biggest spending day: \(context.biggestSpendingDay.map { "\($0.day) - ₹\(Int($0.amount))" } ?? "N/A")
        
        TODAY'S ANGLE: \(angle.uppercased()) (seed: \(randomSeed))
        
        ANGLE GUIDE:
        - daily_spending: Comment on ₹/day pattern
        - category_breakdown: Top or 2nd category insights
        - monthly_trend: Compare to last month
        - projection: Month-end prediction
        - savings_rate: Comment on income vs spending
        - weekend_habits: Weekend vs weekday spending
        - frequent_merchant: Most visited place
        - transaction_patterns: Number/size of transactions
        - biggest_day: Which day they splurge most
        
        RULES:
        1. ONLY focus on the assigned angle
        2. Use REAL numbers from above
        3. NO clichés (avocado toast, coffee, etc)
        4. Max 100 chars. No emojis. No quotes.
        
        Your insight:
        """
        
        
        
        do {
            let text = try await generateContent(systemPrompt: prompt)
            
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
        } catch {
            // Fallback is handled inside wrapper, but if that also fails:
            if error.localizedDescription.contains("400") || error.localizedDescription.contains("403") {
                 return "Insight unavailable. Check API Model/Key."
            }
            throw error
        }
    }

    // MARK: - General Financial Tip (Variety)
    func generateGeneralTip() async throws -> String {
        // Random seed to force variety
        let seed = Int.random(in: 1...1000)
        let topics = ["investing", "saving", "spending psychology", "financial freedom", "side hustles", "debt", "lifestyle inflation", "emergency funds", "automation"]
        let topic = topics.randomElement() ?? "money"
        
        let prompt = """
        You're a witty financial friend. Give ONE unique money insight.
        
        TOPIC FOCUS: \(topic.uppercased()) (seed: \(seed))
        
        STYLE - Pick one randomly:
        - A surprising money fact most people don't know
        - A gentle roast of common financial mistakes
        - A motivational nudge without being preachy
        - A relatable observation about money habits
        - A clever reframe of boring financial advice
        
        AVOID THESE CLICHÉS:
        - "Avocado toast" or "latte factor"
        - "Pay yourself first" (too overused)
        - Generic "save more, spend less"
        - Anything that sounds like a boomer lecture
        
        GOOD EXAMPLES:
        - "Your future self is silently judging your Amazon cart"
        - "Every ₹100 invested today is ₹1000 of flex in 10 years"
        - "Rich people budget. Broke people wing it. Pick your side"
        - "Your bank knows your spending habits better than your therapist"
        - "Automated savings: the only good thing about forgetting"
        
        FORMAT: Max 100 chars. No emojis. No quotes. No markdown.
        
        Unique tip:
        """
        
        do {
            let text = try await generateContent(systemPrompt: prompt)
            
            let cleaned = text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "*", with: "")
                
            if cleaned.count > 120 {
                return String(cleaned.prefix(117)) + "..."
            }
            return cleaned
        } catch {
             if error.localizedDescription.contains("400") || error.localizedDescription.contains("403") {
                 return "Tip: Check API Key/Model settings."
            }
            throw error
        }
    }
    
    // MARK: - Monthly Wrapped (AI-generated fun summary)
    struct MonthlyStats {
        let monthName: String
        let totalSpent: Double
        let totalEarned: Double
        let savingsRate: Double
        let topCategories: [(name: String, amount: Double)]
        let topMerchants: [(name: String, amount: Double, count: Int)]
        let biggestExpense: (merchant: String, amount: Double)?
        let transactionCount: Int
        let vsLastMonth: Int // percentage change
    }
    
    func generateMonthlyWrapped(stats: MonthlyStats) async throws -> String {
        let topCats = stats.topCategories.prefix(3).map { "\($0.name): ₹\(Int($0.amount))" }.joined(separator: ", ")
        let topMerchants = stats.topMerchants.prefix(3).map { "\($0.name) (₹\(Int($0.amount)), \($0.count) visits)" }.joined(separator: ", ")
        
        let prompt = """
        You are a fun, witty financial storyteller. Write a "\(stats.monthName) Wrapped" summary for someone's spending.
        
        THEIR MONTH IN NUMBERS:
        - Spent: ₹\(Int(stats.totalSpent))
        - Earned: ₹\(Int(stats.totalEarned))
        - Saved: \(Int(stats.savingsRate))% of income
        - Transactions: \(stats.transactionCount)
        - vs Last Month: \(stats.vsLastMonth > 0 ? "+\(stats.vsLastMonth)%" : "\(stats.vsLastMonth)%")
        - Top Categories: \(topCats)
        - Favorite Merchants: \(topMerchants)
        - Biggest Single Expense: \(stats.biggestExpense.map { "₹\(Int($0.amount)) at \($0.merchant)" } ?? "None")
        
        RULES:
        1. Write 3-4 SHORT sentences (max 200 chars total)
        2. Be playful and personal - like Spotify Wrapped
        3. Include ONE specific merchant or category callout
        4. End with a fun observation or gentle nudge
        5. DON'T be boring or preachy. NO markdown. NO emojis.
        
        Examples:
        - "Swiggy saw you 23 times. That's basically a standing reservation. You saved 18% though - the kitchen stays clean AND the bank stays happy."
        - "Shopping took 40% of your budget. Your wardrobe won, your wallet tap-danced. At least rent was on time."
        
        Now write their \(stats.monthName) Wrapped:
        """
        
        do {
            let text = try await generateContent(systemPrompt: prompt)
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "*", with: "")
        } catch {
            return ""
        }
    }
}

