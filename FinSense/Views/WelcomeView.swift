import SwiftUI

struct WelcomeView: View {
    let action: () -> Void
    
    var body: some View {
        ZStack {
            // Background Gradient
            LinearGradient(
                colors: [Color.teal, Color.cyan, Color.indigo],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Spacer()
                
                // Hero Icon / App Logo
                Image("Logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .cornerRadius(24)
                    .shadow(radius: 10)
                
                // Typography
                VStack(spacing: 12) {
                    Text("Welcome to Finlytics")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Text("Your personal finance companion for tracking, saving, and growing.")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal)
                }
                
                // Features Grid
                VStack(alignment: .leading, spacing: 20) {
                    FeatureRow(icon: "checkmark.circle.fill", title: "Smart Tracking", subtitle: "Auto-categorized expenses & income")
                    FeatureRow(icon: "wand.and.stars", title: "AI Insights", subtitle: "Personalized tips based on your data")
                    FeatureRow(icon: "lock.fill", title: "Local & Secure", subtitle: "Your data stays on your device")
                }
                .padding(30)
                .background(.ultraThinMaterial)
                .cornerRadius(24)
                .padding(.horizontal)
                
                Spacer()
                
                // Get Started Button
                Button(action: action) {
                    HStack {
                        Text("Get Started")
                            .font(.title3)
                            .fontWeight(.bold)
                        Image(systemName: "arrow.right")
                    }
                    .foregroundColor(.indigo)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 50)
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true) // Allow wrapping
            }
        }
    }
}
