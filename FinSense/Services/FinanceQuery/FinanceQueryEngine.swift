import Foundation

@MainActor
struct FinanceQueryContext {
    let transactions: [Transaction]
    let budgets: [Budget]
    let projects: [Project]
    let merchantProfiles: [MerchantProfile]
    let monthlySalary: Double
    let startingBalance: Double
    let startingBalanceDate: Date?
    let allowHiddenTransactions: Bool

    init(
        transactions: [Transaction],
        budgets: [Budget] = [],
        projects: [Project] = [],
        merchantProfiles: [MerchantProfile] = [],
        monthlySalary: Double = 0,
        startingBalance: Double = 0,
        startingBalanceDate: Date? = nil,
        allowHiddenTransactions: Bool = false
    ) {
        self.transactions = transactions
        self.budgets = budgets
        self.projects = projects
        self.merchantProfiles = merchantProfiles
        self.monthlySalary = monthlySalary
        self.startingBalance = startingBalance
        self.startingBalanceDate = startingBalanceDate
        self.allowHiddenTransactions = allowHiddenTransactions
    }
}

@MainActor
final class FinanceQueryEngine {
    static let shared = FinanceQueryEngine()

    private init() {}

    func execute(
        _ query: FinanceQuery,
        context: FinanceQueryContext,
        calendar: Calendar = .current,
        now: Date = Date()
    ) throws -> FinanceQueryResult {
        let resolver = FinanceDateResolver(calendar: calendar, now: now)
        let primaryRange = query.metric == .balance
            ? balanceRange(context: context, calendar: calendar)
            : try resolver.resolve(query.dateScope)
        let comparisonRange = query.metric == .balance
            ? nil
            : try resolver.comparisonRange(
                for: query.comparison,
                primary: primaryRange,
                primaryScope: query.dateScope,
                customComparisonScope: query.comparisonDateScope
            )

        let primaryTransactions = filteredTransactions(
            for: query,
            in: primaryRange,
            context: context
        )
        let comparisonTransactions = comparisonRange.map {
            filteredTransactions(for: query, in: $0, context: context)
        } ?? []

        let primary = aggregate(
            transactions: primaryTransactions,
            query: query,
            context: context,
            calendar: calendar
        )
        let comparison = aggregate(
            transactions: comparisonTransactions,
            query: query,
            context: context,
            calendar: calendar
        )

        let primaryAmount = primary.amount
        let comparisonAmount = comparisonRange == nil ? nil : comparison.amount
        let absoluteChange = zipAmounts(primaryAmount, comparisonAmount).map { pair in
            pair.0 - pair.1
        }
        let percentageChange = percentageChange(current: primaryAmount, previous: comparisonAmount)

        let evidence = FinanceEvidence(
            transactionIDs: primaryTransactions.map(\.id),
            comparisonTransactionIDs: comparisonTransactions.map(\.id),
            primaryCount: primaryTransactions.count,
            comparisonCount: comparisonTransactions.count,
            periodLabel: primaryRange.label,
            comparisonPeriodLabel: comparisonRange?.label,
            calculation: calculationDescription(for: query),
            excludesHidden: !context.allowHiddenTransactions,
            excludesInvestments: query.metric == .balance ? false : !query.includeInvestments
        )

        return FinanceQueryResult(
            query: query,
            primaryAmount: primaryAmount,
            comparisonAmount: comparisonAmount,
            absoluteChange: absoluteChange,
            percentageChange: percentageChange,
            primaryCount: primaryTransactions.count,
            comparisonCount: comparisonRange == nil ? nil : comparisonTransactions.count,
            groups: primary.groups,
            comparisonGroups: comparisonRange == nil ? [] : comparison.groups,
            evidence: evidence
        )
    }

    private func balanceRange(
        context: FinanceQueryContext,
        calendar: Calendar
    ) -> ResolvedFinanceDateRange {
        guard let start = context.startingBalanceDate else {
            return ResolvedFinanceDateRange(start: nil, end: nil, label: "All time")
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .medium
        return ResolvedFinanceDateRange(
            start: start,
            end: nil,
            label: "Since \(formatter.string(from: start))"
        )
    }

    private func filteredTransactions(
        for query: FinanceQuery,
        in range: ResolvedFinanceDateRange,
        context: FinanceQueryContext
    ) -> [Transaction] {
        let visibleProjectNames = Set(
            context.projects
                .filter { !$0.isHidden }
                .map(\.name)
        )
        return context.transactions.filter { transaction in
            guard isInRange(transaction.date, range: range) else { return false }
            guard context.allowHiddenTransactions || !transaction.isHidden else { return false }
            guard query.metric == .balance ||
                    query.includeInvestments ||
                    !isInvestmentExpense(transaction) else {
                return false
            }
            guard matchesMetricType(transaction, metric: query.metric) else { return false }

            if !query.filters.transactionTypes.isEmpty,
               !query.filters.transactionTypes.contains(transaction.type) {
                return false
            }

            if !query.filters.categories.isEmpty,
               !query.filters.categories.contains(where: {
                   $0.caseInsensitiveCompare(transaction.category) == .orderedSame
               }) {
                return false
            }

            let profile = MerchantResolver.shared.profile(
                for: transaction,
                profiles: context.merchantProfiles
            )
            if !query.filters.merchantKeys.isEmpty {
                let transactionKey = profile?.canonicalKey
                    ?? transaction.canonicalMerchantKey
                    ?? MerchantResolver.normalize(transaction.merchant)
                guard query.filters.merchantKeys.contains(where: {
                    MerchantResolver.normalize($0) == MerchantResolver.normalize(transactionKey)
                }) else {
                    return false
                }
            }

            if !query.filters.merchantTags.isEmpty {
                let profileMatches = profile?.tags.contains(
                    where: query.filters.merchantTags.contains
                ) ?? false
                let seedMatches = MerchantResolver.shared.matchesSeedTag(
                    merchant: transaction.merchant,
                    requestedTags: query.filters.merchantTags
                )
                guard profileMatches || seedMatches else {
                    return false
                }
            }

            if !query.filters.projectNames.isEmpty {
                guard query.filters.projectNames.contains(where: {
                    visibleProjectNames.contains($0) &&
                    transaction.projectNames.contains($0)
                }) else {
                    return false
                }
            }

            if query.metric == .projectSpend || query.grouping == .project {
                guard transaction.projectNames.contains(where: visibleProjectNames.contains) else {
                    return false
                }
            }

            if !query.filters.searchTerms.isEmpty {
                let searchable = MerchantResolver.normalize(
                    "\(transaction.merchant) \(transaction.category) \(transaction.notes)"
                )
                guard query.filters.searchTerms.contains(where: {
                    searchable.contains(MerchantResolver.normalize($0))
                }) else {
                    return false
                }
            }

            return true
        }
    }

    private func isInRange(_ date: Date, range: ResolvedFinanceDateRange) -> Bool {
        if let start = range.start, date < start { return false }
        if let end = range.end, date >= end { return false }
        return true
    }

    private func isInvestmentExpense(_ transaction: Transaction) -> Bool {
        transaction.type == .expense &&
        transaction.category.localizedCaseInsensitiveContains("invest")
    }

    private func matchesMetricType(_ transaction: Transaction, metric: FinanceMetric) -> Bool {
        switch metric {
        case .totalSpent, .categoryBreakdown, .merchantBreakdown, .topMerchants,
             .topCategories, .budgetStatus, .projectSpend:
            return transaction.type == .expense
        case .totalIncome:
            return transaction.type == .income
        case .netCashFlow, .transactionCount, .averageTransaction, .balance:
            return true
        }
    }

    private func aggregate(
        transactions: [Transaction],
        query: FinanceQuery,
        context: FinanceQueryContext,
        calendar: Calendar
    ) -> (amount: Decimal?, groups: [FinanceResultGroup]) {
        let amount: Decimal?
        switch query.metric {
        case .totalSpent, .projectSpend:
            amount = sum(transactions)
        case .totalIncome:
            amount = sum(transactions)
        case .netCashFlow:
            amount = net(transactions)
        case .transactionCount:
            amount = Decimal(transactions.count)
        case .averageTransaction:
            amount = transactions.isEmpty ? 0 : sum(transactions) / Decimal(transactions.count)
        case .categoryBreakdown, .merchantBreakdown, .topMerchants, .topCategories:
            amount = sum(transactions)
        case .budgetStatus:
            amount = sum(transactions)
        case .balance:
            let referenceDate = context.startingBalanceDate ?? .distantPast
            let balanceTransactions = transactions.filter { $0.date >= referenceDate }
            amount = decimal(context.startingBalance) + net(balanceTransactions)
        }

        let grouping: FinanceGrouping = {
            switch query.metric {
            case .categoryBreakdown, .topCategories, .budgetStatus:
                return .category
            case .merchantBreakdown, .topMerchants:
                return .merchant
            case .projectSpend:
                return query.grouping == .none ? .project : query.grouping
            default:
                return query.grouping
            }
        }()

        let groups: [FinanceResultGroup]
        if query.metric == .budgetStatus {
            groups = budgetGroups(transactions: transactions, budgets: context.budgets, filters: query.filters)
        } else {
            groups = grouped(
                transactions,
                by: grouping,
                metric: query.metric,
                profiles: context.merchantProfiles,
                visibleProjectNames: Set(
                    context.projects
                        .filter { !$0.isHidden }
                        .map(\.name)
                ),
                calendar: calendar
            )
            .sorted { $0.amount > $1.amount }
            .prefix(query.limit)
            .map { $0 }
        }

        return (amount, groups)
    }

    private func grouped(
        _ transactions: [Transaction],
        by grouping: FinanceGrouping,
        metric: FinanceMetric,
        profiles: [MerchantProfile],
        visibleProjectNames: Set<String>,
        calendar: Calendar
    ) -> [FinanceResultGroup] {
        guard grouping != .none else { return [] }

        var buckets: [String: (label: String, transactions: [Transaction])] = [:]
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.locale = .current
        dayFormatter.timeZone = calendar.timeZone
        dayFormatter.dateStyle = .medium

        let monthFormatter = DateFormatter()
        monthFormatter.calendar = calendar
        monthFormatter.locale = .current
        monthFormatter.timeZone = calendar.timeZone
        monthFormatter.dateFormat = "MMM yyyy"

        for transaction in transactions {
            let keys: [(String, String)]
            switch grouping {
            case .none:
                keys = []
            case .category:
                keys = [(MerchantResolver.normalize(transaction.category), transaction.category)]
            case .merchant:
                if let profile = MerchantResolver.shared.profile(for: transaction, profiles: profiles) {
                    keys = [(profile.canonicalKey, profile.displayName)]
                } else {
                    keys = [(MerchantResolver.normalize(transaction.merchant), transaction.merchant)]
                }
            case .day:
                let start = calendar.startOfDay(for: transaction.date)
                keys = [(String(start.timeIntervalSince1970), dayFormatter.string(from: start))]
            case .week:
                let start = calendar.dateInterval(of: .weekOfYear, for: transaction.date)?.start
                    ?? calendar.startOfDay(for: transaction.date)
                keys = [(String(start.timeIntervalSince1970), "Week of \(dayFormatter.string(from: start))")]
            case .month:
                let components = calendar.dateComponents([.year, .month], from: transaction.date)
                let start = calendar.date(from: components) ?? transaction.date
                keys = [(String(start.timeIntervalSince1970), monthFormatter.string(from: start))]
            case .project:
                keys = transaction.projectNames
                    .filter(visibleProjectNames.contains)
                    .map { (MerchantResolver.normalize($0), $0) }
            }

            for (key, label) in keys {
                var bucket = buckets[key] ?? (label, [])
                bucket.transactions.append(transaction)
                buckets[key] = bucket
            }
        }

        return buckets.map { key, bucket in
            FinanceResultGroup(
                key: key,
                label: bucket.label,
                amount: groupedAmount(bucket.transactions, metric: metric),
                count: bucket.transactions.count
            )
        }
    }

    private func groupedAmount(
        _ transactions: [Transaction],
        metric: FinanceMetric
    ) -> Decimal {
        switch metric {
        case .netCashFlow, .balance:
            return net(transactions)
        case .transactionCount:
            return Decimal(transactions.count)
        case .averageTransaction:
            return transactions.isEmpty
                ? .zero
                : sum(transactions) / Decimal(transactions.count)
        case .totalSpent, .totalIncome, .categoryBreakdown, .merchantBreakdown,
             .topMerchants, .topCategories, .budgetStatus, .projectSpend:
            return sum(transactions)
        }
    }

    private func budgetGroups(
        transactions: [Transaction],
        budgets: [Budget],
        filters: FinanceQueryFilters
    ) -> [FinanceResultGroup] {
        budgets
            .filter { budget in
                filters.categories.isEmpty ||
                filters.categories.contains {
                    $0.caseInsensitiveCompare(budget.category) == .orderedSame
                }
            }
            .map { budget in
                let matching = transactions.filter {
                    $0.category.caseInsensitiveCompare(budget.category) == .orderedSame
                }
                let spent = sum(matching)
                let limit = decimal(budget.monthlyLimit)
                let percentage = limit == 0 ? 0 : (spent / limit) * 100
                return FinanceResultGroup(
                    key: MerchantResolver.normalize(budget.category),
                    label: budget.category,
                    amount: spent,
                    count: matching.count,
                    referenceAmount: limit,
                    detail: "\(format(percentage))% used"
                )
            }
            .sorted { $0.amount > $1.amount }
    }

    private func calculationDescription(for query: FinanceQuery) -> String {
        let investmentText = query.includeInvestments ? "including investments" : "excluding investment outflows"
        switch query.metric {
        case .totalSpent:
            return "Sum of expense transactions, \(investmentText)"
        case .totalIncome:
            return "Sum of income transactions"
        case .netCashFlow:
            return "Income minus expenses, \(investmentText)"
        case .transactionCount:
            return "Count of matching transactions"
        case .averageTransaction:
            return "Matching transaction total divided by transaction count"
        case .categoryBreakdown:
            return "Expense total grouped by category, \(investmentText)"
        case .merchantBreakdown, .topMerchants:
            return "Expense total grouped by canonical merchant, \(investmentText)"
        case .topCategories:
            return "Expense total grouped by category, \(investmentText)"
        case .budgetStatus:
            return "Category expense total compared with its monthly budget"
        case .projectSpend:
            return "Expense total for matching project tags, \(investmentText)"
        case .balance:
            return "Starting balance plus income minus expenses since the balance date"
        }
    }

    private func sum(_ transactions: [Transaction]) -> Decimal {
        transactions.reduce(Decimal.zero) { partial, transaction in
            partial + decimal(transaction.amount)
        }
    }

    private func net(_ transactions: [Transaction]) -> Decimal {
        transactions.reduce(Decimal.zero) { partial, transaction in
            let amount = decimal(transaction.amount)
            return transaction.type == .income ? partial + amount : partial - amount
        }
    }

    private func decimal(_ value: Double) -> Decimal {
        Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX")) ?? Decimal(value)
    }

    private func zipAmounts(_ first: Decimal?, _ second: Decimal?) -> (Decimal, Decimal)? {
        guard let first, let second else { return nil }
        return (first, second)
    }

    private func percentageChange(current: Decimal?, previous: Decimal?) -> Decimal? {
        guard let current, let previous, previous != 0 else { return nil }
        return ((current - previous) / previous) * 100
    }

    private func format(_ decimal: Decimal) -> String {
        NSDecimalNumber(decimal: decimal).rounding(
            accordingToBehavior: NSDecimalNumberHandler(
                roundingMode: .plain,
                scale: 0,
                raiseOnExactness: false,
                raiseOnOverflow: false,
                raiseOnUnderflow: false,
                raiseOnDivideByZero: false
            )
        ).stringValue
    }
}
