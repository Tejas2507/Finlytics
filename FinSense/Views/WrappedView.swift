import SwiftUI
import Charts

/// Monthly Wrapped - Spotify-style animated slideshow for previous month stats
struct WrappedView: View {
    @Environment(\.dismiss) private var dismiss
    let transactions: [Transaction]
    let monthlySalary: Double
    let targetMonth: Date  // The month we're wrapping (previous month)
    
    @State private var currentSlide = 0
    @State private var showConfetti = false
    @State private var slideData: [WrappedSlide] = []
    @State private var isLoading = true
    @State private var animateNumber = false
    
    // Slide structure
    struct WrappedSlide: Identifiable {
        let id = UUID()
        let emoji: String
        let title: String
        let value: String
        let subtitle: String
        let gradient: [Color]
    }
    
    // Previous month's data
    var monthTransactions: [Transaction] {
        MonthlyStats.shared.getTransactions(for: targetMonth, from: transactions)
    }
    
    var monthSpending: [Transaction] {
        monthTransactions.filter { MonthlyStats.isSpending($0) }
    }
    
    var monthInvestments: [Transaction] {
        monthTransactions.filter { $0.type == .expense && $0.category.lowercased().contains("invest") }
    }
    
    var totalSpent: Double {
        monthSpending.reduce(0) { $0 + $1.amount }
    }
    
    var totalInvested: Double {
        monthInvestments.reduce(0) { $0 + $1.amount }
    }
    
    var monthName: String {
        MonthlyStats.shared.formatMonth(targetMonth)
    }
    
    var body: some View {
        ZStack {
            // Background gradient based on current slide
            if !slideData.isEmpty && currentSlide < slideData.count {
                LinearGradient(
                    colors: slideData[currentSlide].gradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: currentSlide)
            } else {
                Color.black.ignoresSafeArea()
            }
            
            // Confetti on celebration slides
            if showConfetti {
                ConfettiView()
            }
            
            VStack {
                // Skip button
                HStack {
                    Spacer()
                    Button(action: skipWrapped) {
                        Text("Skip")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial.opacity(0.3))
                            .cornerRadius(20)
                    }
                }
                .padding()
                
                Spacer()
                
                // Slide content
                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                } else if !slideData.isEmpty {
                    slideContent
                }
                
                Spacer()
                
                // Progress dots
                if !slideData.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(0..<slideData.count, id: \.self) { i in
                            Circle()
                                .fill(i == currentSlide ? Color.white : Color.white.opacity(0.4))
                                .frame(width: 8, height: 8)
                                .scaleEffect(i == currentSlide ? 1.2 : 1)
                                .animation(.spring(), value: currentSlide)
                        }
                    }
                    .padding(.bottom, 30)
                }
                
                // Continue button
                Button(action: nextSlide) {
                    Text(currentSlide >= slideData.count - 1 ? "Finish" : "Continue")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(16)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            generateSlides()
        }
    }
    
    @ViewBuilder
    var slideContent: some View {
        let slide = slideData[currentSlide]
        
        VStack(spacing: 20) {
            // Emoji with bounce animation
            Text(slide.emoji)
                .font(.system(size: 80))
                .scaleEffect(animateNumber ? 1.0 : 0.5)
                .animation(.spring(response: 0.5, dampingFraction: 0.6), value: animateNumber)
            
            // Title
            Text(slide.title)
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
            
            // Main value with count-up animation
            Text(slide.value)
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(.white)
                .scaleEffect(animateNumber ? 1.0 : 0.8)
                .opacity(animateNumber ? 1.0 : 0)
                .animation(.easeOut(duration: 0.5).delay(0.2), value: animateNumber)
            
            // Subtitle
            Text(slide.subtitle)
                .font(.body)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.horizontal, 24)
        .onChange(of: currentSlide) { _, _ in
            animateNumber = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation {
                    animateNumber = true
                }
            }
            
            // Show confetti on first and last slides
            showConfetti = currentSlide == 0 || currentSlide == slideData.count - 1
        }
    }
    
    private func generateSlides() {
        let calendar = Calendar.current
        let categoryBreakdown = MonthlyStats.shared.getCategoryBreakdown(for: targetMonth, from: transactions)
        let txCount = monthSpending.count
        
        // Unique data extractions
        let biggestPurchase = monthSpending.max(by: { $0.amount < $1.amount })
        let smallestPurchase = monthSpending.filter { $0.amount > 0 }.min(by: { $0.amount < $1.amount })
        
        // Busiest spending day
        let byDay = Dictionary(grouping: monthSpending) { tx in
            calendar.startOfDay(for: tx.date)
        }
        let busiestDay = byDay.max(by: { $0.value.count < $1.value.count })
        let busiestDayFormatter = DateFormatter()
        busiestDayFormatter.dateFormat = "EEEE, MMM d"
        
        // Least active category (with at least 1 transaction)
        let leastCategory = categoryBreakdown.last
        
        // Days in month for daily average
        let daysInMonth = calendar.range(of: .day, in: .month, for: targetMonth)?.count ?? 30
        let dailyAverage = totalSpent / Double(daysInMonth)
        
        // Build slides
        var slides: [WrappedSlide] = []
        
        // Slide 1: Intro
        slides.append(WrappedSlide(
            emoji: "🎊",
            title: "Your \(monthName)",
            value: "Wrapped",
            subtitle: "Let's uncover your spending story!",
            gradient: [.purple, .indigo]
        ))
        
        // Slide 2: Total Spent + Daily Avg
        slides.append(WrappedSlide(
            emoji: "💰",
            title: "You spent a total of",
            value: "₹\(Int(totalSpent).formatted())",
            subtitle: "That's ₹\(Int(dailyAverage).formatted()) per day across \(txCount) transactions",
            gradient: [.blue, .cyan]
        ))
        
        // Slide 3: Biggest Single Purchase (UNIQUE)
        if let biggest = biggestPurchase {
            slides.append(WrappedSlide(
                emoji: "💸",
                title: "Your biggest purchase was",
                value: "₹\(Int(biggest.amount).formatted())",
                subtitle: "\(biggest.merchant) • \(biggest.category)",
                gradient: [.red, .pink]
            ))
        }
        
        // Slide 4: Smallest Purchase (UNIQUE)
        if let smallest = smallestPurchase, smallest.amount != biggestPurchase?.amount {
            slides.append(WrappedSlide(
                emoji: "🪙",
                title: "Your tiniest spend was",
                value: "₹\(Int(smallest.amount).formatted())",
                subtitle: "\(smallest.merchant) • Every rupee counts!",
                gradient: [.teal, .mint]
            ))
        }
        
        // Slide 5: Busiest Day (UNIQUE)
        if let busiest = busiestDay {
            let daySpent = busiest.value.reduce(0) { $0 + $1.amount }
            slides.append(WrappedSlide(
                emoji: "🔥",
                title: "Your busiest day was",
                value: busiestDayFormatter.string(from: busiest.key),
                subtitle: "\(busiest.value.count) transactions totaling ₹\(Int(daySpent).formatted())",
                gradient: [.orange, .yellow]
            ))
        }
        
        // Slide 6: Least Active Category (UNIQUE)
        if let least = leastCategory, categoryBreakdown.count > 2 {
            slides.append(WrappedSlide(
                emoji: "📊",
                title: "You spent the least on",
                value: least.name,
                subtitle: "Just ₹\(Int(least.amount).formatted()) - room to splurge?",
                gradient: [.gray, .blue]
            ))
        }
        
        // Slide 7: Investments (if any)
        if totalInvested > 0 {
            slides.append(WrappedSlide(
                emoji: "🏦",
                title: "You invested",
                value: "₹\(Int(totalInvested).formatted())",
                subtitle: "Building your future 💪",
                gradient: [.green, .teal]
            ))
        }
        
        // Slide 8: Savings/Wrap-up
        let savingsRate = monthlySalary > 0 ? Int(((monthlySalary - totalSpent - totalInvested) / monthlySalary) * 100) : 0
        let savingsEmoji = savingsRate > 30 ? "🎉" : (savingsRate > 0 ? "💪" : "🚀")
        slides.append(WrappedSlide(
            emoji: savingsEmoji,
            title: "That's a wrap!",
            value: "\(savingsRate)% saved",
            subtitle: savingsRate > 30 ? "You're crushing it!" : "Every month is a fresh start!",
            gradient: [.pink, .purple]
        ))
        
        slideData = slides
        isLoading = false
        
        // Trigger initial animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            animateNumber = true
            showConfetti = true
        }
    }
    
    private func nextSlide() {
        if currentSlide >= slideData.count - 1 {
            dismiss()
        } else {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentSlide += 1
            }
        }
    }
    
    private func skipWrapped() {
        dismiss()
    }
}

#Preview {
    WrappedView(
        transactions: [],
        monthlySalary: 50000,
        targetMonth: Calendar.current.date(byAdding: .month, value: -1, to: Date())!
    )
}
