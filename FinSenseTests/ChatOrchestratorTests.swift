import XCTest
import SwiftData
@testable import FinSense

@MainActor
final class ChatOrchestratorTests: XCTestCase {
    func testFactualQuestionUsesLocalCalculationAndPersistsEvidence() async throws {
        let schema = Schema(versionedSchema: FinSenseSchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: FinSenseMigrationPlan.self,
            configurations: [configuration]
        )
        let context = container.mainContext
        let profile = MerchantProfile(
            canonicalKey: "swiggy",
            displayName: "Swiggy",
            aliases: ["Swiggy"],
            tags: ["foodDelivery"]
        )
        let transaction = Transaction(
            amount: 725,
            date: Date(),
            merchant: "Swiggy",
            type: .expense,
            category: "Food & Dining",
            canonicalMerchantKey: "swiggy"
        )
        let thread = ChatThread(mode: .financial)
        let user = ChatMessage(
            role: .user,
            content: "How much did I spend on online food delivery apps this month?"
        )
        let assistant = ChatMessage(
            role: .assistant,
            content: "",
            status: .pending,
            replyToMessageID: user.id
        )
        thread.messages.append(user)
        thread.messages.append(assistant)
        context.insert(profile)
        context.insert(transaction)
        context.insert(thread)
        try context.save()

        await ChatOrchestrator.shared.generateReply(
            thread: thread,
            userMessage: user,
            assistantMessage: assistant,
            transactions: [transaction],
            budgets: [],
            projects: [],
            merchantProfiles: [profile],
            modelContext: context
        )

        XCTAssertEqual(assistant.status, .completed)
        XCTAssertEqual(assistant.evidence?.primaryAmount, Decimal(725))
        XCTAssertEqual(assistant.evidence?.primaryCount, 1)
        XCTAssertTrue(assistant.content.contains("725"))
        XCTAssertEqual(thread.lastQuery?.filters.merchantTags, ["foodDelivery"])
    }

    func testRetryReusesStoredPlanInsteadOfLatestThreadQuery() async throws {
        let schema = Schema(versionedSchema: FinSenseSchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: FinSenseMigrationPlan.self,
            configurations: [configuration]
        )
        let context = container.mainContext
        let food = Transaction(
            amount: 250,
            date: Date(),
            merchant: "Cafe",
            type: .expense,
            category: "Food & Dining"
        )
        let shopping = Transaction(
            amount: 900,
            date: Date(),
            merchant: "Store",
            type: .expense,
            category: "Shopping"
        )
        let storedQuery = FinanceQuery(
            metric: .totalSpent,
            dateScope: FinanceDateScope(preset: .thisMonth),
            filters: FinanceQueryFilters(categories: ["Food & Dining"])
        )
        let thread = ChatThread(mode: .financial)
        thread.lastQuery = FinanceQuery(
            metric: .totalSpent,
            filters: FinanceQueryFilters(categories: ["Shopping"])
        )
        let user = ChatMessage(role: .user, content: "What about this month?")
        let assistant = ChatMessage(
            role: .assistant,
            content: "",
            status: .pending,
            replyToMessageID: user.id
        )
        assistant.queryPlan = FinanceQueryPlan(
            action: .query,
            query: storedQuery,
            clarificationQuestion: nil,
            requiresNarration: false,
            confidence: 1,
            source: .local
        )
        thread.messages.append(user)
        thread.messages.append(assistant)
        context.insert(thread)
        context.insert(food)
        context.insert(shopping)
        try context.save()

        await ChatOrchestrator.shared.generateReply(
            thread: thread,
            userMessage: user,
            assistantMessage: assistant,
            transactions: [food, shopping],
            budgets: [],
            projects: [],
            merchantProfiles: [],
            modelContext: context
        )

        XCTAssertEqual(assistant.evidence?.primaryAmount, Decimal(250))
        XCTAssertEqual(thread.lastQuery?.filters.categories, ["Food & Dining"])
    }
}
