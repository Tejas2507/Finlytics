import Foundation
import SwiftData

@MainActor
final class MerchantClassificationService {
    static let shared = MerchantClassificationService()

    private init() {}

    func classifyUnknownMerchantsIfNeeded(
        transactions: [Transaction],
        existingProfiles: [MerchantProfile],
        requestedTags: [String],
        apiKey: String,
        model: String,
        providerClient: any AIProviderClient,
        modelContext: ModelContext
    ) async -> [MerchantProfile] {
        var profiles = existingProfiles
        let unknownNames = Array(
            Dictionary(
                grouping: transactions.filter {
                    guard !$0.isHidden else { return false }
                    guard isPlausibleCandidate(
                        category: $0.category,
                        requestedTags: requestedTags
                    ) else {
                        return false
                    }
                    if MerchantResolver.shared.seedProfile(for: $0.merchant) != nil {
                        return false
                    }
                    guard let profile = MerchantResolver.shared.profile(for: $0, profiles: profiles) else {
                        return true
                    }
                    return profile.tags.isEmpty &&
                        !profile.isUserOverride &&
                        profile.confidence == 0
                },
                by: { MerchantResolver.normalize($0.merchant) }
            )
            .values
            .compactMap { $0.first?.merchant }
            .prefix(25)
        )

        guard !unknownNames.isEmpty, !apiKey.isEmpty else { return profiles }

        let allowedTags = Array(Set(MerchantResolver.seedProfiles.flatMap(\.tags))).sorted()
        let request = AIProviderRequest(
            systemInstruction: """
            Classify merchant names for an Indian personal-finance app.
            Return only the provided JSON schema.
            Use only these semantic tags: \(allowedTags.joined(separator: ", ")).
            Tags describe the merchant channel, not a guess about this specific purchase.
            Use an empty tags array when uncertain. Never infer anything about the user.
            """,
            messages: [
                AIProviderMessage(
                    role: .user,
                    text: unknownNames.joined(separator: "\n")
                )
            ],
            responseSchema: Self.responseSchema(allowedTags: allowedTags),
            temperature: 0,
            maxOutputTokens: 1_200
        )

        do {
            let response = try await providerClient.generate(
                request: request,
                apiKey: apiKey,
                model: model
            )
            let cleanedResponse = response.text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```JSON", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let payload = try JSONDecoder().decode(
                ClassificationPayload.self,
                from: Data(cleanedResponse.utf8)
            )

            for item in payload.classifications {
                guard let sourceName = unknownNames.first(where: {
                    MerchantResolver.normalize($0) == MerchantResolver.normalize(item.inputName)
                }) else {
                    continue
                }

                let key = MerchantResolver.normalize(item.canonicalName)
                    .replacingOccurrences(of: " ", with: "-")
                guard !key.isEmpty else {
                    continue
                }

                let validTags = item.tags.filter(allowedTags.contains)
                if let transaction = transactions.first(where: {
                    MerchantResolver.normalize($0.merchant) == MerchantResolver.normalize(sourceName)
                }),
                   let existing = MerchantResolver.shared.profile(
                       for: transaction,
                       profiles: profiles
                   ),
                   !existing.isUserOverride {
                    existing.displayName = item.canonicalName
                    if !existing.aliases.contains(sourceName) {
                        existing.aliases.append(sourceName)
                    }
                    existing.tags = validTags
                    existing.defaultCategory = item.defaultCategory.isEmpty
                        ? existing.defaultCategory
                        : item.defaultCategory
                    // A small non-zero floor records that this merchant has
                    // already been classified, even when the model is unsure.
                    existing.confidence = min(max(item.confidence, 0.01), 1)
                    existing.updatedAt = Date()
                    continue
                }

                guard !profiles.contains(where: { $0.canonicalKey == key }) else {
                    continue
                }
                let profile = MerchantProfile(
                    canonicalKey: key,
                    displayName: item.canonicalName,
                    aliases: [sourceName],
                    tags: validTags,
                    defaultCategory: item.defaultCategory.isEmpty ? nil : item.defaultCategory,
                    confidence: min(max(item.confidence, 0.01), 1)
                )
                modelContext.insert(profile)
                profiles.append(profile)
            }

            // A successful classification request is attempted only once per
            // merchant, even when the model omits it or returns no tags.
            for sourceName in unknownNames {
                guard let transaction = transactions.first(where: {
                    MerchantResolver.normalize($0.merchant) == MerchantResolver.normalize(sourceName)
                }),
                let profile = MerchantResolver.shared.profile(
                    for: transaction,
                    profiles: profiles
                ),
                !profile.isUserOverride,
                profile.confidence == 0 else {
                    continue
                }
                profile.confidence = 0.01
                profile.updatedAt = Date()
            }

            for transaction in transactions where transaction.canonicalMerchantKey == nil {
                transaction.canonicalMerchantKey = MerchantResolver.shared.resolveKey(
                    for: transaction.merchant,
                    profiles: profiles
                )
            }
            try? modelContext.save()
        } catch {
            // Classification enriches retrieval but must not prevent an answer.
        }

        return profiles
    }

    private func isPlausibleCandidate(
        category: String,
        requestedTags: [String]
    ) -> Bool {
        guard !requestedTags.isEmpty else { return true }
        let allowedCategories: [String: Set<String>] = [
            "foodDelivery": ["Food & Dining"],
            "quickCommerce": ["Shopping", "Food & Dining"],
            "grocery": ["Shopping", "Food & Dining"],
            "eCommerce": ["Shopping"],
            "rideHailing": ["Transportation"],
            "subscription": ["Entertainment", "Bills & Utilities"],
            "streaming": ["Entertainment"],
            "travelBooking": ["Travel", "Transportation"],
            "pharmacy": ["Healthcare"]
        ]
        let candidates = requestedTags.reduce(into: Set<String>()) { result, tag in
            result.formUnion(allowedCategories[tag] ?? [])
        }
        return candidates.isEmpty || candidates.contains(category)
    }

    private static func responseSchema(allowedTags: [String]) -> AIJSONSchema {
        .object(
            properties: [
                "classifications": .array(
                    of: .object(
                        properties: [
                            "inputName": .string(),
                            "canonicalName": .string(),
                            "tags": .array(of: .string(values: allowedTags)),
                            "defaultCategory": .string(
                                values: ["", "Food & Dining", "Shopping", "Transportation", "Entertainment", "Bills & Utilities", "Healthcare", "Education", "Personal Care", "Travel", "Other"]
                            ),
                            "confidence": .number()
                        ],
                        required: [
                            "inputName", "canonicalName", "tags",
                            "defaultCategory", "confidence"
                        ]
                    )
                )
            ],
            required: ["classifications"]
        )
    }
}

private struct ClassificationPayload: Decodable {
    let classifications: [MerchantClassification]
}

private struct MerchantClassification: Decodable {
    let inputName: String
    let canonicalName: String
    let tags: [String]
    let defaultCategory: String
    let confidence: Double
}
