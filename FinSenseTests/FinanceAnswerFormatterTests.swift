import XCTest
@testable import FinSense

@MainActor
final class FinanceAnswerFormatterTests: XCTestCase {
    func testCountComparisonIsNotFormattedAsCurrency() {
        let query = FinanceQuery(
            metric: .transactionCount,
            dateScope: FinanceDateScope(preset: .thisMonth),
            comparison: .sameElapsedDaysPreviousMonth,
            grouping: .category
        )
        let result = FinanceQueryResult(
            query: query,
            primaryAmount: Decimal(3),
            comparisonAmount: Decimal(2),
            absoluteChange: Decimal(1),
            percentageChange: Decimal(50),
            primaryCount: 3,
            comparisonCount: 2,
            groups: [
                FinanceResultGroup(
                    key: "food",
                    label: "Food & Dining",
                    amount: Decimal(3),
                    count: 3
                )
            ],
            comparisonGroups: [],
            evidence: FinanceEvidence(
                transactionIDs: [],
                comparisonTransactionIDs: [],
                primaryCount: 3,
                comparisonCount: 2,
                periodLabel: "August 2026",
                comparisonPeriodLabel: "July 2026",
                calculation: "Count of matching transactions",
                excludesHidden: true,
                excludesInvestments: true
            )
        )

        let answer = FinanceAnswerFormatter().format(result)

        XCTAssertFalse(answer.contains("₹"))
        XCTAssertTrue(answer.contains("3 matching transactions"))
        XCTAssertTrue(answer.contains("50% higher"))
    }
}
