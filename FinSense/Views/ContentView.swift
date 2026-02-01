import SwiftUI
import SwiftData

struct ContentView: View {
    @AppStorage("appTheme") private var appTheme: String = "System"
    @StateObject private var tutorialManager = TutorialManager.shared
    @State private var showingAddSheet = false
    
    var body: some View {
        ZStack {
            TabView(selection: $tutorialManager.selectedTab) {
                DashboardView()
                    .tag(0)
                    .tabItem {
                        Label("Dashboard", systemImage: "chart.bar.fill")
                    }
                
                TransactionsView()
                    .tag(1)
                    .tabItem {
                        Label("Transactions", systemImage: "list.bullet.rectangle")
                    }
                
                AIInsightsView()
                    .tag(2)
                    .tabItem {
                        Label("AI Chat", systemImage: "sparkles")
                    }
                
                SmartBudgetView()
                    .tag(3)
                    .tabItem {
                        Label("Budget", systemImage: "chart.pie.fill")
                    }
                
                SettingsView()
                    .tag(4)
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
            }
            .tint(Color.indigo)
            .preferredColorScheme(theme)
            .sheet(isPresented: $showingAddSheet) {
                AddTransactionView()
            }
            .environmentObject(tutorialManager)
            
            // Tutorial overlay
            if tutorialManager.showWelcome {
                WelcomeView {
                    withAnimation {
                        tutorialManager.startInteractive()
                    }
                }
                .transition(.opacity)
                .zIndex(2)
            } else if tutorialManager.isActive && tutorialManager.currentStep != .complete {
                TutorialOverlay(tutorialManager: tutorialManager)
                    .zIndex(1)
            }
        }
        .onPreferenceChange(TutorialTargetKey.self) { rects in
            tutorialManager.spotlightRects = rects
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
