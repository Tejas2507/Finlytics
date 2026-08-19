import XCTest
@testable import FinSense

final class FinanceQueryEngineTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @MainActor
    func testFoodDeliveryTagSumsEveryVisibleMatchingTransaction() throws {
        let swiggy = MerchantProfile(
            canonicalKey: "swiggy",
            displayName: "Swiggy",
            aliases: ["Swiggy"],
            tags: ["foodDelivery"]
        )
        let zomato = MerchantProfile(
            canonicalKey: "zomato",
            displayName: "Zomato",
            aliases: ["Zomato"],
            tags: ["foodDelivery"]
        )
        let transactions = [
            transaction(450, "Swiggy", "Food & Dining", "2026-08-05", key: "swiggy"),
            transaction(500, "Zomato", "Food & Dining", "2026-08-12", key: "zomato"),
            transaction(300, "Local Cafe", "Food & Dining", "2026-08-13"),
            transaction(200, "Zomato", "Food & Dining", "2026-08-14", hidden: true, key: "zomato")
        ]
        let query = FinanceQuery(
            metric: .totalSpent,
            dateScope: FinanceDateScope(preset: .thisMonth),
            filters: FinanceQueryFilters(merchantTags: ["foodDelivery"])
        )

        let result = try FinanceQueryEngine.shared.execute(
            query,
            context: FinanceQueryContext(
                transactions: transactions,
                merchantProfiles: [swiggy, zomato]
            ),
            calendar: calendar,
            now: date("2026-08-15")
        )

        XCTAssertEqual(result.primaryAmount, Decimal(950))
        XCTAssertEqual(result.primaryCount, 2)
        XCTAssertTrue(result.evidence.excludesHidden)
        XCTAssertEqual(Set(result.evidence.transactionIDs).count, 2)
    }

    @MainActor
    func testSameElapsedDaysComparisonDoesNotCompareAgainstFullPreviousMonth() throws {
        let transactions = [
            transaction(600, "Cafe", "Food & Dining", "2026-08-10"),
            transaction(400, "Cafe", "Food & Dining", "2026-07-08"),
            transaction(900, "Cafe", "Food & Dining", "2026-07-25")
        ]
        let query = FinanceQuery(
            metric: .totalSpent,
            dateScope: FinanceDateScope(preset: .thisMonth),
            comparison: .sameElapsedDaysPreviousMonth,
            filters: FinanceQueryFilters(categories: ["Food & Dining"])
        )

        let result = try FinanceQueryEngine.shared.execute(
            query,
            context: FinanceQueryContext(transactions: transactions),
            calendar: calendar,
            now: date("2026-08-15")
        )

        XCTAssertEqual(result.primaryAmount, Decimal(600))
        XCTAssertEqual(result.comparisonAmount, Decimal(400))
        XCTAssertEqual(result.percentageChange, Decimal(50))
        XCTAssertEqual(result.comparisonCount, 1)
    }

    @MainActor
    func testInvestmentAndVaultPoliciesAreAppliedBeforeAggregation() throws {
        let transactions = [
            transaction(700, "Store", "Shopping", "2026-08-02"),
            transaction(1_000, "Broker", "Investment", "2026-08-03"),
            transaction(200, "Private", "Shopping", "2026-08-04", hidden: true)
        ]
        let query = FinanceQuery(
            metric: .totalSpent,
            dateScope: FinanceDateScope(preset: .thisMonth)
        )

        let result = try FinanceQueryEngine.shared.execute(
            query,
            context: FinanceQueryContext(transactions: transactions),
            calendar: calendar,
            now: date("2026-08-15")
        )

        XCTAssertEqual(result.primaryAmount, Decimal(700))
        XCTAssertEqual(result.primaryCount, 1)
        XCTAssertTrue(result.evidence.excludesInvestments)
        XCTAssertTrue(result.evidence.excludesHidden)
    }

    @MainActor
    func testZeroComparisonBaselineDoesNotInventPercentage() throws {
        let query = FinanceQuery(
            metric: .totalSpent,
            dateScope: FinanceDateScope(preset: .thisMonth),
            comparison: .sameElapsedDaysPreviousMonth
        )
        let result = try FinanceQueryEngine.shared.execute(
            query,
            context: FinanceQueryContext(
                transactions: [transaction(300, "Cafe", "Food & Dining", "2026-08-02")]
            ),
            calendar: calendar,
            now: date("2026-08-15")
        )

        XCTAssertEqual(result.comparisonAmount, Decimal.zero)
        XCTAssertNil(result.percentageChange)
    }

    @MainActor
    func testGroupedNetCashFlowUsesSignedAmounts() throws {
        let income = Transaction(
            amount: 1_000,
            date: date("2026-08-02"),
            merchant: "Acme",
            type: .income,
            category: "Business"
        )
        let expense = Transaction(
            amount: 400,
            date: date("2026-08-03"),
            merchant: "Acme",
            type: .expense,
            category: "Other"
        )
        let query = FinanceQuery(
            metric: .netCashFlow,
            dateScope: FinanceDateScope(preset: .thisMonth),
            grouping: .merchant
        )

        let result = try FinanceQueryEngine.shared.execute(
            query,
            context: FinanceQueryContext(transactions: [income, expense]),
            calendar: calendar,
            now: date("2026-08-15")
        )

        XCTAssertEqual(result.groups.first?.amount, Decimal(600))
        XCTAssertEqual(result.groups.first?.count, 2)
    }

    @MainActor
    func testHiddenProjectsAreExcludedFromProjectQueriesAndGrouping() throws {
        let visibleProject = Project(name: "Vacation")
        let hiddenProject = Project(name: "Private Event")
        hiddenProject.isHidden = true
        let visibleTransaction = transaction(
            300,
            "Hotel",
            "Travel",
            "2026-08-02"
        )
        visibleTransaction.projectNames = ["Vacation"]
        let hiddenProjectTransaction = transaction(
            900,
            "Venue",
            "Other",
            "2026-08-03"
        )
        hiddenProjectTransaction.projectNames = ["Private Event"]

        let grouped = try FinanceQueryEngine.shared.execute(
            FinanceQuery(
                metric: .projectSpend,
                dateScope: FinanceDateScope(preset: .thisMonth),
                grouping: .project
            ),
            context: FinanceQueryContext(
                transactions: [visibleTransaction, hiddenProjectTransaction],
                projects: [visibleProject, hiddenProject]
            ),
            calendar: calendar,
            now: date("2026-08-15")
        )
        let hiddenFilter = try FinanceQueryEngine.shared.execute(
            FinanceQuery(
                metric: .projectSpend,
                dateScope: FinanceDateScope(preset: .thisMonth),
                filters: FinanceQueryFilters(projectNames: ["Private Event"])
            ),
            context: FinanceQueryContext(
                transactions: [visibleTransaction, hiddenProjectTransaction],
                projects: [visibleProject, hiddenProject]
            ),
            calendar: calendar,
            now: date("2026-08-15")
        )

        XCTAssertEqual(grouped.primaryAmount, Decimal(300))
        XCTAssertEqual(grouped.groups.map(\.label), ["Vacation"])
        XCTAssertEqual(hiddenFilter.primaryAmount, Decimal.zero)
        XCTAssertTrue(hiddenFilter.groups.isEmpty)
    }

    @MainActor
    private func transaction(
        _ amount: Double,
        _ merchant: String,
        _ category: String,
        _ day: String,
        hidden: Bool = false,
        key: String? = nil
    ) -> Transaction {
        Transaction(
            amount: amount,
            date: date(day),
            merchant: merchant,
            type: .expense,
            category: category,
            isHidden: hidden,
            canonicalMerchantKey: key
        )
    }

    private func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)!
    }
}
import XCTest
@testable import FinSense

final class FinanceQueryEngineAdditionalTests: XCTestCase {
    private var calendar: Calendar!
    private var now: Date!

    override func setUp() {
        super.setUp()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        self.calendar = calendar
        now = makeDate(2026, 8, 15)
    }

    @MainActor
    func testFoodDeliveryUsesSemanticMerchantTagAndExcludesVault() throws {
        let swiggy = profile(
            key: "swiggy",
            name: "Swiggy",
            aliases: ["swiggy"],
            tags: ["foodDelivery"]
        )
        let zomato = profile(
            key: "zomato",
            name: "Zomato",
            aliases: ["zomato"],
            tags: ["foodDelivery"]
        )
        let transactions = [
            transaction(500, date: makeDate(2026, 8, 2), merchant: "SWIGGY", category: "Food & Dining"),
            transaction(300, date: makeDate(2026, 8, 4), merchant: "Zomato", category: "Food & Dining"),
            transaction(1_000, date: makeDate(2026, 8, 5), merchant: "Zomato", category: "Food & Dining", hidden: true),
            transaction(700, date: makeDate(2026, 8, 6), merchant: "Local Restaurant", category: "Food & Dining")
        ]
        let query = FinanceQuery(
            metric: .totalSpent,
            dateScope: FinanceDateScope(preset: .thisMonth),
            filters: FinanceQueryFilters(merchantTags: ["foodDelivery"])
        )

        let result = try FinanceQueryEngine.shared.execute(
            query,
            context: FinanceQueryContext(
                transactions: transactions,
                merchantProfiles: [swiggy, zomato]
            ),
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(result.primaryAmount, Decimal(800))
        XCTAssertEqual(result.primaryCount, 2)
        XCTAssertTrue(result.evidence.excludesHidden)
    }

    @MainActor
    func testSameElapsedDaysComparisonDoesNotComparePartialMonthWithFullMonth() throws {
        let transactions = [
            transaction(600, date: makeDate(2026, 8, 3), merchant: "Cafe", category: "Food & Dining"),
            transaction(400, date: makeDate(2026, 7, 5), merchant: "Cafe", category: "Food & Dining"),
            transaction(9_000, date: makeDate(2026, 7, 25), merchant: "Restaurant", category: "Food & Dining")
        ]
        let query = FinanceQuery(
            metric: .totalSpent,
            dateScope: FinanceDateScope(preset: .thisMonth),
            comparison: .sameElapsedDaysPreviousMonth,
            filters: FinanceQueryFilters(categories: ["Food & Dining"])
        )

        let result = try FinanceQueryEngine.shared.execute(
            query,
            context: FinanceQueryContext(transactions: transactions),
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(result.primaryAmount, Decimal(600))
        XCTAssertEqual(result.comparisonAmount, Decimal(400))
        XCTAssertEqual(result.percentageChange, Decimal(50))
        XCTAssertEqual(result.comparisonCount, 1)
    }

    @MainActor
    func testInvestmentOutflowsAreExcludedUnlessExplicitlyRequested() throws {
        let transactions = [
            transaction(1_000, date: makeDate(2026, 8, 2), merchant: "Grocer", category: "Shopping"),
            transaction(5_000, date: makeDate(2026, 8, 3), merchant: "Broker", category: "Investment")
        ]
        let defaultQuery = FinanceQuery(
            metric: .totalSpent,
            dateScope: FinanceDateScope(preset: .thisMonth)
        )
        var includingInvestments = defaultQuery
        includingInvestments.includeInvestments = true

        let context = FinanceQueryContext(transactions: transactions)
        let defaultResult = try FinanceQueryEngine.shared.execute(
            defaultQuery,
            context: context,
            calendar: calendar,
            now: now
        )
        let inclusiveResult = try FinanceQueryEngine.shared.execute(
            includingInvestments,
            context: context,
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(defaultResult.primaryAmount, Decimal(1_000))
        XCTAssertEqual(inclusiveResult.primaryAmount, Decimal(6_000))
    }

    @MainActor
    func testCustomDateRangeUsesInclusiveCalendarDays() throws {
        let transactions = [
            transaction(100, date: makeDate(2026, 8, 1), merchant: "A", category: "Other"),
            transaction(200, date: makeDate(2026, 8, 2), merchant: "B", category: "Other"),
            transaction(300, date: makeDate(2026, 8, 3), merchant: "C", category: "Other")
        ]
        let query = FinanceQuery(
            metric: .totalSpent,
            dateScope: FinanceDateScope(
                preset: .custom,
                startDate: "2026-08-01",
                endDate: "2026-08-02"
            )
        )

        let result = try FinanceQueryEngine.shared.execute(
            query,
            context: FinanceQueryContext(transactions: transactions),
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(result.primaryAmount, Decimal(300))
        XCTAssertEqual(result.primaryCount, 2)
    }

    @MainActor
    private func transaction(
        _ amount: Double,
        date: Date,
        merchant: String,
        category: String,
        hidden: Bool = false
    ) -> Transaction {
        Transaction(
            amount: amount,
            date: date,
            merchant: merchant,
            type: .expense,
            category: category,
            isHidden: hidden
        )
    }

    @MainActor
    private func profile(
        key: String,
        name: String,
        aliases: [String],
        tags: [String]
    ) -> MerchantProfile {
        MerchantProfile(
            canonicalKey: key,
            displayName: name,
            aliases: aliases,
            tags: tags
        )
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
}
