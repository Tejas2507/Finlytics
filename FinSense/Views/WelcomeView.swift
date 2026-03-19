import SwiftUI

struct OnboardingQuestion {
    let id: Int
    let title: String
    let subtitle: String
    let options: [String]
    let symbol: String
}

let onboardingQuestions = [
    OnboardingQuestion(
        id: 1, title: "Financial Confidence",
        subtitle: "How confident do you feel about managing and tracking your money day-to-day?",
        options: ["Clueless", "Unsure", "Getting There", "Confident", "Total Pro"],
        symbol: "brain.head.profile"
    ),
    OnboardingQuestion(
        id: 2, title: "Impulse Spending",
        subtitle: "How often do you make unplanned, in-the-moment purchases you later regret?",
        options: ["Constantly", "Often", "Sometimes", "Rarely", "Never"],
        symbol: "cart.fill.badge.questionmark"
    ),
    OnboardingQuestion(
        id: 3, title: "Savings Discipline",
        subtitle: "How strictly do you set aside money for savings every month?",
        options: ["Never Save", "Sometimes Try", "Hit or Miss", "Usually Do", "Iron Discipline"],
        symbol: "lock.shield.fill"
    ),
    OnboardingQuestion(
        id: 4, title: "Financial Anxiety",
        subtitle: "How stressed do you feel when checking your bank balance or monthly expenses?",
        options: ["Full Panic", "Very Anxious", "Nervous", "Calm", "Completely Chill"],
        symbol: "heart.text.square.fill"
    ),
    OnboardingQuestion(
        id: 5, title: "Lifestyle Creep",
        subtitle: "When you have extra money (bonus, raise), what do you usually do with it?",
        options: ["Spend It All", "Mostly Spend", "Split 50/50", "Mostly Save", "Save It All"],
        symbol: "arrow.up.right.circle.fill"
    ),
    OnboardingQuestion(
        id: 6, title: "Motivation Style",
        subtitle: "How do you prefer your AI financial advisor to talk to you?",
        options: ["Very Gentle", "Encouraging", "Direct", "Blunt", "Brutally Roast Me"],
        symbol: "megaphone.fill"
    ),
    OnboardingQuestion(
        id: 7, title: "Budget Awareness",
        subtitle: "How closely do you track where your money actually goes each month?",
        options: ["Never Track", "Occasional Peek", "Monthly Review", "Weekly Check", "Track Every Rupee"],
        symbol: "chart.bar.doc.horizontal.fill"
    )
]


struct WelcomeView: View {
    let action: () -> Void
    
    @State private var currentPage = 0
    @State private var answers: [Int: String] = [:]
    
    var body: some View {
        ZStack {
            // Background
            Color(.systemBackground).ignoresSafeArea()
            
            // Decorative background shapes
            Circle()
                .fill(Color.indigo.opacity(0.15))
                .frame(width: 300)
                .blur(radius: 60)
                .offset(x: -100, y: -200)
                
            Circle()
                .fill(Color.teal.opacity(0.15))
                .frame(width: 300)
                .blur(radius: 60)
                .offset(x: 100, y: 300)
            
            TabView(selection: $currentPage) {
                // Page 0: The Welcome Screen
                VStack(spacing: 0) {
                    Spacer()
                    
                    Image("Logo") // Ensure to use the app logo
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .indigo.opacity(0.3), radius: 20, y: 10)
                        .padding(.bottom, 40)
                    
                    Text("Meet Finlytics")
                        .font(.system(size: 42, weight: .heavy, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [.primary, .primary.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .padding(.bottom, 12)
                    
                    Text("Your AI-powered financial brain. Let's personalize your experience before we start.")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 50)
                    
                    VStack(alignment: .leading, spacing: 24) {
                        WelcomeFeatureRow(icon: "brain", title: "Smart Memory", subtitle: "AI learns your habits over time", color: .indigo)
                        WelcomeFeatureRow(icon: "bolt.fill", title: "Brutal Honesty", subtitle: "Tailored advice that actually works", color: .orange)
                        WelcomeFeatureRow(icon: "lock.shield.fill", title: "100% Private", subtitle: "Data stays securely on your device", color: .teal)
                    }
                    .padding(30)
                    .background(Color(.secondarySystemBackground).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.horizontal, 24)
                    
                    Spacer()
                    
                    Button {
                        withAnimation(.spring()) {
                            currentPage = 1
                        }
                    } label: {
                        Text("Personalize My AI")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(height: 56)
                            .frame(maxWidth: .infinity)
                            .background(
                                LinearGradient(colors: [.indigo, .blue], startPoint: .leading, endPoint: .trailing)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: .indigo.opacity(0.3), radius: 10, y: 5)
                            .padding(.horizontal, 32)
                            .padding(.bottom, 40)
                    }
                }
                .tag(0)
                
                // Pages 1-7: Questions
                ForEach(onboardingQuestions, id: \.id) { q in
                    QuestionView(
                        question: q,
                        selectedAnswer: Binding(
                            get: { answers[q.id] },
                            set: { newValue in
                                answers[q.id] = newValue
                                // Auto-advance after small delay
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    withAnimation(.spring()) {
                                        if currentPage < onboardingQuestions.count {
                                            currentPage += 1
                                        } else {
                                            finishOnboarding()
                                        }
                                    }
                                }
                            }
                        ),
                        isLast: q.id == onboardingQuestions.count,
                        onNext: {
                            if currentPage < onboardingQuestions.count {
                                withAnimation(.spring()) { currentPage += 1 }
                            } else {
                                finishOnboarding()
                            }
                        },
                        onBack: {
                            withAnimation(.spring()) { currentPage -= 1 }
                        }
                    )
                    .tag(q.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never)) // Hide the standard page dots
            .animation(.easeInOut, value: currentPage)
        }
    }
    
    private func finishOnboarding() {
        // Compile profile
        var profileLines = ["User's Initial Self-Assessment (Baseline):"]
        for q in onboardingQuestions {
            let answer = answers[q.id] ?? "Skipped"
            profileLines.append("- \(q.title): \(answer)")
        }
        let profileString = profileLines.joined(separator: "\n")
        
        // Save
        UserDefaults.standard.set(profileString, forKey: "onboardingProfile")
        print("Set onboarding profile:\n\(profileString)")
        
        // Trigger completion via the TutorialManager callback from ContentView
        action()
    }
}

struct WelcomeFeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct QuestionView: View {
    let question: OnboardingQuestion
    @Binding var selectedAnswer: String?
    let isLast: Bool
    let onNext: () -> Void
    let onBack: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            
            // Header with Back Button and Progress
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.bold))
                        .foregroundColor(.primary)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Circle())
                }
                Spacer()
                Text("Step \(question.id) of \(onboardingQuestions.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 60)
            
            Spacer().frame(height: 40)
            
            // Question Content
            VStack(alignment: .leading, spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.indigo.opacity(0.1))
                        .frame(width: 64, height: 64)
                    Image(systemName: question.symbol)
                        .font(.system(size: 28))
                        .foregroundColor(.indigo)
                }
                .padding(.bottom, 8)
                
                Text(question.title)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text(question.subtitle)
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            
            // Options List
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(question.options, id: \.self) { option in
                        Button {
                            // Haptic feedback (simple built-in generator)
                            let impactMed = UIImpactFeedbackGenerator(style: .medium)
                            impactMed.impactOccurred()
                            selectedAnswer = option
                        } label: {
                            HStack {
                                Text(option)
                                    .font(.headline)
                                    .foregroundColor(selectedAnswer == option ? .white : .primary)
                                Spacer()
                                if selectedAnswer == option {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.white)
                                        .font(.title3)
                                } else {
                                    Circle()
                                        .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 2)
                                        .frame(width: 20, height: 20)
                                }
                            }
                            .padding(.horizontal, 24)
                            .frame(height: 64)
                            .background(
                                selectedAnswer == option ? 
                                LinearGradient(colors: [.indigo, .blue], startPoint: .leading, endPoint: .trailing) : 
                                LinearGradient(colors: [Color(.secondarySystemBackground), Color(.secondarySystemBackground)], startPoint: .leading, endPoint: .trailing)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
            
            Spacer()
        }
    }
}

#Preview {
    WelcomeView(action: {})
}
