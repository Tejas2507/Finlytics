import SwiftUI
import SwiftData

struct SplashView: View {
    @Binding var isActive: Bool
    @Environment(\.modelContext) private var modelContext
    @Query private var transactions: [Transaction]
    
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
            await prepareApp()
        }
    }
    
    private func prepareApp() async {
        // Just wait for splash animation - DashboardView handles insight fetch with cooldown
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Transition
        withAnimation {
            self.isActive = true
        }
    }
}
