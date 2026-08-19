import XCTest
import SwiftData
@testable import FinSense

@MainActor
final class MerchantClassificationTests: XCTestCase {
    func testHiddenMerchantNameIsNeverSentForClassification() async throws {
        let schema = Schema(versionedSchema: FinSenseSchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: FinSenseMigrationPlan.self,
            configurations: [configuration]
        )
        let profile = MerchantProfile(
            canonicalKey: "private-merchant",
            displayName: "Private Merchant",
            aliases: ["Private Merchant"],
            tags: [],
            defaultCategory: "Food & Dining",
            confidence: 0
        )
        let transaction = Transaction(
            amount: 500,
            merchant: "Private Merchant",
            type: .expense,
            category: "Food & Dining",
            isHidden: true,
            canonicalMerchantKey: profile.canonicalKey
        )
        let client = ClassificationSpyClient()

        _ = await MerchantClassificationService.shared.classifyUnknownMerchantsIfNeeded(
            transactions: [transaction],
            existingProfiles: [profile],
            requestedTags: ["foodDelivery"],
            apiKey: "test-key",
            model: "test-model",
            providerClient: client,
            modelContext: container.mainContext
        )

        XCTAssertEqual(client.generateCallCount, 0)
    }
}

@MainActor
private final class ClassificationSpyClient: AIProviderClient {
    private(set) var generateCallCount = 0

    func generate(
        request: AIProviderRequest,
        apiKey: String,
        model: String
    ) async throws -> AIProviderResponse {
        generateCallCount += 1
        return AIProviderResponse(
            text: #"{"classifications":[]}"#,
            promptTokenCount: nil,
            responseTokenCount: nil
        )
    }

    func stream(
        request: AIProviderRequest,
        apiKey: String,
        model: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
