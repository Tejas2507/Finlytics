import SwiftUI
import SwiftData

struct DashboardHeader: View {
    let balance: Double
    let spent: Double
    let monthlyIncome: Double
    let insight: Insight?
    @Binding var showThisMonth: Bool
    let hasTransactions: Bool

    @Binding var showBalanceEdit: Bool
    
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
                .frame(height: 390)
                .clipped()
                .overlay(
                    LinearGradient(colors: [.black.opacity(0.3), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                )
                .edgesIgnoringSafeArea(.top)
            
            VStack(alignment: .leading, spacing: 14) {
                // Enhanced Title with gradient
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Finlytics")
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(colors: [.white, .cyan.opacity(0.9)], startPoint: .leading, endPoint: .trailing)
                            )
                            .shadow(color: .cyan.opacity(0.5), radius: 8, x: 0, y: 2)
                        
                        Text("Your money, visualized")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    Spacer()
                }
                .padding(.top, 8)
                
                // Insight Section
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundStyle(.yellow)
    
                    if let insight = insight {
                        Text(insight.message)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .lineLimit(3)
                    } else if hasTransactions {
                         Text("Analyzing your financial health...")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(2)
                    } else {
                        Text("Record transactions to unlock AI-powered insights!")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(2)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                
                // 2x2 Grid of Stat Cards
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    // Balance card is tappable
                    StatCard(title: "Balance", value: balance, icon: "building.columns.fill", color: .cyan)
                        .tutorialTarget(.editBalance)
                        .onTapGesture { showBalanceEdit = true }
                        .overlay(
                            HStack {
                                Spacer()
                                VStack {
                                    Image(systemName: "pencil.circle.fill")
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.6))
                                        .padding(6)
                                    Spacer()
                                }
                            }
                        )
                    StatCard(title: "Spent", value: -spent, icon: "creditcard.fill", color: .red, isNegative: true)
                        .tutorialTarget(.expenseOverview)
                    StatCard(title: "Inflow", value: monthlyIncome, icon: "arrow.down.circle.fill", color: .green)
                    StatCard(title: "Saved", value: max(0, potentialSavings), icon: "leaf.fill", color: .teal)
                }
                
                // This Month / Wrapped Button
                Button {
                    showThisMonth = true
                } label: {
                    HStack {
                        Image(systemName: isWrappedTime ? "gift.fill" : "calendar")
                        Text(isWrappedTime ? "\(currentMonthName) Wrapped 🎉" : "More on your Month")
                            .fontWeight(.medium)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(isWrappedTime ? Color.purple.opacity(0.5) : Color.white.opacity(0.15))
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal, 16)
        }
        .cornerRadius(24)
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
    }
    
    // Check if last 2 days of month
    var isWrappedTime: Bool {
        let calendar = Calendar.current
        let now = Date()
        let dayOfMonth = calendar.component(.day, from: now)
        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        return dayOfMonth >= daysInMonth - 1
    }
    
    var currentMonthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter.string(from: Date())
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
