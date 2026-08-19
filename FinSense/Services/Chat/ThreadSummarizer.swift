import Foundation

@MainActor
final class ThreadSummarizer {
    static let shared = ThreadSummarizer()

    private let minimumUnsummarizedMessages = 14
    private let recentMessagesToKeep = 8
    private let tokenThreshold = 2_600
    private var activeThreadIDs: Set<UUID> = []

    private init() {}

    func shouldSummarize(thread: ChatThread) -> Bool {
        let candidates = unsummarizedMessages(in: thread)
        let estimatedTokens = candidates.reduce(0) {
            $0 + ContextBudget.freeTier.estimateTokens(in: $1.content)
        }
        return candidates.count >= minimumUnsummarizedMessages ||
            estimatedTokens >= tokenThreshold
    }

    func summarizeIfNeeded(
        thread: ChatThread,
        apiKey: String,
        model: String,
        providerClient: any AIProviderClient = GeminiRESTClient.shared
    ) async {
        guard
            shouldSummarize(thread: thread),
            !apiKey.isEmpty,
            activeThreadIDs.insert(thread.id).inserted
        else {
            return
        }
        defer { activeThreadIDs.remove(thread.id) }

        let unsummarized = unsummarizedMessages(in: thread)
        guard unsummarized.count > recentMessagesToKeep else { return }
        let candidates = Array(unsummarized.dropLast(recentMessagesToKeep))
        guard let checkpoint = candidates.last?.createdAt else { return }

        let transcript = candidates.map {
            "\($0.role == .user ? "User" : "Assistant"): \($0.content)"
        }
        .joined(separator: "\n")
        .prefix(12_000)

        let request = AIProviderRequest(
            systemInstruction: """
            Summarize an earlier portion of a personal-finance chat for future conversational continuity.
            Preserve only:
            - questions already answered,
            - explicit goals, preferences, and constraints stated by the user,
            - unresolved questions,
            - the meaning of follow-up references.
            Do not infer personality, emotions, motivation, or spending habits.
            Do not copy transaction lists. Do not add advice or facts.
            Return a concise plain-text summary under 180 words.
            """,
            messages: [
                AIProviderMessage(
                    role: .user,
                    text: """
                    Existing summary:
                    \(thread.rollingSummary.isEmpty ? "None" : thread.rollingSummary)

                    Messages to merge:
                    \(transcript)
                    """
                )
            ],
            temperature: 0,
            maxOutputTokens: 350
        )

        do {
            let response = try await providerClient.generate(
                request: request,
                apiKey: apiKey,
                model: model
            )
            thread.rollingSummary = response.text
            thread.summaryThroughDate = checkpoint
            thread.touch()
        } catch {
            // Summarization is an optimization and must never block chat.
        }
    }

    private func unsummarizedMessages(in thread: ChatThread) -> [ChatMessage] {
        thread.messages
            .filter {
                $0.status == .completed &&
                $0.role != .system &&
                (thread.summaryThroughDate == nil || $0.createdAt > thread.summaryThroughDate!)
            }
            .sorted { $0.createdAt < $1.createdAt }
    }
}
