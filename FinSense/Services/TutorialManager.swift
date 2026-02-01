import SwiftUI
import Combine

/// Tutorial step definitions
enum TutorialStep: Int, CaseIterable, Hashable {
    case welcome = 0
    case editBalance
    case expenseOverview
    case spendingTrends // New step
    case addTransaction
    case settingsSetup
    case aiChat
    case budgeting
    case complete
    
    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .editBalance: return "Set Balance"
        case .expenseOverview: return "Track Expenses"
        case .spendingTrends: return "Spending Trends"
        case .addTransaction: return "Add Transaction"
        case .settingsSetup: return "Setup"
        case .aiChat: return "AI Insight"
        case .budgeting: return "Smart Budgets"
        case .complete: return "For You!"
        }
    }
    
    var instruction: String {
        switch self {
        case .welcome: return ""
        case .editBalance: return "Tap here to set your current account balance."
        case .expenseOverview: return "This card shows your monthly spending breakdown."
        case .spendingTrends: return "View your spending trends and overall expenses here."
        case .addTransaction: return "Tap + to log your first expense (or use Smart Paste!)."
        case .settingsSetup: return "Set your income and API key here."
        case .aiChat: return "Ask the AI for personalized financial advice."
        case .budgeting: return "Generate smart budgets based on your spending."
        case .complete: return "You're all set! Enjoy Finlytics."
        }
    }
    
    // Which tab needs to be active for this step
    var targetTab: Int? {
        switch self {
        case .welcome, .editBalance, .expenseOverview, .spendingTrends: return 0 // Dashboard
        case .addTransaction: return 1 // Transactions
        case .settingsSetup: return 4 // Settings
        case .aiChat: return 2 // Chat
        case .budgeting: return 3 // Budget
        case .complete: return nil // Stay on current tab (Budget)
        }
    }
}

@MainActor
class TutorialManager: ObservableObject {
    static let shared = TutorialManager()
    
    @Published var currentStep: TutorialStep = .welcome
    @Published var isActive: Bool = false
    @Published var showWelcome: Bool = false
    @Published var selectedTab: Int = 0
    
    // Dynamic Frame Tracking
    @Published var spotlightRects: [TutorialStep: CGRect] = [:]
    
    private let completedKey = "hasCompletedTutorial"
    
    var hasCompletedTutorial: Bool {
        get { UserDefaults.standard.bool(forKey: completedKey) }
        set { UserDefaults.standard.set(newValue, forKey: completedKey) }
    }
    
    private init() {
        if !hasCompletedTutorial {
            showWelcome = true
        }
    }
    
    func startTutorial() {
        showWelcome = true
        currentStep = .welcome
        isActive = false // Active starts after welcome
    }
    
    // Called when "Get Started" is clicked
    func startInteractive() {
        showWelcome = false
        isActive = true
        currentStep = .editBalance
        selectedTab = 0
    }
    
    func advance() {
        moveToNextStep()
    }
    
    // Explicitly complete a step (used for actions like Save Balance)
    func completeStep(_ step: TutorialStep) {
        if isActive && currentStep == step {
            advance()
        }
    }
    
    private func moveToNextStep() {
        let allSteps = TutorialStep.allCases
        if let currentIndex = allSteps.firstIndex(of: currentStep),
           currentIndex < allSteps.count - 1 {
            withAnimation {
                currentStep = allSteps[currentIndex + 1]
            }
            
            // Auto-Switch Tab
            if let tab = currentStep.targetTab {
                selectedTab = tab
            }
            
            if currentStep == .complete {
                completeTutorial()
            }
        }
    }
    
    func skipTutorial() {
        completeTutorial()
    }
    
    private func completeTutorial() {
        hasCompletedTutorial = true
        isActive = false
        showWelcome = false
        currentStep = .complete
    }
}
