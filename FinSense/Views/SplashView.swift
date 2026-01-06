import SwiftUI
import SwiftData

struct SplashView: View {
    @Binding var isActive: Bool
    @Environment(\.modelContext) private var modelContext
    @Query private var transactions: [Transaction]
    @AppStorage("geminiApiKey") private var apiKey: String = ""
    
    @State private var opacity = 0.5
    @State private var scale = 0.8
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                if let appIcon = UIImage(named: "AppIcon") {
                    Image(uiImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 120)
                        .cornerRadius(24)
                        .shadow(color: .blue.opacity(0.5), radius: 20, x: 0, y: 0)
                } else {
                    // Fallback if AppIcon isn't easily loadable via UIImage(named:) in some contexts
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 80))
                        .foregroundStyle(LinearGradient(colors: [.blue, .mint], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                
                Text("Finlytics")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.white, .gray], startPoint: .top, endPoint: .bottom))
            }
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeIn(duration: 1.2)) {
                    self.scale = 1.0
                    self.opacity = 1.0
                }
            }
        }
        .task {
            // 1. Kick off Insight Generation
            // We use a Task group or async let to run both the timer and the fetch concurrently
            await prepareApp()
        }
    }
    
    private func prepareApp() async {
        let startTime = Date()
        
        // Start fetching insight
        // We ignore the result here because the DashbaordView will pick up the persisted Insight from SwiftData
        // or re-fetch (which will hit the cache/SwiftData since we just generated it).
        // Actually, InsightEngine saves to context.
        if !transactions.isEmpty && !apiKey.isEmpty {
            _ = await InsightEngine.shared.fetchTodaysInsight(context: modelContext, transactions: transactions, apiKey: apiKey)
        }
        
        // Ensure minimum 2 seconds display
        let elapsed = Date().timeIntervalSince(startTime)
        let remaining = 2.0 - elapsed
        if remaining > 0 {
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
        }
        
        // Transition
        withAnimation {
            self.isActive = true
        }
    }
}
