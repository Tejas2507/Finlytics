import XCTest
@testable import FinSense

@MainActor
final class FinanceDateResolverTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return calendar
    }

    func testCustomEndDateIsInclusiveAndStoredAsExclusiveBoundary() throws {
        let resolver = FinanceDateResolver(
            calendar: calendar,
            now: date("2026-08-15 10:00")
        )
        let range = try resolver.resolve(
            FinanceDateScope(
                preset: .custom,
                startDate: "2026-08-01",
                endDate: "2026-08-15"
            )
        )

        XCTAssertEqual(range.start, date("2026-08-01 00:00"))
        XCTAssertEqual(range.end, date("2026-08-16 00:00"))
    }

    func testSameElapsedDaysUsesEquivalentPreviousMonthWindow() throws {
        let resolver = FinanceDateResolver(
            calendar: calendar,
            now: date("2026-08-15 10:00")
        )
        let primary = try resolver.resolve(FinanceDateScope(preset: .thisMonth))
        let comparison = try XCTUnwrap(
            resolver.comparisonRange(
                for: .sameElapsedDaysPreviousMonth,
                primary: primary
            )
        )

        XCTAssertEqual(comparison.start, date("2026-07-01 00:00"))
        XCTAssertEqual(comparison.end, date("2026-07-16 00:00"))
    }

    private func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)!
    }
}
