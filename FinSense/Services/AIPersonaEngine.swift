import Foundation
import SwiftUI

class AIPersonaEngine {
    static let shared = AIPersonaEngine()
    private init() {}
    
    // Generates a deep psychological profile of the user to be injected into future prompts
    func generatePersona(transactions: [Transaction]) async {
        let existingPersona = UserDefaults.standard.string(forKey: "userAIPersona") ?? ""
        
        let prompt: String
        
         let onboardingProfile = UserDefaults.standard.string(forKey: "onboardingProfile") ?? ""
        let hasOnboarding = !onboardingProfile.isEmpty
        
        // If not enough transaction data but user has completed onboarding,
        // generate a REAL persona from their onboarding self-assessment.
        // Only fall back to the blank default if we have NO data at all.
        if transactions.count < 15 {
            guard hasOnboarding else {
                // Truly zero data — use a minimal placeholder
                let defaultPersona = """
                [STATUS: New User — Insufficient Data]
                This user just started. No spending patterns or self-assessment available.
                → Ask open-ended questions about their financial projects.
                → Be warm, encouraging, and non-judgmental.
                → Do not make assumptions about their habits.
                """
                UserDefaults.standard.set(defaultPersona, forKey: "userAIPersona")
                print("📝 Set blank-slate persona (no data yet)")
                return
            }
            
            // We have onboarding answers but few/no transactions.
            let recentChatSignals = UserDefaults.standard.string(forKey: "recentChatSignals") ?? "No chat signals yet."
            let onboardingPrompt = """
            You are writing a behavioral dossier about a new app user based on their self-assessment survey.
            This dossier will be silently injected into the system prompts of OTHER AI agents (chat advisor, budget planner, tip generator) so they can personalize their responses. The user does NOT see this dossier.
            
            USER'S SELF-ASSESSMENT (Onboarding):
            \(onboardingProfile)
            
            RECENT CHAT SIGNALS:
            \(recentChatSignals)
            
            Write the dossier using exactly these 8 sections. Each section should be 1-2 sentences (20-30 words). Be specific to THIS user, never generic.
            
            • Spending Psychology: How do they relate to money emotionally? Are they anxious, carefree, guilty, disciplined?
            • Savings Behavior: Do they save consistently, sporadically, or never? What's their likely approach?
            • Impulse Triggers: What situations or emotions drive them to overspend? (Based on their self-reported impulse level)
            • Lifestyle Creep Risk: When they get extra money, do they spend or save? How susceptible are they?
            • Communication Guide: EXACTLY how to talk to this user. Be specific — are they fragile (be gentle), thick-skinned (roast them), data-driven (show numbers), or emotion-driven (use stories)?
            • Active Projects & Concerns: Any specific financial projects, worries, or life events they've mentioned or implied.
            • Behavioral Shift: Write "Day-1 baseline — self-reported only, no behavioral data yet."
            • Agent Instructions: One sentence telling other AI agents the MOST important thing to remember when talking to this user.
            
            IMPORTANT: Write in third person ("This user...", "They tend to..."). No intros, no pleasantries. Just the 8 sections.
            """
            
            do {
                let persona = try await AIManager.shared.generateContent(systemPrompt: onboardingPrompt)
                let cleaned = persona.trimmingCharacters(in: .whitespacesAndNewlines)
                UserDefaults.standard.set(cleaned, forKey: "userAIPersona")
                print("✅ Generated Day-1 onboarding-based persona")
            } catch {
                print("❌ Failed to generate onboarding persona: \(error)")
            }
            return
        }

        
        let expenses = transactions.filter { $0.type == .expense }
        let grouped = Dictionary(grouping: expenses) { $0.category }
            .map { "\($0.key): ₹\($0.value.reduce(0) { $0 + $1.amount })" }
            .joined(separator: ", ")
            
        let recentChatSignals = UserDefaults.standard.string(forKey: "recentChatSignals") ?? "No recent behavioral signals from chat."
        let contextAddition = existingPersona.isEmpty || existingPersona.contains("New user") || existingPersona.contains("New User") ? "" : "\nMost Recent Persona (compare for shifts):\n\(existingPersona)\n"
        
        // Load rolling history to observe multi-week behavioral arcs
        let personaHistory = UserDefaults.standard.stringArray(forKey: "personaHistory") ?? []
        let historySummary = personaHistory.isEmpty ? "" : """
        
        HISTORICAL PERSONA SNAPSHOTS (oldest → newest, observe behavioral arc):
        \(personaHistory.joined(separator: "\n---\n"))
        """
            
        prompt = """
        You are writing a behavioral dossier about a user of a financial tracking app.
        This dossier will be SILENTLY injected into the system prompts of OTHER AI agents (chat advisor, budget planner, tip generator) so they can deeply personalize their responses. The user NEVER sees this dossier — it is hidden context.
        
        SPENDING DATA:
        [ \(grouped) ]
        
        USER'S SELF-ASSESSMENT (Onboarding):
        \(onboardingProfile.isEmpty ? "Not completed." : onboardingProfile)
        
        RECENT CHAT SIGNALS (emotions/projects the user revealed in conversation):
        \(recentChatSignals)
        \(contextAddition)\(historySummary)
        
        Write the dossier using exactly these 8 sections. Each section = 1-2 sentences (20-30 words). Be brutally specific to THIS user's data. Never write generic advice.
        
        • Spending Psychology: How do they relate to money? Anxious saver? Guilt-free spender? Calculated optimizer? What does their spending DATA reveal about their mindset?
        • Savings Behavior: Based on their actual spending patterns, are they a consistent saver, an erratic one, or do they spend everything? Quantify if possible (₹ INR).
        • Impulse Triggers: Which merchants or categories show impulsive patterns? (e.g., "Late-night Swiggy orders 3x/week suggest emotional eating spending.")
        • Lifestyle Creep Risk: Are their discretionary categories growing month-over-month? Are they susceptible to lifestyle inflation?
        • Communication Guide: EXACTLY how to talk to this user. Based on their chosen motivation style and observed behavior. E.g., "Responds to dark humor and blunt callouts. Avoid corporate jargon — they'll disengage."
        • Active Projects & Concerns: Any specific projects, fears, or life events from their chat signals or onboarding. E.g., "Wants to save for a trip to Europe. Stressed about upcoming rent increase."
        • Behavioral Shift: Compare to the historical snapshots above. Is there a multi-week trend? E.g., "Discipline improving — Food spending down 15% over 3 weeks." If no history, write "Initial profile established."
        • Agent Instructions: One critical sentence for other AI agents. E.g., "This user responds well to specific numbers and comparisons, not vague encouragement. Push them on Food category — that's where they bleed money."
        
        RULES:
        - Third person only ("This user...", "They tend to...")
        - Use ₹ (INR) for all amounts
        - Reference SPECIFIC merchants and categories from the data, not abstract traits
        - NO intros, NO summaries, NO pleasantries. Just the 8 bullet sections.
        """
        
        do {
            let persona = try await AIManager.shared.generateContent(systemPrompt: prompt)
            let cleaned = persona.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Save to AppStorage via UserDefaults
            UserDefaults.standard.set(cleaned, forKey: "userAIPersona")
            print("Successfully updated User AI Persona")
        } catch {
            print("Failed to generate AI Persona: \(error)")
        }
    }
    
    // Summarizes the recent chat history to extract behavioral signals
    func summarizeRecentChats() {
        let chatBuffer = UserDefaults.standard.stringArray(forKey: "chatHistoryBuffer") ?? []
        guard chatBuffer.count >= 50 else { return } // Wait for at least 25 user + 25 AI interactions before summarizing
        
        let combinedChat = chatBuffer.joined(separator: "\n")
        
        let prompt = """
        You are extracting behavioral signals from a chat between a user and a financial AI advisor.
        
        IMPORTANT: We ALREADY have the user's spending metrics from their transaction data.
        Your ONLY job is to capture what transactions CANNOT reveal:
        
        Focus EXCLUSIVELY on:
        1. Emotional state — Are they stressed, guilty, hopeful, anxious, proud, defeated?
        2. Stated projects & ambitions — e.g. "I want to buy a house in 2 years", "I'm trying to save for a trip"
        3. Financial fears & self-beliefs — e.g. "I'll never get out of debt", "I suck at saving"
        4. Specific struggles or habits they admitted — e.g. "I always buy when bored", "I give in when friends pressure me"
        5. Important external context — e.g. upcoming big expenses, job uncertainty, life events they mentioned
        6. Key questions or insights that stuck — e.g. "They asked how to build an emergency fund" or "They showed interest in SIPs"
        
        DO NOT mention rupee amounts, category names, or spending totals. That's captured elsewhere.
        
        CHAT LOG:
        \(combinedChat)
        
        Return a crisp, 2-3 sentence behavioral summary in third-person. Max 60 words.
        If there are no meaningful signals, return "No significant behavioral signals detected in recent chats."
        """
        
        Task(priority: .background) {
            do {
                let summary = try await AIManager.shared.generateContent(systemPrompt: prompt)
                let cleaned = summary.trimmingCharacters(in: .whitespacesAndNewlines)
                
                await MainActor.run {
                    // 1. Save the new chat signals
                    UserDefaults.standard.set(cleaned, forKey: "recentChatSignals")
                    UserDefaults.standard.set(Date(), forKey: "lastChatSummaryDate")
                    
                    // 2. Clear the buffer
                    UserDefaults.standard.removeObject(forKey: "chatHistoryBuffer")
                    UserDefaults.standard.set(0, forKey: "chatInteractionCount")
                    
                    print("✅ Chat signals updated: \(cleaned)")
                }
                
                // 3. IMMEDIATELY push a persona refresh so the Persona Engine
                //    absorbs these new signals right away, not next week.
                //    We fetch transactions via notification since we don't have context here.
                NotificationCenter.default.post(name: .chatSignalsUpdated, object: nil)
                
            } catch {
                print("❌ Failed to summarize chat: \(error)")
            }
        }
    }
    
    // Pushes the current persona into a rolling history stack (keeps last 3 snapshots)
    // so the Persona Writer can observe multi-week behavioral changes, not just the last delta.
    func archiveCurrentPersona() {
        guard let current = UserDefaults.standard.string(forKey: "userAIPersona"),
              !current.contains("New user") else { return }
        
        var history = UserDefaults.standard.stringArray(forKey: "personaHistory") ?? []
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
        history.append("[\(timestamp)] \(current)")
        
        // Keep only the last 3 snapshots
        if history.count > 3 { history = Array(history.suffix(3)) }
        UserDefaults.standard.set(history, forKey: "personaHistory")
        print("📚 Archived persona snapshot (\(history.count)/3 in history)")
    }
    
    // 30-day fallback: summarize chat even if buffer hasn't reached 50 messages
    func summarizeIfStale() {
        let lastSummary = UserDefaults.standard.object(forKey: "lastChatSummaryDate") as? Date ?? .distantPast
        let daysSinceLastSummary = Calendar.current.dateComponents([.day], from: lastSummary, to: Date()).day ?? 0
        let buffer = UserDefaults.standard.stringArray(forKey: "chatHistoryBuffer") ?? []
        
        // If it's been 30 days and we have *any* messages, summarize what we have
        if daysSinceLastSummary >= 30 && buffer.count >= 3 {
            print("⏰ 30-day fallback: triggering chat summarization with \(buffer.count) messages.")
            summarizeRecentChats()
        }
    }
    
}

extension Notification.Name {
    static let chatSignalsUpdated = Notification.Name("chatSignalsUpdated")
}