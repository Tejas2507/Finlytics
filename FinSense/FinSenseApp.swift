import SwiftUI
import SwiftData

@main
struct FinSenseApp: App {
    
    // Create a shared ModelContainer for YOUR models
    var sharedModelContainer: ModelContainer = {
        // List YOUR actual SwiftData models here, NOT 'Item'
        let schema = Schema([
            Transaction.self,
            Budget.self,
            Insight.self
            // Add other models if you have them
        ])
        
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        
        do {
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup("Finlytics") {
            // This should be your main view
            RootView()
        }
        .modelContainer(sharedModelContainer) // This attaches your container
    }
}
