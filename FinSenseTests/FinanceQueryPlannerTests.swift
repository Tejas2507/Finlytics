import XCTest
@testable import FinSense

final class FinanceQueryPlannerTests: XCTestCase {
    @MainActor
    func testFoodDeliveryQuestionUsesSemanticMerchantTagWithoutNetwork() async throws {
        let plan = try await FinanceQueryPlanner.shared.plan(
            question: "How much did I spend on online food delivery apps this month?",
            lastQuery: nil,
            merchantProfiles: [],
            apiKey: "",
            model: GeminiRESTClient.defaultModel
        )

        XCTAssertEqual(plan.source, .local)
        XCTAssertEqual(plan.query?.metric, .totalSpent)
        XCTAssertEqual(plan.query?.dateScope.preset, .thisMonth)
        XCTAssertEqual(plan.query?.filters.merchantTags, ["foodDelivery"])
        XCTAssertFalse(plan.requiresNarration)
    }

    @MainActor
    func testCategoryComparisonUsesFairPartialMonthBaseline() async throws {
        let plan = try await FinanceQueryPlanner.shared.plan(
            question: "Compare Food & Dining this month vs last month",
            lastQuery: nil,
            merchantProfiles: [],
            apiKey: "",
            model: GeminiRESTClient.defaultModel
        )

        XCTAssertEqual(plan.query?.filters.categories, ["Food & Dining"])
        XCTAssertEqual(plan.query?.comparison, .sameElapsedDaysPreviousMonth)
        XCTAssertEqual(plan.query?.dateScope.preset, .thisMonth)
    }

    @MainActor
    func testShortFollowUpUpdatesTypedLastQuery() async throws {
        let previous = FinanceQuery(
            metric: .totalSpent,
            dateScope: FinanceDateScope(preset: .thisMonth),
            filters: FinanceQueryFilters(categories: ["Shopping"])
        )

        let plan = try await FinanceQueryPlanner.shared.plan(
            question: "What about last month?",
            lastQuery: previous,
            merchantProfiles: [],
            apiKey: "",
            model: GeminiRESTClient.defaultModel
        )

        XCTAssertEqual(plan.source, .local)
        XCTAssertEqual(plan.query?.dateScope.preset, .lastMonth)
        XCTAssertEqual(plan.query?.filters.categories, ["Shopping"])
    }

    @MainActor
    func testPlannerAcceptsSchemaJSONWrappedInMarkdownFence() async throws {
        let json = """
        ```json
        {
          "action": "query",
          "metric": "topCategories",
          "datePreset": "thisMonth",
          "startDate": "",
          "endDate": "",
          "comparison": "none",
          "grouping": "category",
          "transactionTypes": [],
          "categories": [],
          "merchantKeys": [],
          "merchantTags": [],
          "projectNames": [],
          "searchTerms": [],
          "includeInvestments": false,
          "limit": 5,
          "clarificationQuestion": "",
          "requiresNarration": false,
          "confidence": 0.95
        }
        ```
        """
        let plan = try await FinanceQueryPlanner.shared.plan(
            question: "Rank the main areas where my money went",
            lastQuery: nil,
            merchantProfiles: [],
            apiKey: "test-key",
            model: "test-model",
            providerClient: PlannerStubClient(response: json)
        )

        XCTAssertEqual(plan.source, .gemini)
        XCTAssertEqual(plan.query?.metric, .topCategories)
        XCTAssertEqual(plan.query?.limit, 5)
    }

    @MainActor
    func testKnownMerchantQuestionIsPlannedLocally() async throws {
        let profile = MerchantProfile(
            canonicalKey: "neighborhood-cafe",
            displayName: "Neighborhood Cafe",
            aliases: ["The Neighborhood Cafe"]
        )
        let plan = try await FinanceQueryPlanner.shared.plan(
            question: "How much did I spend at Neighborhood Cafe last month?",
            lastQuery: nil,
            merchantProfiles: [profile],
            apiKey: "",
            model: GeminiRESTClient.defaultModel
        )

        XCTAssertEqual(plan.source, .local)
        XCTAssertEqual(plan.query?.filters.merchantKeys, ["neighborhood-cafe"])
        XCTAssertEqual(plan.query?.dateScope.preset, .lastMonth)
    }

    @MainActor
    func testKnownMerchantNameWinsOverCategorySubstring() async throws {
        let profile = MerchantProfile(
            canonicalKey: "healthkart",
            displayName: "HealthKart",
            aliases: ["HealthKart"]
        )

        let plan = try await FinanceQueryPlanner.shared.plan(
            question: "How much did I spend at HealthKart this month?",
            lastQuery: nil,
            merchantProfiles: [profile],
            apiKey: "",
            model: GeminiRESTClient.defaultModel
        )

        XCTAssertEqual(plan.query?.filters.merchantKeys, ["healthkart"])
        XCTAssertTrue(plan.query?.filters.categories.isEmpty == true)
    }

    @MainActor
    func testLastWeekComparisonUsesPreviousEquivalentWeek() async throws {
        let plan = try await FinanceQueryPlanner.shared.plan(
            question: "Compare my food spend last week with the week before",
            lastQuery: nil,
            merchantProfiles: [],
            apiKey: "",
            model: GeminiRESTClient.defaultModel
        )

        XCTAssertEqual(plan.query?.dateScope.preset, .lastWeek)
        XCTAssertEqual(plan.query?.comparison, .previousPeriod)
    }

    @MainActor
    func testCommonPeriodAliasesNeverSilentlyDefaultToThisMonth() async throws {
        let pastWeek = try await FinanceQueryPlanner.shared.plan(
            question: "How much did I spend on food in the past 7 days?",
            lastQuery: nil,
            merchantProfiles: [],
            apiKey: "",
            model: GeminiRESTClient.defaultModel
        )
        let yearToDate = try await FinanceQueryPlanner.shared.plan(
            question: "How much did I spend on food year to date?",
            lastQuery: nil,
            merchantProfiles: [],
            apiKey: "",
            model: GeminiRESTClient.defaultModel
        )

        XCTAssertEqual(pastWeek.query?.dateScope.preset, .last7Days)
        XCTAssertEqual(yearToDate.query?.dateScope.preset, .thisYear)
    }

    @MainActor
    func testExplicitDateRangeIsDelegatedToStructuredProviderPlanner() async throws {
        let json = """
        {
          "action": "query",
          "metric": "totalSpent",
          "datePreset": "custom",
          "startDate": "2026-07-01",
          "endDate": "2026-07-15",
          "comparison": "none",
          "grouping": "none",
          "transactionTypes": [],
          "categories": ["Food & Dining"],
          "merchantKeys": [],
          "merchantTags": [],
          "projectNames": [],
          "searchTerms": [],
          "includeInvestments": false,
          "limit": 10,
          "clarificationQuestion": "",
          "requiresNarration": false,
          "confidence": 0.99
        }
        """
        let plan = try await FinanceQueryPlanner.shared.plan(
            question: "How much did I spend on food from 2026-07-01 to 2026-07-15?",
            lastQuery: nil,
            merchantProfiles: [],
            apiKey: "test-key",
            model: "test-model",
            providerClient: PlannerStubClient(response: json)
        )

        XCTAssertEqual(plan.source, .gemini)
        XCTAssertEqual(plan.query?.dateScope.preset, .custom)
        XCTAssertEqual(plan.query?.dateScope.startDate, "2026-07-01")
    }

    @MainActor
    func testPlannerRejectsUnknownCategoryFromProvider() async {
        let json = """
        {
          "action": "query",
          "metric": "totalSpent",
          "datePreset": "thisMonth",
          "startDate": "",
          "endDate": "",
          "comparison": "none",
          "grouping": "none",
          "transactionTypes": [],
          "categories": ["Invented Category"],
          "merchantKeys": [],
          "merchantTags": [],
          "projectNames": [],
          "searchTerms": [],
          "includeInvestments": false,
          "limit": 500,
          "clarificationQuestion": "",
          "requiresNarration": false,
          "confidence": 0.9
        }
        """

        do {
            _ = try await FinanceQueryPlanner.shared.plan(
                question: "Use a category the app does not have",
                lastQuery: nil,
                merchantProfiles: [],
                apiKey: "test-key",
                model: "test-model",
                providerClient: PlannerStubClient(response: json)
            )
            XCTFail("Expected invalid plan")
        } catch is FinancePlannerError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

@MainActor
private final class PlannerStubClient: AIProviderClient {
    let response: String

    init(response: String) {
        self.response = response
    }

    func generate(
        request: AIProviderRequest,
        apiKey: String,
        model: String
    ) async throws -> AIProviderResponse {
        AIProviderResponse(
            text: response,
            promptTokenCount: nil,
            responseTokenCount: nil
        )
    }

    func stream(
        request: AIProviderRequest,
        apiKey: String,
        model: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(response)
            continuation.finish()
        }
    }
}
