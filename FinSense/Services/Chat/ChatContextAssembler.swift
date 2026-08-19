import Foundation

struct ChatContext {
    let systemInstruction: String
    let messages: [AIProviderMessage]
    let estimatedTokenCount: Int
}

struct ContextBudget {
    let maximumInputTokens: Int
    let maximumRecentMessages: Int

    static let freeTier = ContextBudget(
        maximumInputTokens: 4_000,
        maximumRecentMessages: 10
    )

    func estimateTokens(in text: String) -> Int {
        // Conservative approximation for mixed English, numbers, and merchant names.
        max(1, Int(ceil(Double(text.utf8.count) / 3.5)))
    }
}

struct ChatContextAssembler {
    var budget: ContextBudget = .freeTier

    func assemble(
        thread: ChatThread,
        messages: [ChatMessage],
        mode: ChatMode,
        additionalInstruction: String? = nil
    ) -> ChatContext {
        let system = systemInstruction(
            mode: mode,
            summary: thread.rollingSummary,
            lastQuery: thread.lastQuery,
            additionalInstruction: additionalInstruction
        )
        var remainingTokens = max(
            400,
            budget.maximumInputTokens - budget.estimateTokens(in: system)
        )

        let eligible = messages
            .filter {
                $0.role != .system &&
                (
                    $0.status == .completed ||
                    ($0.role == .user && $0.status == .pending)
                )
            }
            .sorted { $0.createdAt < $1.createdAt }

        var selected: [(message: ChatMessage, text: String)] = []
        for message in eligible.suffix(budget.maximumRecentMessages).reversed() {
            let cost = budget.estimateTokens(in: message.content) + 8
            if cost <= remainingTokens {
                selected.append((message, message.content))
                remainingTokens -= cost
            } else if selected.isEmpty && remainingTokens > 40 {
                let characterBudget = max(80, Int(Double(remainingTokens - 8) * 3.2))
                selected.append((message, String(message.content.prefix(characterBudget))))
                remainingTokens = 0
                break
            } else {
                break
            }
        }

        let providerMessages = selected.reversed().map {
            AIProviderMessage(
                role: $0.message.role == .user ? .user : .model,
                text: $0.text
            )
        }
        let total = budget.estimateTokens(in: system) +
            providerMessages.reduce(0) { $0 + budget.estimateTokens(in: $1.text) + 8 }

        return ChatContext(
            systemInstruction: system,
            messages: providerMessages,
            estimatedTokenCount: total
        )
    }

    private func systemInstruction(
        mode: ChatMode,
        summary: String,
        lastQuery: FinanceQuery?,
        additionalInstruction: String?
    ) -> String {
        var sections: [String] = []

        switch mode {
        case .financial:
            sections.append("""
            You are Finlytics, a concise personal-finance assistant for Indian users.
            Never calculate or guess financial values. Use only the verified evidence supplied by the app.
            Clearly distinguish facts from suggestions. All currency is INR.
            Do not infer personality, motives, or emotions from spending.
            If evidence is insufficient, say what is missing.
            """)
        case .help:
            sections.append("""
            You are the Finlytics app help guide.
            Give short, precise steps about app usage only.
            You have no access to the user's financial records.
            """)
        }

        if !summary.isEmpty {
            sections.append("""
            Earlier thread summary (user-confirmed facts and conversational continuity only):
            \(summary)
            """)
        }

        if let lastQuery,
           let data = try? JSONEncoder().encode(lastQuery),
           let json = String(data: data, encoding: .utf8) {
            sections.append("Last validated finance query for resolving follow-ups:\n\(json)")
        }

        if let additionalInstruction, !additionalInstruction.isEmpty {
            sections.append(additionalInstruction)
        }

        return sections.joined(separator: "\n\n")
    }
}
