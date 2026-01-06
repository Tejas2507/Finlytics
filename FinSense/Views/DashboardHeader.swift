import SwiftUI
import SwiftData

struct DashboardHeader: View {
    let balance: Double
    let spent: Double
    let monthlyIncome: Double
    let insight: Insight?
    
    var potentialSavings: Double {
        monthlyIncome - spent
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            // Background Banner
            Image("DashboardBanner")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: 340)
                .clipped()
                .overlay(
                    LinearGradient(colors: [.black.opacity(0.4), .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                )
                .edgesIgnoringSafeArea(.top)
            
            VStack(alignment: .leading, spacing: 16) {
                // Title
                Text("Finlytics")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    .padding(.top, 10)
                
                // Insight Section (Top, beneath title)
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundStyle(.yellow)
                    
                    if let insight = insight {
                        Text(insight.message)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .lineLimit(4)
                    } else {
                        Text("Record transactions to unlock AI-powered insights! ✨")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(2)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial)
                .cornerRadius(14)
                
                // 2x2 Grid of Stat Cards
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatCard(title: "Net Balance", value: balance, icon: "building.columns.fill", color: .cyan)
                    StatCard(title: "Spent", value: -spent, icon: "creditcard.fill", color: .red, isNegative: true)
                    StatCard(title: "Inflow", value: monthlyIncome, icon: "arrow.down.circle.fill", color: .green)
                    StatCard(title: "Saved", value: potentialSavings, icon: "leaf.fill", color: .teal)
                }
            }
            .padding(.horizontal, 20)
        }
        .cornerRadius(24)
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
    }
}

struct StatCard: View {
    let title: String
    let value: Double
    let icon: String
    let color: Color
    var isNegative: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white.opacity(0.7))
            }
            
            Text(value, format: .currency(code: "INR"))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }
}
