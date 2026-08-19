import XCTest
import SwiftData
@testable import FinSense

@MainActor
final class ChatPersistenceAdditionalTests: XCTestCase {
    func testThreadAndMessagesPersistInSwiftData() throws {
        let schema = Schema(versionedSchema: FinSenseSchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: FinSenseMigrationPlan.self,
            configurations: [configuration]
        )
        let context = container.mainContext

        let thread = ChatThread(title: "Food delivery", mode: .financial)
        let user = ChatMessage(role: .user, content: "How much did I spend?")
        let assistant = ChatMessage(
            role: .assistant,
            content: "You spent ₹950.",
            replyToMessageID: user.id
        )
        context.insert(thread)
        context.insert(user)
        context.insert(assistant)
        thread.messages.append(user)
        thread.messages.append(assistant)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<ChatThread>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.messages.count, 2)
        XCTAssertEqual(
            fetched.first?.messages.first(where: { $0.role == .assistant })?.replyToMessageID,
            user.id
        )
    }

    func testContextBudgetKeepsSummaryAndRecentMessagesBounded() {
        let thread = ChatThread(
            title: "Long thread",
            rollingSummary: "The user explicitly wants to reduce dining spend."
        )
        for index in 0..<30 {
            let message = ChatMessage(
                role: index.isMultiple(of: 2) ? .user : .assistant,
                content: String(repeating: "message \(index) ", count: 80),
                createdAt: Date().addingTimeInterval(Double(index))
            )
            thread.messages.append(message)
        }

        let context = ChatContextAssembler(
            budget: ContextBudget(maximumInputTokens: 1_000, maximumRecentMessages: 6)
        )
        .assemble(
            thread: thread,
            messages: thread.messages,
            mode: .financial
        )

        XCTAssertLessThanOrEqual(context.messages.count, 6)
        XCTAssertLessThanOrEqual(context.estimatedTokenCount, 1_050)
        XCTAssertTrue(context.systemInstruction.contains("reduce dining spend"))
    }

    func testQueryAndEvidenceRoundTripOnMessage() {
        let query = FinanceQuery(
            metric: .totalSpent,
            filters: FinanceQueryFilters(categories: ["Food & Dining"])
        )
        let plan = FinanceQueryPlan(
            action: .query,
            query: query,
            clarificationQuestion: nil,
            requiresNarration: false,
            confidence: 1,
            source: .local
        )
        let evidence = FinanceEvidence(
            transactionIDs: [UUID()],
            comparisonTransactionIDs: [],
            primaryCount: 1,
            comparisonCount: 0,
            periodLabel: "August 2026",
            comparisonPeriodLabel: nil,
            calculation: "Sum of expenses",
            excludesHidden: true,
            excludesInvestments: true
        )
        let result = FinanceQueryResult(
            query: query,
            primaryAmount: Decimal(500),
            comparisonAmount: nil,
            absoluteChange: nil,
            percentageChange: nil,
            primaryCount: 1,
            comparisonCount: nil,
            groups: [],
            comparisonGroups: [],
            evidence: evidence
        )

        let message = ChatMessage(role: .assistant, content: "₹500")
        message.queryPlan = plan
        message.evidence = result

        XCTAssertEqual(message.queryPlan, plan)
        XCTAssertEqual(message.evidence, result)
    }
}

@MainActor
final class ChatPersistenceTests: XCTestCase {
    func testVersionedSchemaCreatesLatestInMemoryStore() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let thread = ChatThread(title: "Food analysis", mode: .financial)
        let user = ChatMessage(role: .user, content: "Compare food spending")
        let assistant = ChatMessage(
            role: .assistant,
            content: "Verified answer",
            replyToMessageID: user.id
        )
        thread.messages.append(user)
        thread.messages.append(assistant)
        context.insert(thread)
        try context.save()

        let storedThreads = try context.fetch(FetchDescriptor<ChatThread>())
        XCTAssertEqual(storedThreads.count, 1)
        XCTAssertEqual(storedThreads.first?.title, "Food analysis")
        XCTAssertEqual(storedThreads.first?.messages.count, 2)
    }

    func testDeletingThreadCascadesToMessages() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let thread = ChatThread()
        thread.messages.append(ChatMessage(role: .user, content: "Hello"))
        context.insert(thread)
        try context.save()

        context.delete(thread)
        try context.save()

        XCTAssertTrue(try context.fetch(FetchDescriptor<ChatThread>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ChatMessage>()).isEmpty)
    }

    func testQueryAndEvidenceRoundTripThroughMessageData() throws {
        let query = FinanceQuery(
            metric: .totalSpent,
            dateScope: FinanceDateScope(preset: .lastMonth),
            filters: FinanceQueryFilters(categories: ["Travel"])
        )
        let plan = FinanceQueryPlan(
            action: .query,
            query: query,
            clarificationQuestion: nil,
            requiresNarration: false,
            confidence: 1,
            source: .local
        )
        let evidence = FinanceEvidence(
            transactionIDs: [UUID()],
            comparisonTransactionIDs: [],
            primaryCount: 1,
            comparisonCount: 0,
            periodLabel: "July 2026",
            comparisonPeriodLabel: nil,
            calculation: "Sum of matching expenses",
            excludesHidden: true,
            excludesInvestments: true
        )
        let result = FinanceQueryResult(
            query: query,
            primaryAmount: Decimal(2_500),
            comparisonAmount: nil,
            absoluteChange: nil,
            percentageChange: nil,
            primaryCount: 1,
            comparisonCount: nil,
            groups: [],
            comparisonGroups: [],
            evidence: evidence
        )
        let message = ChatMessage(role: .assistant, content: "₹2,500")

        message.queryPlan = plan
        message.evidence = result

        XCTAssertEqual(message.queryPlan, plan)
        XCTAssertEqual(message.evidence, result)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: FinSenseSchemaV2.self)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: FinSenseMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
