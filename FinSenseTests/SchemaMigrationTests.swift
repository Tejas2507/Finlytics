import XCTest
import SwiftData
@testable import FinSense

@MainActor
final class SchemaMigrationTests: XCTestCase {
    func testV1StoreMigratesTransactionsBudgetsAndProjectsToV2() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "FinSenseMigration-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "FinSense.store")

        do {
            // Mirrors the shipped app, which created an unversioned Schema
            // before this migration plan was introduced.
            let schema = Schema([
                FinSenseSchemaV1.Transaction.self,
                FinSenseSchemaV1.Budget.self,
                FinSenseSchemaV1.Project.self
            ])
            let configuration = ModelConfiguration(schema: schema, url: storeURL)
            let container = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
            let context = container.mainContext
            context.insert(
                FinSenseSchemaV1.Transaction(
                    amount: 425,
                    merchant: "Swiggy",
                    type: .expense,
                    category: "Food & Dining"
                )
            )
            context.insert(
                FinSenseSchemaV1.Budget(
                    category: "Food & Dining",
                    monthlyLimit: 5_000
                )
            )
            context.insert(
                FinSenseSchemaV1.Project(
                    name: "Goa",
                    targetBudget: 20_000
                )
            )
            try context.save()
        }

        let latestSchema = Schema(versionedSchema: FinSenseSchemaV2.self)
        let latestConfiguration = ModelConfiguration(schema: latestSchema, url: storeURL)
        let migratedContainer = try ModelContainer(
            for: latestSchema,
            migrationPlan: FinSenseMigrationPlan.self,
            configurations: [latestConfiguration]
        )
        let context = migratedContainer.mainContext

        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let budgets = try context.fetch(FetchDescriptor<Budget>())
        let projects = try context.fetch(FetchDescriptor<Project>())

        XCTAssertEqual(transactions.count, 1)
        XCTAssertEqual(transactions.first?.merchant, "Swiggy")
        XCTAssertNil(transactions.first?.canonicalMerchantKey)
        XCTAssertEqual(budgets.first?.monthlyLimit, 5_000)
        XCTAssertEqual(projects.first?.name, "Goa")
    }
}
