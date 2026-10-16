import Foundation
import SwiftData

/// Human-readable stages reported while an assistant reply is being produced.
/// The chat UI uses these to explain what is happening during slower steps.
enum ChatGenerationPhase: String {
    case understanding
    case calculating
    case writing

    var label: String {
        switch self {
        case .understanding:
            return "Understanding your question…"
        case .calculating:
            return "Checking your transactions…"
        case .writing:
            return "Writing…"
        }
    }
}

@MainActor
final class ChatOrchestrator {
    static let shared = ChatOrchestrator()

    private init() {}

    func generateReply(
        thread: ChatThread,
        userMessage: ChatMessage,
        assistantMessage: ChatMessage,
        transactions: [Transaction],
        budgets: [Budget],
        projects: [Project],
        merchantProfiles: [MerchantProfile],
        modelContext: ModelContext,
        onPhase: ((ChatGenerationPhase) -> Void)? = nil
    ) async {
        let provider = activeProvider()
        userMessage.status = .completed
        assistantMessage.provider = provider.name
        assistantMessage.model = provider.model
        assistantMessage.status = .pending
        assistantMessage.errorCode = nil
        assistantMessage.errorMessage = nil
        assistantMessage.content = ""
        thread.touch()

        if thread.title == "New chat" {
            thread.title = localTitle(from: userMessage.content)
        }
        try? modelContext.save()

        do {
            switch thread.mode {
            case .financial:
                try await generateFinancialReply(
                    thread: thread,
                    userMessage: userMessage,
                    assistantMessage: assistantMessage,
                    transactions: transactions,
                    budgets: budgets,
                    projects: projects,
                    merchantProfiles: merchantProfiles,
                    provider: provider,
                    modelContext: modelContext,
                    onPhase: onPhase
                )
            case .help:
                onPhase?(.writing)
                try await generateHelpReply(
                    thread: thread,
                    assistantMessage: assistantMessage,
                    provider: provider
                )
            }

            thread.touch()
            try? modelContext.save()
            scheduleSummary(thread: thread, provider: provider, modelContext: modelContext)
        } catch is CancellationError {
            markCancelled(assistantMessage)
            try? modelContext.save()
        } catch let error as AIProviderError {
            if case .cancelled = error {
                markCancelled(assistantMessage)
            } else {
                markFailed(assistantMessage, error: error)
            }
            try? modelContext.save()
        } catch let error as FinancePlannerError {
            markDomainFailure(
                assistantMessage,
                code: "invalid_plan",
                message: error.localizedDescription
            )
            try? modelContext.save()
        } catch let error as FinanceQueryError {
            markDomainFailure(
                assistantMessage,
                code: "query_failed",
                message: error.localizedDescription
            )
            try? modelContext.save()
        } catch {
            assistantMessage.status = .failed
            assistantMessage.errorCode = String(describing: type(of: error))
            assistantMessage.errorMessage = error.localizedDescription
            if assistantMessage.content.isEmpty {
                assistantMessage.content = error.localizedDescription
            }
            try? modelContext.save()
        }
    }

    private func generateFinancialReply(
        thread: ChatThread,
        userMessage: ChatMessage,
        assistantMessage: ChatMessage,
        transactions: [Transaction],
        budgets: [Budget],
        projects: [Project],
        merchantProfiles: [MerchantProfile],
        provider: ActiveAIProvider,
        modelContext: ModelContext,
        onPhase: ((ChatGenerationPhase) -> Void)?
    ) async throws {
        let visibleProfiles = privacySafeProfiles(
            transactions: transactions,
            profiles: merchantProfiles
        )
        let plan: FinanceQueryPlan
        if let storedPlan = assistantMessage.queryPlan {
            plan = storedPlan
        } else {
            onPhase?(.understanding)
            plan = try await FinanceQueryPlanner.shared.plan(
                question: userMessage.content,
                lastQuery: thread.lastQuery,
                conversationContext: plannerConversationContext(
                    thread: thread,
                    userMessage: userMessage
                ),
                merchantProfiles: visibleProfiles,
                apiKey: provider.apiKey,
                model: provider.model,
                providerClient: provider.client
            )
        }
        assistantMessage.queryPlan = plan

        if plan.action == .clarify {
            assistantMessage.content = plan.clarificationQuestion
                ?? "Which category or time period should I use?"
            assistantMessage.status = .completed
            return
        }

        if plan.action == .generalAdvice {
            try await generateConversationalReply(
                thread: thread,
                assistantMessage: assistantMessage,
                provider: provider,
                onPhase: onPhase
            )
            return
        }

        guard let query = plan.query else {
            throw FinancePlannerError.invalidPlan("No executable query was returned.")
        }

        let effectiveProfiles: [MerchantProfile]
        if query.filters.merchantTags.isEmpty {
            effectiveProfiles = visibleProfiles
        } else {
            effectiveProfiles = await MerchantClassificationService.shared
                .classifyUnknownMerchantsIfNeeded(
                    transactions: transactions,
                    existingProfiles: visibleProfiles,
                    requestedTags: query.filters.merchantTags,
                    apiKey: provider.apiKey,
                    model: provider.model,
                    providerClient: provider.client,
                    modelContext: modelContext
                )
        }

        let startingTimestamp = UserDefaults.standard.double(forKey: "startingBalanceDate")
        let queryContext = FinanceQueryContext(
            transactions: transactions,
            budgets: budgets,
            projects: projects,
            merchantProfiles: effectiveProfiles,
            monthlySalary: UserDefaults.standard.double(forKey: "monthlySalary"),
            startingBalance: UserDefaults.standard.double(forKey: "startingBalance"),
            startingBalanceDate: startingTimestamp > 0
                ? Date(timeIntervalSince1970: startingTimestamp)
                : nil,
            allowHiddenTransactions: false
        )
        onPhase?(.calculating)
        let result = try FinanceQueryEngine.shared.execute(query, context: queryContext)
        assistantMessage.evidence = result
        thread.lastQuery = query

        let verifiedAnswer = FinanceAnswerFormatter().format(result)

        if !provider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let chatContext = ChatContextAssembler().assemble(
                thread: thread,
                messages: thread.messages,
                mode: .financial,
                additionalInstruction: narrationInstruction(verifiedAnswer: verifiedAnswer)
            )
            let request = AIProviderRequest(
                systemInstruction: chatContext.systemInstruction,
                messages: chatContext.messages,
                temperature: 0.4,
                maxOutputTokens: 600
            )
            onPhase?(.writing)
            do {
                try await stream(request: request, into: assistantMessage, provider: provider)
                return
            } catch {
                // Fall back gracefully to verified template on provider error
            }
        }

        assistantMessage.content = verifiedAnswer
        assistantMessage.status = .completed
    }

    /// Conversational lane for messages the planner marks as general advice:
    /// greetings, meta questions, or open-ended asks without a computable query.
    /// The AI may chat freely but never receives or invents financial figures.
    private func generateConversationalReply(
        thread: ChatThread,
        assistantMessage: ChatMessage,
        provider: ActiveAIProvider,
        onPhase: ((ChatGenerationPhase) -> Void)?
    ) async throws {
        guard !provider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            assistantMessage.status = .completed
            assistantMessage.content = """
            Add your AI API key in Settings → AI Configuration to chat freely here.

            In the meantime, I can still answer questions like “How much did I spend this month?”, “Show my top merchants”, or “Compare Food & Dining with last month”.
            """
            return
        }

        let chatContext = ChatContextAssembler().assemble(
            thread: thread,
            messages: thread.messages,
            mode: .financial,
            additionalInstruction: """
            The user's latest message is conversational, not a computable finance question.
            Reply in 2-4 warm, natural sentences. Never invent or guess financial figures; you have no verified evidence for this message.
            If the user seems to expect numbers, briefly say what this screen can compute (spending, income, comparisons, category/merchant breakdowns, budgets, projects, and balance) and suggest one concrete question they could ask.
            Keep the response short: no headings, no tables. Use '-' bullets only if listing more than two items.
            """
        )
        let request = AIProviderRequest(
            systemInstruction: chatContext.systemInstruction,
            messages: chatContext.messages,
            temperature: 0.5,
            maxOutputTokens: 400
        )
        onPhase?(.writing)
        try await stream(request: request, into: assistantMessage, provider: provider)
    }

    private func narrationInstruction(verifiedAnswer: String) -> String {
        """
        The app calculated this authoritative financial evidence:
        \(verifiedAnswer)

        Instructions for your reply:
        1. State the verified numbers clearly to answer the user's question directly.
        2. Provide financial context or commentary on what these numbers mean (e.g. key drivers, percentage changes, or group breakdowns).
        3. Offer 1-2 warm, actionable financial recommendations or observations based on this evidence.
        4. Maintain 100% fidelity to the numbers above—do not alter amounts or invent transactions.
        5. Format for a chat bubble: short paragraphs, **bold** for key figures, and '-' bullets when listing more than two items. Do not use headings or tables.
        """
    }

    /// Compact transcript of the last few turns used only to resolve follow-ups
    /// and clarification answers during query planning.
    private func plannerConversationContext(
        thread: ChatThread,
        userMessage: ChatMessage
    ) -> String? {
        let previous = thread.messages
            .filter {
                $0.id != userMessage.id &&
                $0.role != .system &&
                $0.status != .superseded &&
                !$0.content.isEmpty
            }
            .sorted { $0.createdAt < $1.createdAt }
            .suffix(4)
        guard !previous.isEmpty else { return nil }

        var lines = previous.map { message -> String in
            let role = message.role == .user ? "User" : "Assistant"
            let compact = message.content
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
            let trimmed = compact.count > 240
                ? String(compact.prefix(240)) + "…"
                : compact
            return "\(role): \(trimmed)"
        }
        if let last = previous.last,
           last.role == .assistant,
           last.queryPlan?.action == .clarify {
            lines.append("(The Assistant's last message was a clarification question — the latest User message answers it.)")
        }
        return lines.joined(separator: "\n")
    }

    private func privacySafeProfiles(
        transactions: [Transaction],
        profiles: [MerchantProfile]
    ) -> [MerchantProfile] {
        var visibleKeys = Set(
            transactions
                .filter { !$0.isHidden }
                .compactMap(\.canonicalMerchantKey)
        )
        for transaction in transactions where !transaction.isHidden {
            if let resolved = MerchantResolver.shared.resolveKey(
                for: transaction.merchant,
                profiles: profiles
            ) {
                visibleKeys.insert(resolved)
            }
        }
        return profiles.filter { visibleKeys.contains($0.canonicalKey) }
    }

    private func generateHelpReply(
        thread: ChatThread,
        assistantMessage: ChatMessage,
        provider: ActiveAIProvider
    ) async throws {
        let chatContext = ChatContextAssembler().assemble(
            thread: thread,
            messages: thread.messages,
            mode: .help,
            additionalInstruction: """
            Official app manual:
            \(AppHelpKnowledge.manual)

            If a feature is not documented, say so instead of inventing steps.
            If asked about personal financial data, direct the user to a Financial AI thread.
            """
        )
        let request = AIProviderRequest(
            systemInstruction: chatContext.systemInstruction,
            messages: chatContext.messages,
            temperature: 0.2,
            maxOutputTokens: 600
        )
        try await stream(request: request, into: assistantMessage, provider: provider)
    }

    private func stream(
        request: AIProviderRequest,
        into assistantMessage: ChatMessage,
        provider: ActiveAIProvider
    ) async throws {
        assistantMessage.status = .streaming
        var receivedText = false

        for try await chunk in provider.client.stream(
            request: request,
            apiKey: provider.apiKey,
            model: provider.model
        ) {
            try Task.checkCancellation()
            receivedText = true
            assistantMessage.content += chunk
        }

        guard receivedText, !assistantMessage.content.isEmpty else {
            throw AIProviderError.emptyResponse
        }
        assistantMessage.status = .completed
    }

    private func activeProvider() -> ActiveAIProvider {
        let providerName = UserDefaults.standard.string(forKey: "aiProvider") ?? "gemini"
        if providerName == "openai" {
            return ActiveAIProvider(
                name: "openai",
                apiKey: KeychainHelper.shared.read(for: "openai_api_key") ?? "",
                model: UserDefaults.standard.string(forKey: "aiModel") ?? "gpt-4o-mini",
                client: OpenAIProviderAdapter.shared
            )
        }

        let selectedModel = UserDefaults.standard.string(forKey: "aiModel")
            ?? GeminiRESTClient.defaultModel
        return ActiveAIProvider(
            name: "gemini",
            apiKey: KeychainHelper.shared.read(for: "gemini_api_key") ?? "",
            model: GeminiRESTClient.normalizedModel(selectedModel),
            client: GeminiRESTClient.shared
        )
    }

    private func localTitle(from text: String) -> String {
        let compact = text
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard compact.count > 48 else { return compact }
        return String(compact.prefix(47)).trimmingCharacters(in: .whitespaces) + "…"
    }

    private func markCancelled(_ message: ChatMessage) {
        message.status = .cancelled
        message.errorCode = "cancelled"
        message.errorMessage = AIProviderError.cancelled.localizedDescription
        if message.content.isEmpty {
            message.content = "Response stopped."
        }
    }

    private func markFailed(_ message: ChatMessage, error: AIProviderError) {
        message.status = .failed
        message.errorMessage = error.localizedDescription
        if message.content.isEmpty {
            message.content = error.localizedDescription
        }
        switch error {
        case .missingAPIKey: message.errorCode = "missing_api_key"
        case .authenticationFailed: message.errorCode = "authentication"
        case .quotaExceeded: message.errorCode = "quota"
        case .invalidRequest: message.errorCode = "invalid_request"
        case .serverError: message.errorCode = "server"
        case .invalidResponse, .emptyResponse: message.errorCode = "invalid_response"
        case .cancelled: message.errorCode = "cancelled"
        case .network: message.errorCode = "network"
        }
    }

    private func markDomainFailure(
        _ message: ChatMessage,
        code: String,
        message errorMessage: String
    ) {
        message.status = .failed
        message.errorCode = code
        message.errorMessage = errorMessage
        if message.content.isEmpty {
            message.content = errorMessage
        }
    }

    private func scheduleSummary(
        thread: ChatThread,
        provider: ActiveAIProvider,
        modelContext: ModelContext
    ) {
        guard ThreadSummarizer.shared.shouldSummarize(thread: thread) else { return }
        Task { @MainActor in
            await ThreadSummarizer.shared.summarizeIfNeeded(
                thread: thread,
                apiKey: provider.apiKey,
                model: provider.model,
                providerClient: provider.client
            )
            try? modelContext.save()
        }
    }
}

private struct ActiveAIProvider {
    let name: String
    let apiKey: String
    let model: String
    let client: any AIProviderClient
}
