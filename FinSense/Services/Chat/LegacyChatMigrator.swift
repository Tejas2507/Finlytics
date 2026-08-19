import Foundation
import SwiftData

@MainActor
enum LegacyChatMigrator {
    private static let migrationKey = "didMigratePersistentChatV2"

    static func migrateIfNeeded(modelContext: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let buffer = UserDefaults.standard.stringArray(forKey: "chatHistoryBuffer") ?? []
        let parsedMessages: [(ChatRole, String)] = buffer.map { entry in
            if entry.hasPrefix("User: ") {
                return (.user, String(entry.dropFirst(6)))
            }
            if entry.hasPrefix("AI: ") {
                return (.assistant, String(entry.dropFirst(4)))
            }
            return (.assistant, entry)
        }

        if !parsedMessages.isEmpty {
            let thread = ChatThread(
                title: "Previous conversation",
                mode: .financial
            )
            modelContext.insert(thread)

            for (index, parsed) in parsedMessages.enumerated() {
                let timestamp = Date().addingTimeInterval(Double(index - parsedMessages.count))
                let message = ChatMessage(
                    role: parsed.0,
                    content: parsed.1,
                    createdAt: timestamp
                )
                modelContext.insert(message)
                thread.messages.append(message)
            }
            thread.touch()
            do {
                try modelContext.save()
            } catch {
                return
            }
        }

        UserDefaults.standard.removeObject(forKey: "chatHistoryBuffer")
        UserDefaults.standard.removeObject(forKey: "chatInteractionCount")
        UserDefaults.standard.set(true, forKey: migrationKey)
    }
}
