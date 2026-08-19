import Foundation
import SwiftData

@MainActor
enum AppDataBootstrapper {
    private static let retiredPersonaKey = "didRetireInferredPersonaV2"

    static func run(modelContext: ModelContext) {
        LegacyChatMigrator.migrateIfNeeded(modelContext: modelContext)
        recoverInterruptedMessages(modelContext: modelContext)

        // Idempotent so newly shipped seed aliases are picked up on upgrade.
        try? MerchantResolver.shared.seedAndBackfillIfNeeded(modelContext: modelContext)

        if !UserDefaults.standard.bool(forKey: retiredPersonaKey) {
            UserDefaults.standard.removeObject(forKey: "userAIPersona")
            UserDefaults.standard.removeObject(forKey: "recentChatSignals")
            UserDefaults.standard.removeObject(forKey: "personaHistory")
            UserDefaults.standard.removeObject(forKey: "lastPersonaUpdate")
            UserDefaults.standard.removeObject(forKey: "lastChatSummaryDate")
            UserDefaults.standard.set(true, forKey: retiredPersonaKey)
        }
    }

    private static func recoverInterruptedMessages(modelContext: ModelContext) {
        guard let messages = try? modelContext.fetch(FetchDescriptor<ChatMessage>()) else {
            return
        }
        var changed = false
        for message in messages where message.status == .pending || message.status == .streaming {
            message.status = .failed
            message.errorCode = "interrupted"
            message.errorMessage = "The app closed before this response finished. Tap Retry."
            changed = true
        }
        if changed {
            try? modelContext.save()
        }
    }
}
