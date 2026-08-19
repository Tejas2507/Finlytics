import XCTest
@testable import FinSense

@MainActor
final class FinanceBalanceTests: XCTestCase {
    func testBalanceIgnoresQuestionDateScopeAndUsesStartingBalanceDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let oldExpense = Transaction(
            amount: 900,
            date: calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!,
            merchant: "Before balance",
            type: .expense,
            category: "Other"
        )
        let julyIncome = Transaction(
            amount: 2_000,
            date: calendar.date(from: DateComponents(year: 2026, month: 7, day: 2))!,
            merchant: "Salary",
            type: .income,
            category: "Salary"
        )
        let augustExpense = Transaction(
            amount: 500,
            date: calendar.date(from: DateComponents(year: 2026, month: 8, day: 3))!,
            merchant: "Store",
            type: .expense,
            category: "Shopping"
        )
        let investment = Transaction(
            amount: 1_000,
            date: calendar.date(from: DateComponents(year: 2026, month: 8, day: 4))!,
            merchant: "Broker",
            type: .expense,
            category: "Investment"
        )
        let query = FinanceQuery(
            metric: .balance,
            dateScope: FinanceDateScope(preset: .thisMonth)
        )

        let result = try FinanceQueryEngine.shared.execute(
            query,
            context: FinanceQueryContext(
                transactions: [oldExpense, julyIncome, augustExpense, investment],
                startingBalance: 10_000,
                startingBalanceDate: start
            ),
            calendar: calendar,
            now: calendar.date(from: DateComponents(year: 2026, month: 8, day: 15))!
        )

        XCTAssertEqual(result.primaryAmount, Decimal(10_500))
        XCTAssertEqual(result.primaryCount, 3)
        XCTAssertFalse(result.evidence.excludesInvestments)
        XCTAssertTrue(result.evidence.periodLabel.hasPrefix("Since"))
    }
}
