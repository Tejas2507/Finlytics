import Foundation

enum FinanceMetric: String, Codable, CaseIterable {
    case totalSpent
    case totalIncome
    case netCashFlow
    case transactionCount
    case averageTransaction
    case categoryBreakdown
    case merchantBreakdown
    case topMerchants
    case topCategories
    case budgetStatus
    case projectSpend
    case balance
}

enum FinanceDatePreset: String, Codable, CaseIterable {
    case today
    case yesterday
    case thisWeek
    case lastWeek
    case thisMonth
    case lastMonth
    case last7Days
    case last30Days
    case thisYear
    case lastYear
    case allTime
    case custom
}

struct FinanceDateScope: Codable, Equatable {
    var preset: FinanceDatePreset
    /// Inclusive local calendar day in yyyy-MM-dd format.
    var startDate: String?
    /// Inclusive local calendar day in yyyy-MM-dd format.
    var endDate: String?

    init(
        preset: FinanceDatePreset = .thisMonth,
        startDate: String? = nil,
        endDate: String? = nil
    ) {
        self.preset = preset
        self.startDate = startDate
        self.endDate = endDate
    }
}

enum FinanceComparison: String, Codable, CaseIterable {
    case none
    case previousPeriod
    case previousMonth
    case previousYear
    case sameElapsedDaysPreviousMonth
}

enum FinanceGrouping: String, Codable, CaseIterable {
    case none
    case category
    case merchant
    case day
    case week
    case month
    case project
}

struct FinanceQueryFilters: Codable, Equatable {
    var transactionTypes: [TransactionType]
    var categories: [String]
    var merchantKeys: [String]
    var merchantTags: [String]
    var projectNames: [String]
    var searchTerms: [String]

    init(
        transactionTypes: [TransactionType] = [],
        categories: [String] = [],
        merchantKeys: [String] = [],
        merchantTags: [String] = [],
        projectNames: [String] = [],
        searchTerms: [String] = []
    ) {
        self.transactionTypes = transactionTypes
        self.categories = categories
        self.merchantKeys = merchantKeys
        self.merchantTags = merchantTags
        self.projectNames = projectNames
        self.searchTerms = searchTerms
    }
}

struct FinanceQuery: Codable, Equatable {
    var metric: FinanceMetric
    var dateScope: FinanceDateScope
    var comparison: FinanceComparison
    var grouping: FinanceGrouping
    var filters: FinanceQueryFilters
    var includeInvestments: Bool
    var limit: Int

    init(
        metric: FinanceMetric,
        dateScope: FinanceDateScope = FinanceDateScope(),
        comparison: FinanceComparison = .none,
        grouping: FinanceGrouping = .none,
        filters: FinanceQueryFilters = FinanceQueryFilters(),
        includeInvestments: Bool = false,
        limit: Int = 10
    ) {
        self.metric = metric
        self.dateScope = dateScope
        self.comparison = comparison
        self.grouping = grouping
        self.filters = filters
        self.includeInvestments = includeInvestments
        self.limit = min(max(limit, 1), 25)
    }
}

struct ResolvedFinanceDateRange: Equatable {
    /// Inclusive lower bound. Nil means no lower bound.
    let start: Date?
    /// Exclusive upper bound. Nil means no upper bound.
    let end: Date?
    let label: String
}

struct FinanceResultGroup: Codable, Identifiable, Equatable {
    var id: String { key }
    let key: String
    let label: String
    let amount: Decimal
    let count: Int
    let referenceAmount: Decimal?
    let detail: String?

    init(
        key: String,
        label: String,
        amount: Decimal,
        count: Int,
        referenceAmount: Decimal? = nil,
        detail: String? = nil
    ) {
        self.key = key
        self.label = label
        self.amount = amount
        self.count = count
        self.referenceAmount = referenceAmount
        self.detail = detail
    }
}

struct FinanceEvidence: Codable, Equatable {
    let transactionIDs: [UUID]
    let comparisonTransactionIDs: [UUID]
    let primaryCount: Int
    let comparisonCount: Int
    let periodLabel: String
    let comparisonPeriodLabel: String?
    let calculation: String
    let excludesHidden: Bool
    let excludesInvestments: Bool
}

struct FinanceQueryResult: Codable, Equatable {
    let query: FinanceQuery
    let primaryAmount: Decimal?
    let comparisonAmount: Decimal?
    let absoluteChange: Decimal?
    let percentageChange: Decimal?
    let primaryCount: Int
    let comparisonCount: Int?
    let groups: [FinanceResultGroup]
    let comparisonGroups: [FinanceResultGroup]
    let evidence: FinanceEvidence
}

enum FinanceQueryError: LocalizedError, Equatable {
    case invalidDateRange
    case unsupportedMetric
    case noMatchingMerchantTag(String)
    case hiddenDataRequiresAuthentication

    var errorDescription: String? {
        switch self {
        case .invalidDateRange:
            return "The requested date range is invalid."
        case .unsupportedMetric:
            return "That financial calculation is not supported yet."
        case .noMatchingMerchantTag(let tag):
            return "No merchants are classified as \(tag) yet."
        case .hiddenDataRequiresAuthentication:
            return "Vault data requires authentication."
        }
    }
}
