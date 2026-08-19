import Foundation
import SwiftData

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
        modelContext: ModelContext
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
                    modelContext: modelContext
                )
            case .help:
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
        modelContext: ModelContext
    ) async throws {
        let visibleProfiles = privacySafeProfiles(
            transactions: transactions,
            profiles: merchantProfiles
        )
        let plan: FinanceQueryPlan
        if let storedPlan = assistantMessage.queryPlan {
            plan = storedPlan
        } else {
            plan = try await FinanceQueryPlanner.shared.plan(
                question: userMessage.content,
                lastQuery: thread.lastQuery,
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
        let result = try FinanceQueryEngine.shared.execute(query, context: queryContext)
        assistantMessage.evidence = result
        thread.lastQuery = query

        let verifiedAnswer = FinanceAnswerFormatter().format(result)
        guard plan.requiresNarration else {
            assistantMessage.content = verifiedAnswer
            assistantMessage.status = .completed
            return
        }

        let chatContext = ChatContextAssembler().assemble(
            thread: thread,
            messages: thread.messages,
            mode: .financial,
            additionalInstruction: """
            The app calculated this authoritative result:
            \(verifiedAnswer)

            Answer the latest question in at most 120 words.
            Preserve every number and period exactly. Do not add unsupported causes
            or characterize the user's personality. Label suggestions as suggestions.
            """
        )
        let request = AIProviderRequest(
            systemInstruction: chatContext.systemInstruction,
            messages: chatContext.messages,
            temperature: 0.3,
            maxOutputTokens: 500
        )
        try await stream(request: request, into: assistantMessage, provider: provider)
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
