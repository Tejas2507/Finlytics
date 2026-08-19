import XCTest
@testable import FinSense

@MainActor
final class FinancePlannerAndContextTests: XCTestCase {
    func testFoodDeliveryQuestionIsPlannedLocallyWithoutAPIKey() async throws {
        let plan = try await FinanceQueryPlanner.shared.plan(
            question: "How much did I spend on online food delivery apps this month?",
            lastQuery: nil,
            merchantProfiles: [],
            apiKey: "",
            model: GeminiRESTClient.defaultModel
        )

        XCTAssertEqual(plan.source, .local)
        XCTAssertEqual(plan.action, .query)
        XCTAssertEqual(plan.query?.metric, .totalSpent)
        XCTAssertEqual(plan.query?.dateScope.preset, .thisMonth)
        XCTAssertEqual(plan.query?.filters.merchantTags, ["foodDelivery"])
        XCTAssertFalse(plan.requiresNarration)
    }

    func testFollowUpReusesValidatedQueryAndChangesOnlyPeriod() async throws {
        let previousQuery = FinanceQuery(
            metric: .totalSpent,
            dateScope: FinanceDateScope(preset: .thisMonth),
            filters: FinanceQueryFilters(categories: ["Travel"])
        )

        let plan = try await FinanceQueryPlanner.shared.plan(
            question: "What about last month?",
            lastQuery: previousQuery,
            merchantProfiles: [],
            apiKey: "",
            model: GeminiRESTClient.defaultModel
        )

        XCTAssertEqual(plan.source, .local)
        XCTAssertEqual(plan.query?.dateScope.preset, .lastMonth)
        XCTAssertEqual(plan.query?.filters.categories, ["Travel"])
        XCTAssertEqual(plan.query?.metric, .totalSpent)
    }

    func testContextAssemblerKeepsSummaryAndBoundsRecentMessages() {
        let thread = ChatThread(
            rollingSummary: "The user explicitly wants to save for a trip."
        )
        let messages = (0..<30).map { index in
            ChatMessage(
                role: index.isMultiple(of: 2) ? .user : .assistant,
                content: String(repeating: "message \(index) ", count: 40),
                createdAt: Date(timeIntervalSince1970: Double(index))
            )
        }
        thread.messages = messages

        let context = ChatContextAssembler(
            budget: ContextBudget(maximumInputTokens: 800, maximumRecentMessages: 6)
        ).assemble(
            thread: thread,
            messages: messages,
            mode: .financial
        )

        XCTAssertTrue(context.systemInstruction.contains("save for a trip"))
        XCTAssertLessThanOrEqual(context.messages.count, 6)
        XCTAssertLessThanOrEqual(context.estimatedTokenCount, 900)
        XCTAssertEqual(context.messages.last?.text, messages.last?.content)
    }

    func testRetiredGeminiModelNamesNormalizeToCurrentDefault() {
        XCTAssertEqual(
            GeminiRESTClient.normalizedModel("gemini-flash-lite-latest"),
            GeminiRESTClient.defaultModel
        )
        XCTAssertEqual(
            GeminiRESTClient.normalizedModel(GeminiRESTClient.defaultModel),
            GeminiRESTClient.defaultModel
        )
    }

    func testProviderErrorsGiveActionableFreeTierMessage() {
        let error = AIProviderError.quotaExceeded(retryAfter: 42)
        XCTAssertTrue(error.localizedDescription.contains("42"))
        XCTAssertTrue(error.localizedDescription.lowercased().contains("quota"))
    }
}
