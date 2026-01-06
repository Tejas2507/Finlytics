import SwiftUI

struct RootView: View {
    @State private var isActive = false
    
    var body: some View {
        ZStack {
            if isActive {
                ContentView()
                    .transition(.opacity)
            } else {
                SplashView(isActive: $isActive)
            }
        }
    }
}
