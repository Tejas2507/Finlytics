import Foundation

struct FinanceDateResolver {
    var calendar: Calendar
    var now: Date

    init(calendar: Calendar = .current, now: Date = Date()) {
        self.calendar = calendar
        self.now = now
    }

    func resolve(_ scope: FinanceDateScope) throws -> ResolvedFinanceDateRange {
        let today = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else {
            throw FinanceQueryError.invalidDateRange
        }

        switch scope.preset {
        case .today:
            return makeRange(start: today, end: tomorrow, label: dayLabel(today))
        case .yesterday:
            guard let start = calendar.date(byAdding: .day, value: -1, to: today) else {
                throw FinanceQueryError.invalidDateRange
            }
            return makeRange(start: start, end: today, label: dayLabel(start))
        case .thisWeek:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else {
                throw FinanceQueryError.invalidDateRange
            }
            return makeRange(start: interval.start, end: tomorrow, label: rangeLabel(interval.start, tomorrow))
        case .lastWeek:
            guard
                let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now),
                let start = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek.start)
            else {
                throw FinanceQueryError.invalidDateRange
            }
            return makeRange(start: start, end: thisWeek.start, label: rangeLabel(start, thisWeek.start))
        case .thisMonth:
            let start = startOfMonth(containing: now)
            return makeRange(start: start, end: tomorrow, label: monthToDateLabel(start, through: today))
        case .lastMonth:
            let end = startOfMonth(containing: now)
            guard let start = calendar.date(byAdding: .month, value: -1, to: end) else {
                throw FinanceQueryError.invalidDateRange
            }
            return makeRange(start: start, end: end, label: monthLabel(start))
        case .last7Days:
            guard let start = calendar.date(byAdding: .day, value: -6, to: today) else {
                throw FinanceQueryError.invalidDateRange
            }
            return makeRange(start: start, end: tomorrow, label: rangeLabel(start, tomorrow))
        case .last30Days:
            guard let start = calendar.date(byAdding: .day, value: -29, to: today) else {
                throw FinanceQueryError.invalidDateRange
            }
            return makeRange(start: start, end: tomorrow, label: rangeLabel(start, tomorrow))
        case .thisYear:
            let start = startOfYear(containing: now)
            return makeRange(start: start, end: tomorrow, label: yearToDateLabel(start, through: today))
        case .lastYear:
            let end = startOfYear(containing: now)
            guard let start = calendar.date(byAdding: .year, value: -1, to: end) else {
                throw FinanceQueryError.invalidDateRange
            }
            return makeRange(start: start, end: end, label: yearLabel(start))
        case .allTime:
            return ResolvedFinanceDateRange(start: nil, end: nil, label: "All time")
        case .custom:
            guard
                let startText = scope.startDate,
                let endText = scope.endDate,
                let start = parseDay(startText),
                let inclusiveEnd = parseDay(endText),
                let end = calendar.date(byAdding: .day, value: 1, to: inclusiveEnd),
                start < end
            else {
                throw FinanceQueryError.invalidDateRange
            }
            return makeRange(start: start, end: end, label: rangeLabel(start, end))
        }
    }

    func comparisonRange(
        for comparison: FinanceComparison,
        primary: ResolvedFinanceDateRange,
        primaryScope: FinanceDateScope? = nil,
        customComparisonScope: FinanceDateScope? = nil
    ) throws -> ResolvedFinanceDateRange? {
        guard comparison != .none else { return nil }
        if comparison == .customDateScope, let customComparisonScope {
            return try resolve(customComparisonScope)
        }
        guard let primaryStart = primary.start, let primaryEnd = primary.end else {
            return nil
        }

        switch comparison {
        case .none:
            return nil
        case .customDateScope:
            if let customComparisonScope {
                return try resolve(customComparisonScope)
            }
            return nil
        case .previousPeriod:
            if primaryScope?.preset == .thisWeek,
               let start = calendar.date(byAdding: .weekOfYear, value: -1, to: primaryStart),
               let end = calendar.date(byAdding: .weekOfYear, value: -1, to: primaryEnd) {
                return makeRange(start: start, end: end, label: rangeLabel(start, end))
            }
            let duration = primaryEnd.timeIntervalSince(primaryStart)
            let start = primaryStart.addingTimeInterval(-duration)
            return makeRange(start: start, end: primaryStart, label: rangeLabel(start, primaryStart))
        case .previousMonth:
            let end = startOfMonth(containing: primaryStart)
            guard let start = calendar.date(byAdding: .month, value: -1, to: end) else {
                throw FinanceQueryError.invalidDateRange
            }
            return makeRange(start: start, end: end, label: monthLabel(start))
        case .previousYear:
            guard
                let start = calendar.date(byAdding: .year, value: -1, to: primaryStart),
                let end = calendar.date(byAdding: .year, value: -1, to: primaryEnd)
            else {
                throw FinanceQueryError.invalidDateRange
            }
            return makeRange(start: start, end: end, label: rangeLabel(start, end))
        case .sameElapsedDaysPreviousMonth:
            guard
                let start = calendar.date(byAdding: .month, value: -1, to: startOfMonth(containing: primaryStart))
            else {
                throw FinanceQueryError.invalidDateRange
            }
            let elapsedDays = max(1, calendar.dateComponents([.day], from: primaryStart, to: primaryEnd).day ?? 1)
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: start)
            let proposedEnd = calendar.date(byAdding: .day, value: elapsedDays, to: start)
            guard let monthEnd = nextMonth, let candidateEnd = proposedEnd else {
                throw FinanceQueryError.invalidDateRange
            }
            let end = min(candidateEnd, monthEnd)
            return makeRange(start: start, end: end, label: rangeLabel(start, end))
        }
    }

    private func makeRange(start: Date?, end: Date?, label: String) -> ResolvedFinanceDateRange {
        ResolvedFinanceDateRange(start: start, end: end, label: label)
    }

    private func startOfMonth(containing date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? calendar.startOfDay(for: date)
    }

    private func startOfYear(containing date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year], from: date)) ?? calendar.startOfDay(for: date)
    }

    private func parseDay(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private func monthLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private func yearLabel(_ date: Date) -> String {
        String(calendar.component(.year, from: date))
    }

    private func monthToDateLabel(_ start: Date, through end: Date) -> String {
        "\(monthLabel(start)) through \(calendar.component(.day, from: end))"
    }

    private func yearToDateLabel(_ start: Date, through end: Date) -> String {
        "\(yearLabel(start)) through \(dayLabel(end))"
    }

    private func rangeLabel(_ start: Date, _ exclusiveEnd: Date) -> String {
        let inclusiveEnd = calendar.date(byAdding: .day, value: -1, to: exclusiveEnd) ?? exclusiveEnd
        return "\(dayLabel(start)) – \(dayLabel(inclusiveEnd))"
    }
}
