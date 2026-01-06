import SwiftUI
import SwiftData

struct ContentView: View {
    @AppStorage("appTheme") private var appTheme: String = "System"
    @State private var showingAddSheet = false
    
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "chart.bar.fill")
                }
            
            TransactionsView()
                .tabItem {
                    Label("Transactions", systemImage: "list.bullet.rectangle")
                }
            
            AIInsightsView()
                .tabItem {
                    Label("AI Chat", systemImage: "sparkles")
                }
            
            SmartBudgetView()
                .tabItem {
                    Label("Budget", systemImage: "chart.pie.fill")
                }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .tint(Color.indigo) // Use Indigo as requested for neutral primary
        .preferredColorScheme(theme)
        // Let's rely on standard UI patterns first: Toolbar button on Dashboard/Transactions.
        // Or actually, a central specialized tab that opens the sheet immediately? 
        // For now, let's attach the sheet to the TabView.
        .sheet(isPresented: $showingAddSheet) {
            AddTransactionView()
        }
    }
    
    private var theme: ColorScheme? {
        switch appTheme {
        case "Light": return .light
        case "Dark": return .dark
        default: return nil
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Transaction.self, inMemory: true)
}
