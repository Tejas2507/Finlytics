import Foundation

enum FinancePlanAction: String, Codable {
    case query
    case clarify
    case generalAdvice
}

enum FinancePlanSource: String, Codable {
    case local
    case gemini
}

struct FinanceQueryPlan: Codable, Equatable {
    let action: FinancePlanAction
    let query: FinanceQuery?
    let clarificationQuestion: String?
    let requiresNarration: Bool
    let confidence: Double
    let source: FinancePlanSource
}

enum FinancePlannerError: LocalizedError {
    case invalidPlan(String)

    var errorDescription: String? {
        switch self {
        case .invalidPlan(let message):
            return "I couldn't safely understand that financial query. \(message)"
        }
    }
}

@MainActor
final class FinanceQueryPlanner {
    static let shared = FinanceQueryPlanner()

    private init() {}

    func plan(
        question: String,
        lastQuery: FinanceQuery?,
        merchantProfiles: [MerchantProfile],
        apiKey: String,
        model: String,
        providerClient: any AIProviderClient = GeminiRESTClient.shared,
        now: Date = Date()
    ) async throws -> FinanceQueryPlan {
        if let localPlan = LocalFinanceIntentParser().plan(
            question: question,
            lastQuery: lastQuery,
            merchantProfiles: merchantProfiles
        ) {
            return localPlan
        }

        let categories = Array(Set(Category.expenseCategories + Category.incomeCategories)).sorted()
        let seededTags = MerchantResolver.seedProfiles.flatMap(\.tags)
        let availableTags = Array(Set(merchantProfiles.flatMap(\.tags) + seededTags)).sorted()
        let merchantKeys = Array(
            Set(
                merchantProfiles
                    .filter { !$0.tags.isEmpty }
                    .map(\.canonicalKey) +
                MerchantResolver.seedProfiles.map(\.canonicalKey)
            )
        ).sorted().prefix(100).map { $0 }

        let request = AIProviderRequest(
            systemInstruction: plannerInstruction(
                categories: categories,
                merchantTags: availableTags,
                merchantKeys: merchantKeys,
                now: now,
                lastQuery: lastQuery
            ),
            messages: [AIProviderMessage(role: .user, text: question)],
            responseSchema: Self.responseSchema,
            temperature: 0,
            maxOutputTokens: 700
        )

        let response = try await providerClient.generate(
            request: request,
            apiKey: apiKey,
            model: model
        )
        let rawPlan: RawFinanceQueryPlan
        do {
            let cleanedResponse = cleanJSON(response.text)
            rawPlan = try JSONDecoder().decode(
                RawFinanceQueryPlan.self,
                from: Data(cleanedResponse.utf8)
            )
        } catch {
            throw FinancePlannerError.invalidPlan("Please rephrase the question with a category or time period.")
        }

        return try validate(
            rawPlan,
            categories: categories,
            merchantTags: availableTags,
            merchantKeys: merchantKeys
        )
    }

    private func cleanJSON(_ text: String) -> String {
        text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```JSON", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validate(
        _ raw: RawFinanceQueryPlan,
        categories: [String],
        merchantTags: [String],
        merchantKeys: [String]
    ) throws -> FinanceQueryPlan {
        let matchedCategories = try raw.categories.map { requested -> String in
            guard let match = categories.first(where: {
                $0.caseInsensitiveCompare(requested) == .orderedSame
            }) else {
                throw FinancePlannerError.invalidPlan("“\(requested)” is not a valid category.")
            }
            return match
        }

        let matchedTags = try raw.merchantTags.map { requested -> String in
            guard let match = merchantTags.first(where: {
                $0.caseInsensitiveCompare(requested) == .orderedSame
            }) else {
                throw FinancePlannerError.invalidPlan("“\(requested)” is not a known merchant group.")
            }
            return match
        }

        let matchedMerchantKeys = try raw.merchantKeys.map { requested -> String in
            guard let match = merchantKeys.first(where: {
                $0.caseInsensitiveCompare(requested) == .orderedSame
            }) else {
                throw FinancePlannerError.invalidPlan("“\(requested)” is not a known merchant.")
            }
            return match
        }

        let transactionTypes = raw.transactionTypes.compactMap(TransactionType.init(rawValue:))
        guard transactionTypes.count == raw.transactionTypes.count else {
            throw FinancePlannerError.invalidPlan("The transaction type was not recognized.")
        }
        
        let customStart = raw.startDate.isEmpty ? nil : raw.startDate
        let customEnd = raw.endDate.isEmpty ? nil : raw.endDate
        if raw.datePreset == .custom && (customStart == nil || customEnd == nil) {
            throw FinancePlannerError.invalidPlan("A custom period needs both start and end dates.")
        }

        let compStart = (raw.comparisonStartDate?.isEmpty ?? true) ? nil : raw.comparisonStartDate
        let compEnd = (raw.comparisonEndDate?.isEmpty ?? true) ? nil : raw.comparisonEndDate
        let customCompScope: FinanceDateScope?
        if let compStart, let compEnd {
            customCompScope = FinanceDateScope(preset: .custom, startDate: compStart, endDate: compEnd)
        } else {
            customCompScope = nil
        }
        let effectiveComparison = customCompScope != nil ? FinanceComparison.customDateScope : raw.comparison

        let query = FinanceQuery(
            metric: raw.metric,
            dateScope: FinanceDateScope(
                preset: raw.datePreset,
                startDate: customStart,
                endDate: customEnd
            ),
            comparison: effectiveComparison,
            comparisonDateScope: customCompScope,
            grouping: raw.grouping,
            filters: FinanceQueryFilters(
                transactionTypes: transactionTypes,
                categories: matchedCategories,
                merchantKeys: matchedMerchantKeys,
                merchantTags: matchedTags,
                projectNames: raw.projectNames,
                searchTerms: raw.searchTerms
            ),
            includeInvestments: raw.includeInvestments,
            limit: raw.limit
        )

        let clarification = raw.clarificationQuestion
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.action == .clarify && clarification.isEmpty {
            throw FinancePlannerError.invalidPlan("The requested filters were ambiguous.")
        }

        return FinanceQueryPlan(
            action: raw.action,
            query: raw.action == .clarify ? nil : query,
            clarificationQuestion: clarification.isEmpty ? nil : clarification,
            requiresNarration: raw.requiresNarration || raw.action == .generalAdvice,
            confidence: min(max(raw.confidence, 0), 1),
            source: .gemini
        )
    }

    private func plannerInstruction(
        categories: [String],
        merchantTags: [String],
        merchantKeys: [String],
        now: Date,
        lastQuery: FinanceQuery?
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        let todayStr = formatter.string(from: now)

        return """
        You are a financial query planner for Finlytics.
        Map user natural language to a JSON plan. Today is \(todayStr).

        Categories available: \(categories.joined(separator: ", "))
        Merchant tags available: \(merchantTags.joined(separator: ", "))
        Known merchant keys: \(merchantKeys.joined(separator: ", "))

        Rules:
        - If comparing two explicit custom months or ranges (e.g., June vs April), set comparison=customDateScope and provide comparisonStartDate and comparisonEndDate in yyyy-MM-dd format.
        - For this month versus last month, use sameElapsedDaysPreviousMonth so partial months are fair.
        - “food delivery apps” maps to merchant tag foodDelivery, not the whole Food & Dining category.
        - Never request hidden or vault data; there is intentionally no field for it.
        - Use custom dates only as yyyy-MM-dd inclusive calendar dates.
        - Keep arrays empty when a filter does not apply and limit between 1 and 25.
        """
    }

    private static let responseSchema = AIJSONSchema.object(
        properties: [
            "action": .string(values: [FinancePlanAction.query.rawValue, FinancePlanAction.clarify.rawValue, FinancePlanAction.generalAdvice.rawValue]),
            "metric": .string(values: FinanceMetric.allCases.map(\.rawValue)),
            "datePreset": .string(values: FinanceDatePreset.allCases.map(\.rawValue)),
            "startDate": .string(description: "yyyy-MM-dd for custom dates, otherwise an empty string"),
            "endDate": .string(description: "yyyy-MM-dd for custom dates, otherwise an empty string"),
            "comparison": .string(values: FinanceComparison.allCases.map(\.rawValue)),
            "comparisonStartDate": .string(description: "yyyy-MM-dd for custom comparison dates, otherwise an empty string"),
            "comparisonEndDate": .string(description: "yyyy-MM-dd for custom comparison dates, otherwise an empty string"),
            "grouping": .string(values: FinanceGrouping.allCases.map(\.rawValue)),
            "transactionTypes": .array(of: .string(values: TransactionType.allCases.map(\.rawValue))),
            "categories": .array(of: .string()),
            "merchantKeys": .array(of: .string()),
            "merchantTags": .array(of: .string()),
            "projectNames": .array(of: .string()),
            "searchTerms": .array(of: .string()),
            "includeInvestments": .boolean(),
            "limit": .integer(),
            "clarificationQuestion": .string(description: "Question for the user, or an empty string"),
            "requiresNarration": .boolean(),
            "confidence": .number(description: "A value from 0 to 1")
        ],
        required: [
            "action", "metric", "datePreset", "startDate", "endDate", "comparison",
            "grouping", "transactionTypes", "categories", "merchantKeys", "merchantTags",
            "projectNames", "searchTerms", "includeInvestments", "limit",
            "clarificationQuestion", "requiresNarration", "confidence"
        ]
    )
}

private struct RawFinanceQueryPlan: Decodable {
    let action: FinancePlanAction
    let metric: FinanceMetric
    let datePreset: FinanceDatePreset
    let startDate: String
    let endDate: String
    let comparison: FinanceComparison
    let comparisonStartDate: String?
    let comparisonEndDate: String?
    let grouping: FinanceGrouping
    let transactionTypes: [String]
    let categories: [String]
    let merchantKeys: [String]
    let merchantTags: [String]
    let projectNames: [String]
    let searchTerms: [String]
    let includeInvestments: Bool
    let limit: Int
    let clarificationQuestion: String
    let requiresNarration: Bool
    let confidence: Double
}

private struct LocalFinanceIntentParser {
    func plan(
        question: String,
        lastQuery: FinanceQuery?,
        merchantProfiles: [MerchantProfile]
    ) -> FinanceQueryPlan? {
        let text = MerchantResolver.normalize(question)
        if requiresRemoteDatePlanning(originalQuestion: question, normalized: text) {
            return nil
        }
        let dateScope = inferredDateScope(in: text)

        if let followUp = followUpDateScope(in: text), let lastQuery {
            var updated = lastQuery
            updated.dateScope = FinanceDateScope(preset: followUp)
            updated.comparison = .none
            return FinanceQueryPlan(
                action: .query,
                query: updated,
                clarificationQuestion: nil,
                requiresNarration: false,
                confidence: 0.99,
                source: .local
            )
        }

        if let merchantTag = inferredMerchantTag(in: text) {
            return FinanceQueryPlan(
                action: .query,
                query: FinanceQuery(
                    metric: .totalSpent,
                    dateScope: dateScope,
                    comparison: inferredComparison(in: text, dateScope: dateScope),
                    filters: FinanceQueryFilters(merchantTags: [merchantTag])
                ),
                clarificationQuestion: nil,
                requiresNarration: false,
                confidence: 0.99,
                source: .local
            )
        }

        if let merchantKey = matchedMerchantKey(
            in: text,
            profiles: merchantProfiles
        ), text.contains("spend") || text.contains("spent") ||
            text.contains("paid") || text.contains("cost") ||
            text.contains("how much") {
            return FinanceQueryPlan(
                action: .query,
                query: FinanceQuery(
                    metric: .totalSpent,
                    dateScope: dateScope,
                    comparison: inferredComparison(in: text, dateScope: dateScope),
                    filters: FinanceQueryFilters(merchantKeys: [merchantKey])
                ),
                clarificationQuestion: nil,
                requiresNarration: false,
                confidence: 0.98,
                source: .local
            )
        }

        if let category = inferredCategory(in: text),
           text.contains("compare") || text.contains("compared") ||
           text.contains(" versus ") || text.contains(" vs ") {
            return FinanceQueryPlan(
                action: .query,
                query: FinanceQuery(
                    metric: .totalSpent,
                    dateScope: dateScope,
                    comparison: inferredComparison(in: text, dateScope: dateScope),
                    filters: FinanceQueryFilters(categories: [category])
                ),
                clarificationQuestion: nil,
                requiresNarration: false,
                confidence: 0.97,
                source: .local
            )
        }

        if text.contains("budget") {
            let categories = inferredCategory(in: text).map { [$0] } ?? []
            return FinanceQueryPlan(
                action: .query,
                query: FinanceQuery(
                    metric: .budgetStatus,
                    dateScope: FinanceDateScope(preset: .thisMonth),
                    grouping: .category,
                    filters: FinanceQueryFilters(categories: categories)
                ),
                clarificationQuestion: nil,
                requiresNarration: false,
                confidence: 0.96,
                source: .local
            )
        }

        if text.contains("top categories") ||
            text.contains("which categories") ||
            text.contains("biggest categories") {
            return FinanceQueryPlan(
                action: .query,
                query: FinanceQuery(
                    metric: .topCategories,
                    dateScope: dateScope,
                    comparison: inferredComparison(in: text, dateScope: dateScope),
                    grouping: .category
                ),
                clarificationQuestion: nil,
                requiresNarration: false,
                confidence: 0.96,
                source: .local
            )
        }

        if text.contains("top merchants") ||
            text.contains("which merchants") ||
            text.contains("biggest merchants") {
            return FinanceQueryPlan(
                action: .query,
                query: FinanceQuery(
                    metric: .topMerchants,
                    dateScope: dateScope,
                    comparison: inferredComparison(in: text, dateScope: dateScope),
                    grouping: .merchant
                ),
                clarificationQuestion: nil,
                requiresNarration: false,
                confidence: 0.96,
                source: .local
            )
        }

        if text.contains("balance") {
            return FinanceQueryPlan(
                action: .query,
                query: FinanceQuery(
                    metric: .balance,
                    dateScope: FinanceDateScope(preset: .allTime),
                    includeInvestments: true
                ),
                clarificationQuestion: nil,
                requiresNarration: false,
                confidence: 0.98,
                source: .local
            )
        }

        if text.contains("income") || text.contains("earned") ||
            text.contains("received") || text.contains("salary total") {
            return FinanceQueryPlan(
                action: .query,
                query: FinanceQuery(
                    metric: .totalIncome,
                    dateScope: dateScope,
                    comparison: inferredComparison(in: text, dateScope: dateScope)
                ),
                clarificationQuestion: nil,
                requiresNarration: false,
                confidence: 0.95,
                source: .local
            )
        }

        if let category = inferredCategory(in: text),
           text.contains("spend") || text.contains("spent") ||
            text.contains("paid") || text.contains("cost") ||
            text.contains("how much") {
            return FinanceQueryPlan(
                action: .query,
                query: FinanceQuery(
                    metric: .totalSpent,
                    dateScope: dateScope,
                    comparison: inferredComparison(in: text, dateScope: dateScope),
                    filters: FinanceQueryFilters(categories: [category])
                ),
                clarificationQuestion: nil,
                requiresNarration: false,
                confidence: 0.97,
                source: .local
            )
        }

        return nil
    }

    private func followUpDateScope(in text: String) -> FinanceDatePreset? {
        guard text.split(separator: " ").count <= 7 else { return nil }
        if text.contains("what about last month") { return .lastMonth }
        if text.contains("what about this month") { return .thisMonth }
        if text.contains("what about all time") { return .allTime }
        if text.contains("and last month") { return .lastMonth }
        return nil
    }

    private func inferredDateScope(in text: String) -> FinanceDateScope {
        if text.contains("all time") || text.contains("ever spent") {
            return FinanceDateScope(preset: .allTime)
        }
        if text.contains("year to date") ||
            text.split(separator: " ").contains("ytd") {
            return FinanceDateScope(preset: .thisYear)
        }
        if text.contains("month to date") ||
            text.split(separator: " ").contains("mtd") {
            return FinanceDateScope(preset: .thisMonth)
        }
        if text.contains("week to date") {
            return FinanceDateScope(preset: .thisWeek)
        }
        if text.contains("yesterday") {
            return FinanceDateScope(preset: .yesterday)
        }
        if text.contains("today") {
            return FinanceDateScope(preset: .today)
        }
        if text.contains("last week") || text.contains("previous week") {
            return FinanceDateScope(preset: .lastWeek)
        }
        if (text.contains("last month") || text.contains("previous month")) &&
            !text.contains("this month") {
            return FinanceDateScope(preset: .lastMonth)
        }
        if text.contains("last 30 days") || text.contains("past 30 days") {
            return FinanceDateScope(preset: .last30Days)
        }
        if text.contains("last 7 days") || text.contains("past 7 days") ||
            text.contains("past week") || text.contains("this week") {
            return FinanceDateScope(
                preset: text.contains("this week") ? .thisWeek : .last7Days
            )
        }
        if text.contains("this year") {
            return FinanceDateScope(preset: .thisYear)
        }
        if text.contains("last year") {
            return FinanceDateScope(preset: .lastYear)
        }
        return FinanceDateScope(preset: .thisMonth)
    }

    private func inferredComparison(
        in text: String,
        dateScope: FinanceDateScope
    ) -> FinanceComparison {
        if text.contains("compare") || text.contains("compared") ||
           text.contains(" versus ") || text.contains(" vs ") {
            switch dateScope.preset {
            case .thisMonth:
                return .sameElapsedDaysPreviousMonth
            case .lastMonth:
                return .previousMonth
            case .thisYear, .lastYear:
                return .previousYear
            default:
                return .previousPeriod
            }
        }
        return .none
    }

    private func requiresRemoteDatePlanning(
        originalQuestion: String,
        normalized: String
    ) -> Bool {
        if originalQuestion.range(
            of: #"\b\d{4}-\d{1,2}-\d{1,2}\b"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        if originalQuestion.range(
            of: #"\b20\d{2}\b"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        if normalized.range(
            of: #"\b(q[1-4]|fy\d{2,4})\b"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        if normalized.range(
            of: #"\b(last|past) \d+ (day|days|week|weeks|month|months)\b"#,
            options: .regularExpression
        ) != nil,
           !normalized.contains("last 7 days"),
           !normalized.contains("past 7 days"),
           !normalized.contains("last 30 days"),
           !normalized.contains("past 30 days") {
            return true
        }
        if normalized.contains(" between ") ||
            (normalized.contains(" from ") && normalized.contains(" to ")) ||
            normalized.contains("quarter") ||
            normalized.contains("financial year") ||
            normalized.contains("past month") ||
            normalized.contains("past year") {
            return true
        }
        let monthNames = [
            "january", "february", "march", "april", "may", "june",
            "july", "august", "september", "october", "november", "december"
        ]
        if monthNames.contains(where: normalized.contains) {
            return true
        }
        let monthAbbreviations: Set<Substring> = [
            "jan", "feb", "mar", "apr", "jun", "jul",
            "aug", "sep", "sept", "oct", "nov", "dec"
        ]
        if !Set(normalized.split(separator: " "))
            .isDisjoint(with: monthAbbreviations) {
            return true
        }

        let knownPeriods = [
            "today", "yesterday", "this week", "last week", "previous week",
            "week to date", "last 7 days", "past 7 days", "past week",
            "this month", "last month", "previous month", "month to date",
            "last 30 days", "past 30 days", "this year", "last year",
            "year to date", "all time", "ever spent", "ytd", "mtd"
        ]
        let hasKnownPeriod = knownPeriods.contains(where: normalized.contains)
        let temporalWords: Set<Substring> = [
            "day", "days", "week", "weeks", "month", "months",
            "year", "years", "since", "before", "after", "ago", "date"
        ]
        let hasTemporalCue = !Set(normalized.split(separator: " "))
            .isDisjoint(with: temporalWords)
        return hasTemporalCue && !hasKnownPeriod
    }

    private func inferredCategory(in text: String) -> String? {
        let synonyms: [String: String] = [
            "food": "Food & Dining",
            "dining": "Food & Dining",
            "transport": "Transportation",
            "travel": "Travel",
            "shopping": "Shopping",
            "entertainment": "Entertainment",
            "bills": "Bills & Utilities",
            "utilities": "Bills & Utilities",
            "healthcare": "Healthcare",
            "health": "Healthcare",
            "education": "Education",
            "personal care": "Personal Care",
            "investment": "Investment",
            "gifts": "Gift",
            "gift": "Gift"
        ]
        let paddedText = " \(text) "
        return synonyms
            .sorted { $0.key.count > $1.key.count }
            .first(where: {
                text == $0.key || paddedText.contains(" \($0.key) ")
            })?
            .value
    }

    private func inferredMerchantTag(in text: String) -> String? {
        let phrases: [(String, String)] = [
            ("food delivery", "foodDelivery"),
            ("online food", "foodDelivery"),
            ("quick commerce", "quickCommerce"),
            ("grocery apps", "grocery"),
            ("online groceries", "grocery"),
            ("ride hailing", "rideHailing"),
            ("cab apps", "rideHailing"),
            ("online shopping", "eCommerce"),
            ("shopping apps", "eCommerce"),
            ("subscriptions", "subscription"),
            ("streaming", "streaming"),
            ("travel booking", "travelBooking"),
            ("pharmacy apps", "pharmacy"),
            ("online medicines", "pharmacy")
        ]
        return phrases.first(where: { text.contains($0.0) })?.1
    }

    private func matchedMerchantKey(
        in text: String,
        profiles: [MerchantProfile]
    ) -> String? {
        let paddedText = " \(text) "
        struct Candidate {
            let key: String
            let alias: String
        }
        var candidates: [Candidate] = []
        for profile in profiles {
            let names = [profile.displayName] + profile.aliases
            for name in names {
                let normalized = MerchantResolver.normalize(name)
                candidates.append(Candidate(key: profile.canonicalKey, alias: normalized))
            }
        }
        let matches = candidates.filter { candidate in
            candidate.alias.count >= 3 && (text == candidate.alias || paddedText.contains(" \(candidate.alias) "))
        }
        return matches.max(by: { $0.alias.count < $1.alias.count })?.key
    }
}
