import Foundation

struct FinanceAnswerFormatter {
    func format(_ result: FinanceQueryResult) -> String {
        let headline: String

        switch result.query.metric {
        case .totalSpent:
            headline = result.primaryCount == 0
                ? "No matching expense transactions were found during \(result.evidence.periodLabel)."
                : "You spent \(currency(result.primaryAmount ?? 0)) during \(result.evidence.periodLabel)."
        case .totalIncome:
            headline = result.primaryCount == 0
                ? "No matching income transactions were found during \(result.evidence.periodLabel)."
                : "You received \(currency(result.primaryAmount ?? 0)) during \(result.evidence.periodLabel)."
        case .netCashFlow:
            headline = result.primaryCount == 0
                ? "No matching transactions were found during \(result.evidence.periodLabel)."
                : "Your net cash flow was \(signedCurrency(result.primaryAmount ?? 0)) during \(result.evidence.periodLabel)."
        case .transactionCount:
            headline = "There were \(result.primaryCount) matching transactions during \(result.evidence.periodLabel)."
        case .averageTransaction:
            headline = result.primaryCount == 0
                ? "No matching transactions were found during \(result.evidence.periodLabel)."
                : "The average matching transaction was \(currency(result.primaryAmount ?? 0)) during \(result.evidence.periodLabel)."
        case .balance:
            headline = "Your calculated balance is \(currency(result.primaryAmount ?? 0))."
        case .categoryBreakdown, .merchantBreakdown, .topMerchants, .topCategories,
             .budgetStatus, .projectSpend:
            headline = result.groups.isEmpty
                ? "No matching transactions were found for \(result.evidence.periodLabel)."
                : "Here is the verified breakdown for \(result.evidence.periodLabel)."
        }

        var sections = [headline]

        if let comparison = comparisonLine(result) {
            sections.append(comparison)
        }

        if !result.groups.isEmpty {
            sections.append(
                result.groups.prefix(8).map { group in
                    var line = "• \(group.label): \(formattedValue(group.amount, metric: result.query.metric))"
                    if let reference = group.referenceAmount {
                        line += " of \(currency(reference))"
                    }
                    if let detail = group.detail {
                        line += " (\(detail))"
                    } else if result.query.metric != .transactionCount {
                        line += " · \(group.count) \(group.count == 1 ? "transaction" : "transactions")"
                    }
                    return line
                }
                .joined(separator: "\n")
            )
        }

        var scopeNotes: [String] = []
        if result.evidence.excludesHidden {
            scopeNotes.append("Vault items excluded")
        }
        if result.evidence.excludesInvestments {
            scopeNotes.append("investment outflows excluded")
        }
        if !scopeNotes.isEmpty {
            sections.append(scopeNotes.joined(separator: " · "))
        }

        return sections.joined(separator: "\n\n")
    }

    private func comparisonLine(_ result: FinanceQueryResult) -> String? {
        guard
            let previous = result.comparisonAmount,
            let comparisonLabel = result.evidence.comparisonPeriodLabel,
            let current = result.primaryAmount
        else {
            return nil
        }

        let direction: String
        if current > previous {
            direction = "higher"
        } else if current < previous {
            direction = "lower"
        } else {
            direction = "unchanged"
        }

        if direction == "unchanged" {
            return "Compared with \(comparisonLabel), the value was unchanged at \(formattedValue(previous, metric: result.query.metric))."
        }

        let changeText = result.percentageChange.map {
            "\(plainNumber(abs($0)))%"
        } ?? formattedValue(abs(result.absoluteChange ?? 0), metric: result.query.metric)
        return "Compared with \(comparisonLabel) (\(formattedValue(previous, metric: result.query.metric))), this is \(changeText) \(direction)."
    }

    private func formattedValue(_ value: Decimal, metric: FinanceMetric) -> String {
        metric == .transactionCount ? plainNumber(value) : currency(value)
    }

    private func currency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "INR"
        formatter.currencySymbol = "₹"
        formatter.locale = Locale(identifier: "en_IN")
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "₹0"
    }

    private func signedCurrency(_ value: Decimal) -> String {
        value < 0 ? "−\(currency(abs(value)))" : "+\(currency(value))"
    }

    private func plainNumber(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "0"
    }
}
