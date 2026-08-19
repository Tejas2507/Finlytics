import Foundation
import SwiftData

@MainActor
final class MerchantResolver {
    static let shared = MerchantResolver()

    private init() {}

    struct SeedProfile {
        let canonicalKey: String
        let displayName: String
        let aliases: [String]
        let tags: [String]
        let defaultCategory: String?
    }

    static let seedProfiles: [SeedProfile] = [
        SeedProfile(
            canonicalKey: "swiggy-instamart",
            displayName: "Swiggy Instamart",
            aliases: ["swiggy instamart", "instamart"],
            tags: ["quickCommerce", "grocery"],
            defaultCategory: "Shopping"
        ),
        SeedProfile(
            canonicalKey: "swiggy",
            displayName: "Swiggy",
            aliases: ["swiggy", "bundl technologies"],
            tags: ["foodDelivery"],
            defaultCategory: "Food & Dining"
        ),
        SeedProfile(
            canonicalKey: "zomato",
            displayName: "Zomato",
            aliases: ["zomato", "zomato media"],
            tags: ["foodDelivery"],
            defaultCategory: "Food & Dining"
        ),
        SeedProfile(
            canonicalKey: "eatsure",
            displayName: "EatSure",
            aliases: ["eatsure", "rebel foods"],
            tags: ["foodDelivery"],
            defaultCategory: "Food & Dining"
        ),
        SeedProfile(
            canonicalKey: "blinkit",
            displayName: "Blinkit",
            aliases: ["blinkit", "grofers"],
            tags: ["quickCommerce", "grocery"],
            defaultCategory: "Shopping"
        ),
        SeedProfile(
            canonicalKey: "zepto",
            displayName: "Zepto",
            aliases: ["zepto", "kirana kart"],
            tags: ["quickCommerce", "grocery"],
            defaultCategory: "Shopping"
        ),
        SeedProfile(
            canonicalKey: "bigbasket",
            displayName: "BigBasket",
            aliases: ["bigbasket", "big basket", "supermarket grocery supplies"],
            tags: ["grocery"],
            defaultCategory: "Shopping"
        ),
        SeedProfile(
            canonicalKey: "uber",
            displayName: "Uber",
            aliases: ["uber", "uber india"],
            tags: ["rideHailing"],
            defaultCategory: "Transportation"
        ),
        SeedProfile(
            canonicalKey: "ola",
            displayName: "Ola",
            aliases: ["ola", "ani technologies"],
            tags: ["rideHailing"],
            defaultCategory: "Transportation"
        ),
        SeedProfile(
            canonicalKey: "amazon",
            displayName: "Amazon",
            aliases: ["amazon", "amazon seller services"],
            tags: ["eCommerce"],
            defaultCategory: "Shopping"
        ),
        SeedProfile(
            canonicalKey: "flipkart",
            displayName: "Flipkart",
            aliases: ["flipkart", "flipkart internet"],
            tags: ["eCommerce"],
            defaultCategory: "Shopping"
        ),
        SeedProfile(
            canonicalKey: "netflix",
            displayName: "Netflix",
            aliases: ["netflix"],
            tags: ["subscription", "streaming"],
            defaultCategory: "Entertainment"
        ),
        SeedProfile(
            canonicalKey: "spotify",
            displayName: "Spotify",
            aliases: ["spotify"],
            tags: ["subscription", "streaming"],
            defaultCategory: "Entertainment"
        ),
        SeedProfile(
            canonicalKey: "makemytrip",
            displayName: "MakeMyTrip",
            aliases: ["makemytrip", "make my trip"],
            tags: ["travelBooking"],
            defaultCategory: "Travel"
        ),
        SeedProfile(
            canonicalKey: "irctc",
            displayName: "IRCTC",
            aliases: ["irctc", "indian railway catering"],
            tags: ["travelBooking"],
            defaultCategory: "Travel"
        ),
        SeedProfile(
            canonicalKey: "pharmeasy",
            displayName: "PharmEasy",
            aliases: ["pharmeasy", "pharm easy"],
            tags: ["pharmacy"],
            defaultCategory: "Healthcare"
        ),
        SeedProfile(
            canonicalKey: "tata-1mg",
            displayName: "Tata 1mg",
            aliases: ["tata 1mg", "1mg"],
            tags: ["pharmacy"],
            defaultCategory: "Healthcare"
        )
    ]

    nonisolated static func normalize(_ value: String) -> String {
        let folded = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        let scalarView = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : " "
        }
        return String(scalarView)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    func seedAndBackfillIfNeeded(modelContext: ModelContext) throws {
        let profiles = try modelContext.fetch(FetchDescriptor<MerchantProfile>())
        let existingKeys = Set(profiles.map(\.canonicalKey))
        var allProfiles = profiles

        for seed in Self.seedProfiles where !existingKeys.contains(seed.canonicalKey) {
            let profile = MerchantProfile(
                canonicalKey: seed.canonicalKey,
                displayName: seed.displayName,
                aliases: seed.aliases,
                tags: seed.tags,
                defaultCategory: seed.defaultCategory
            )
            modelContext.insert(profile)
            allProfiles.append(profile)
        }

        let transactions = try modelContext.fetch(FetchDescriptor<Transaction>())
        for transaction in transactions where transaction.canonicalMerchantKey == nil {
            if let resolved = resolveKey(for: transaction.merchant, profiles: allProfiles) {
                transaction.canonicalMerchantKey = resolved
            } else if let profile = makeLocalProfile(
                merchant: transaction.merchant,
                defaultCategory: transaction.category,
                existingProfiles: allProfiles
            ) {
                if !allProfiles.contains(where: { $0 === profile }) {
                    modelContext.insert(profile)
                    allProfiles.append(profile)
                }
                transaction.canonicalMerchantKey = profile.canonicalKey
            }
        }

        try modelContext.save()
    }

    func resolveKey(for merchant: String, profiles: [MerchantProfile]) -> String? {
        let normalizedMerchant = Self.normalize(merchant)
        guard !normalizedMerchant.isEmpty else { return nil }

        let candidates = profiles.flatMap { profile in
            ([profile.displayName] + profile.aliases).map {
                (profile: profile, normalizedAlias: Self.normalize($0))
            }
        }
        .filter { !$0.normalizedAlias.isEmpty }
        .sorted { $0.normalizedAlias.count > $1.normalizedAlias.count }

        let paddedMerchant = " \(normalizedMerchant) "
        return candidates.first {
            normalizedMerchant == $0.normalizedAlias ||
            paddedMerchant.contains(" \($0.normalizedAlias) ")
        }?.profile.canonicalKey
    }

    func resolveOrCreateKey(
        for merchant: String,
        defaultCategory: String?,
        profiles: [MerchantProfile],
        modelContext: ModelContext
    ) -> String? {
        if let resolved = resolveKey(for: merchant, profiles: profiles) {
            return resolved
        }
        let normalizedKey = Self.normalize(merchant).replacingOccurrences(of: " ", with: "-")
        if let existing = profiles.first(where: { $0.canonicalKey == normalizedKey }) {
            return existing.canonicalKey
        }
        guard let profile = makeLocalProfile(
            merchant: merchant,
            defaultCategory: defaultCategory,
            existingProfiles: profiles
        ) else {
            return nil
        }
        modelContext.insert(profile)
        return profile.canonicalKey
    }

    func profile(
        for transaction: Transaction,
        profiles: [MerchantProfile]
    ) -> MerchantProfile? {
        if let key = transaction.canonicalMerchantKey,
           let exact = profiles.first(where: { $0.canonicalKey == key }) {
            return exact
        }

        guard let resolvedKey = resolveKey(for: transaction.merchant, profiles: profiles) else {
            return nil
        }
        return profiles.first(where: { $0.canonicalKey == resolvedKey })
    }

    func seedProfile(for merchant: String) -> SeedProfile? {
        let normalizedMerchant = Self.normalize(merchant)
        let paddedMerchant = " \(normalizedMerchant) "
        return Self.seedProfiles
            .flatMap { profile in
                ([profile.displayName] + profile.aliases).map {
                    (profile: profile, alias: Self.normalize($0))
                }
            }
            .filter { !$0.alias.isEmpty }
            .sorted { $0.alias.count > $1.alias.count }
            .first {
                normalizedMerchant == $0.alias ||
                paddedMerchant.contains(" \($0.alias) ")
            }?
            .profile
    }

    func matchesSeedTag(
        merchant: String,
        requestedTags: [String]
    ) -> Bool {
        guard let seed = seedProfile(for: merchant) else { return false }
        return requestedTags.contains(where: seed.tags.contains)
    }

    private func makeLocalProfile(
        merchant: String,
        defaultCategory: String?,
        existingProfiles: [MerchantProfile]
    ) -> MerchantProfile? {
        let normalized = Self.normalize(merchant)
        guard !normalized.isEmpty else { return nil }
        let key = normalized.replacingOccurrences(of: " ", with: "-")
        if let existing = existingProfiles.first(where: { $0.canonicalKey == key }) {
            return existing
        }
        return MerchantProfile(
            canonicalKey: key,
            displayName: merchant.trimmingCharacters(in: .whitespacesAndNewlines),
            aliases: [merchant],
            tags: [],
            defaultCategory: defaultCategory,
            confidence: 0
        )
    }
}
