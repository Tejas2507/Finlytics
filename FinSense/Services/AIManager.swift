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
    

    
    // MARK: - App Manual (Hidden Context for AI)
    private var appManual: String {
        """
        # Finlytics App Official Manual (User Guide)
        
        ## 1. DASHBOARD (Tab 1)
        - **Balance Card**: Displays your current "Net Savings". Tap it to set your 'Starting Balance'. All transactions are calculated relative to this point.
        - **Spending Trends**: Charts showing your expense history.
        - **Projects Summary**: Quick access to your top active projects.
        - **This Month Sheet**: Accessible via the "This Month" button or by tapping the weekly bars. Contains deeper analytics and historical month navigation.
        
        ## 2. TRANSACTIONS (Tab 2)
        - **Add Transaction (+)**:
            - *Manual*: Fill in Title, Amount, Category, Date, and **Time**.
            - *Smart Paste*: Type like you talk. Example: "Spent 50 on coffee" or "Income 10000 salary".
        - **Editing**: Tap any transaction to change details. You can now edit the **exact time** of a transaction.
        - **Bulk Actions**: Use 'Select' mode to change categories or 'Hide' multiple items at once.
        - **Search**: Pull down on the list to filter by merchant or category.
        
        ## 3. PROJECTS (The 'Project' Section)
        - **Purpose**: Group transactions for specific events (e.g., 'Goa Trip', 'Wedding').
        - **Creation**: Accessible from Dashboard or Transactions. Set an Emoji and a Target Budget.
        - **Vault (Secure Storage)**: 
            - Swipe LEFT on any project card in the 'See All' list to find the 'Hide' option.
            - Hidden projects move to the **Vault** (located in Settings).
        - **Archiving**: Long-press or use Edit to Archive completed projects.
        
        ## 4. SMART BUDGETS (Tab 4)
        - **Setup**: Create a budget for any category (Food, Travel, etc.).
        - **Monitoring**: The app shows a progress bar indicating how much of your monthly limit is used.
        - **AI Suggestion**: Tap the 'Suggest' button to let AI propose realistic limits based on your past spending.
        
        ## 5. AI CHATS (Bifurcated Context)
        - **Financial Strategist (Main Tab)**: Analyzes numbers, spending patterns, and gives advice. Does NOT know app steps.
        - **App Help Guide (Settings)**: Knows THIS manual and guides you on how to use features. Does NOT see your money data.
        
        ## 6. SETTINGS (Tab 5)
        - **Monthly Income**: Set your salary here for better budgeting.
        - **Vault**: View your hidden (private) projects and transactions here. Access with device bio/passcode.
        - **AI Config**: Switch between Gemini/OpenAI models and manage API keys.
        - **Tutorial**: Tap 'Replay Tutorial' to see the onboarding again.
        """
    }
    
    // MARK: - Valid App Categories (for Smart Paste validation)
    private let validExpenseCategories = [
        "Food & Dining", "Shopping", "Transportation", "Entertainment",
        "Bills & Utilities", "Healthcare", "Education", "Personal Care",
        "Travel", "Investment", "Gift", "Other"
    ]
    private let validIncomeCategories = [
        "Salary", "Freelance", "Business", "Investment", "Gift", "Other"
    ]
    
    // Unified Generation logic with AI Provider routing and optional Persona Injection
    func generateContent(systemPrompt: String, injectPersona: Bool = true) async throws -> String {
        let aiProvider = UserDefaults.standard.string(forKey: "aiProvider") ?? "gemini"
        
        var finalPrompt = systemPrompt
        
        if injectPersona {
            let persona = UserDefaults.standard.string(forKey: "userAIPersona") ?? ""
            if !persona.isEmpty {
                finalPrompt += """
                
                
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
            }
        }
        
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

    // Helper to try selected model, then fallback to gemini-flash-latest if it fails
    private func generateContentWithFallback(apiKey: String, systemPrompt: String) async throws -> String {
        // Migration: Reset any old/invalid model values to default
        let validModels = ["gemini-flash-lite-latest", "gemini-flash-latest"]
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
            
            // If PRIMARY model fails, fallback to gemini-flash-latest
            print("DEBUG: Falling back to gemini-flash-latest")
            let fallbackModel = GenerativeModel(name: "gemini-flash-latest", apiKey: apiKey)
            do {
                let fallbackResponse = try await fallbackModel.generateContent(systemPrompt)
                return fallbackResponse.text ?? ""
            } catch {
                 throw NSError(domain: "GeminiService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Primary (\(selectedModel)) & Fallback (Flash) failed. Error: \(error.localizedDescription)"])
            }
        }
    }
    
    // MARK: - Chat with Financial Agent
    // Uses structured analytics + fuzzy keyword matching + conversation memory
    func generateResponse(for prompt: String, context: [Transaction], budgets: [Budget], monthlySalary: Double, projects: [Project] = [], conversationHistory: [String] = [], isHelpMode: Bool = false) async throws -> String {
        
        if isHelpMode {
            // ── HELP MODE: Strictly App Support ──
            // NO financial context (transactions, budgets, salary) is included here.
            // Routes through the unified pipeline (fallback + provider routing)
            let helpPrompt = """
            You are Finlytics App Guide — a precise, helpful expert on the Finlytics iOS app.
            
            ## MISSION:
            Assist the user with step-by-step instructions on HOW TO USE the app's features.
            
            ## CONTEXT (The App Manual):
            \(appManual)
            
            ## RULES (STRICT):
            1. Be VERY precise and concise.
            2. ONLY answer questions about app functionality.
            3. If the user asks about their financial data (spending, budgets, etc.), politely inform them: "I don't have access to your personal financial data in Help Mode. Please ask your Financial Strategist in the main Chat for spending insights."
            4. Use bullet points for steps.
            5. If a feature isn't in the manual, say you're not sure but can guide them through the basics.
            
            ## USER QUESTION:
            \(prompt)
            """
            
            do {
                // Use unified pipeline but WITHOUT persona injection (Help AI doesn't need personality)
                return try await generateContent(systemPrompt: helpPrompt, injectPersona: false)
            } catch {
                return "Error connecting to AI service. Please check your API key and try again."
            }
        }
        
        // ── ANALYSIS MODE: Full Financial AI ──
        // Filter out hidden transactions for privacy
        let visibleTransactions = context.filter { !$0.isHidden }
        
        let richContext = MerchantAnalytics.shared.buildRichContext(
            transactions: visibleTransactions,
            userQuery: prompt,
            projects: projects
        )
        
        let fuzzyTxStr = getRelevantContext(from: visibleTransactions, for: prompt)
        
        // ── Budget Context (Current Month) ──
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let currentMonthTx = visibleTransactions.filter { $0.date >= startOfMonth }
        
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM yyyy"
        let currentMonthName = monthFormatter.string(from: now)
        
        let budgetContext = budgets.map { budget in
            let spent = currentMonthTx.filter { $0.category == budget.category && $0.type == .expense }.reduce(0) { $0 + $1.amount }
            let pct = budget.monthlyLimit > 0 ? Int((spent / budget.monthlyLimit) * 100) : 0
            return "\(budget.category): ₹\(Int(spent))/₹\(Int(budget.monthlyLimit)) (\(pct)%)"
        }.joined(separator: "; ")
        
        let salaryContext = monthlySalary > 0 ? "Monthly Salary: ₹\(Int(monthlySalary))" : "Monthly Salary: Not set"
        
        // ── Conversation Memory (last messages for continuity) ──
        let conversationContext: String
        if !conversationHistory.isEmpty {
            conversationContext = """
            ## Recent Conversation (for context continuity)
            \(conversationHistory.joined(separator: "\n"))
            """
        } else {
            conversationContext = ""
        }
        
        let systemPrompt = """
        You are Finlytics — a sharp, friendly financial advisor for Indian users. All amounts in ₹ (INR).
        
        ## Pre-Computed Analytics (USE THESE NUMBERS — they are accurate and pre-calculated)
        \(richContext)
        
        ## Budget Status (Current Month — \(currentMonthName))
        \(budgetContext.isEmpty ? "No active budgets set." : budgetContext)
        \(salaryContext)
        
        ## Relevant Transactions (Keyword-matched from history)
        \(fuzzyTxStr.isEmpty ? "No specific matches found." : fuzzyTxStr)
        
        \(conversationContext)
        
        ## User Question
        \(prompt)
        
        ## RESPONSE RULES:
        1. **BE CONCISE** — Answer in 3-5 bullet points. Max 120 words total. No fluff.
        2. **POINTWISE FORMAT** — Use bullet points (•), not paragraphs. Each bullet = one clear insight.
        3. **TABLES** — Only use a simple 2-column vertical table (Label | Value) when the user asks for a comparison or breakdown.
        4. **TONE** — Be a smart, witty financial friend. Not a corporate robot.
        5. **₹ ALWAYS** — All amounts in ₹ with no decimal places.
        6. **ADMIT GAPS** — If the data doesn't cover what the user asked, say so honestly.
        7. **STRICT ISOLATION** — Do NOT provide app instructions here. If the user asks "how to do X", refer them to the Help AI in Settings.
        8. **TIME AWARENESS** — Pay attention to the date provided. "This month" means the CURRENT month section. "Last month" means the LAST MONTH section. Do NOT mix up all-time totals with monthly data.
        """
        
        do {
            let text = try await generateContent(systemPrompt: systemPrompt)
            if text.isEmpty { return "I couldn't generate a response." }
            return text
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Smart Paste: Parse text into transaction details
    func parseTransaction(from text: String) async throws -> ParsedTransaction {
        let allCategories = (validExpenseCategories + validIncomeCategories).joined(separator: ", ")
        
        let prompt = """
        Extract the following transaction details from this text: "\(text)"
        
        Return JSON with these keys:
        - "amount": Double (numeric only)
        - "merchant": String (name of place/person)
        - "category": String (MUST be one of: \(allCategories))
        - "type": String ("Income" or "Expense")
        
        CATEGORY RULES:
        - You MUST pick from the list above. Do not invent new categories.
        - If unsure, use "Other".
        - For food/restaurants/cafes, use "Food & Dining".
        - For cab/auto/fuel, use "Transportation".
        
        If a field is missing, use null.
        Return ONLY the raw JSON object, no markdown.
        Example: {"amount": 500.0, "merchant": "Uber", "category": "Transportation", "type": "Expense"}
        """
        
        do {
            // No persona injection for structured JSON output
            let jsonString = try await generateContent(systemPrompt: prompt, injectPersona: false)
            
            // Clean markdown code blocks if present
            let cleanedJson = jsonString
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard let data = cleanedJson.data(using: .utf8) else { throw NSError(domain: "GeminiService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid data"]) }
            
            var parsed = try JSONDecoder().decode(ParsedTransaction.self, from: data)
            
            // Validate category — if AI returned something not in our list, map to "Other"
            if let cat = parsed.category {
                let isExpense = parsed.type?.lowercased() == "expense"
                let validList = isExpense ? validExpenseCategories : validIncomeCategories
                if !validList.contains(cat) {
                    // Try fuzzy match
                    let fuzzyMatch = validList.first { $0.lowercased().contains(cat.lowercased()) || cat.lowercased().contains($0.lowercased()) }
                    parsed = ParsedTransaction(amount: parsed.amount, merchant: parsed.merchant, category: fuzzyMatch ?? "Other", type: parsed.type)
                }
            }
            
            return parsed
        } catch {
            print("Smart Paste failed: \(error)")
            throw error
        }
    }
    
    // MARK: - Smart Budgeting: Analyze history and suggest monthly budgets
    // Uses historical averages per actual calendar month
    func generateBudgetSuggestions(history: [Transaction]) async throws -> String {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        
        // Get all expenses (exclude hidden + investments)
        let allExpenses = history.filter { !$0.isHidden && $0.type == .expense && !$0.category.lowercased().contains("invest") }
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
        
        OUTPUT: Return ONLY a raw JSON array (no markdown, no explanation):
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
            // No persona injection for JSON output
            let rawText = try await generateContent(systemPrompt: prompt, injectPersona: false)
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
        // Prepare context — filter hidden
        let visible = context.filter { !$0.isHidden }
        let recentTx = visible.prefix(50).map {
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
    
    // MARK: - TF-IDF Keyword Helpers
    private func extractKeywords(from text: String) -> [String] {
        let stopWords: Set<String> = [
            "a", "an", "the", "and", "but", "or", "for", "nor", "on", "at", "to", "from", "by",
            "what", "is", "how", "much", "did", "i", "show", "me", "my", "can", "you", "tell",
            "give", "get", "about", "please", "do", "have", "has", "was", "were", "been",
            "total", "all", "any", "some", "this", "that", "these", "those"
        ]
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !stopWords.contains($0) && $0.count > 1 }
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
        \(context.projectStats)
        
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
    
    // MARK: - AI Helpers
    
    private func getRelevantContext(from transactions: [Transaction], for prompt: String) -> String {
        let kw = extractKeywords(from: prompt)
        if kw.isEmpty { return "No specific keyword matches found." }
        
        let filtered = transactions.filter { tx in
            let text = "\(tx.merchant) \(tx.category) \(tx.notes) \(tx.type)".lowercased()
            return kw.contains { text.contains($0) }
        }
        
        if filtered.isEmpty { return "No transactions directly matched search keywords." }
        
        // Return top 25 most relevant (increased from 15)
        return filtered.prefix(25).map { tx in
            "\(tx.date.formatted(date: .numeric, time: .omitted))|\(tx.merchant)|₹\(Int(tx.amount))|\(tx.category)|\(tx.type == .income ? "IN" : "EX")"
        }.joined(separator: "\n")
    }
}
