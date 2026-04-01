import SwiftUI
import Combine

/// Tutorial step definitions
enum TutorialStep: Int, CaseIterable, Hashable {
    case editBalance = 0
    case projects
    case addTransaction
    case budgeting
    case aiChat
    case complete
    
    var title: String {
        switch self {
        case .editBalance: return "Set Balance"
        case .addTransaction: return "Quick Add"
        case .projects: return "Projects & Vaults"
        case .budgeting: return "Smart Budgets"
        case .aiChat: return "Ask Finlytics Anything"
        case .complete: return "Finish!"
        }
    }
    
    var instruction: String {
        switch self {
        case .editBalance: return "Tap the balance card to set your current savings. Everything is calculated relative to this."
        case .addTransaction: return "Log expenses manually or use 'Smart Paste' with natural language (e.g., 'spent 50 on coffee')."
        case .projects: return "Organize specific events (trips, weddings) into Projects. Swipe left to 'Hide' projects into the secure Vault."
        case .budgeting: return "Set monthly category limits. I'll track your real-time spending versus these budgets."
        case .aiChat: return "Talk to me here for spending analysis and strategy. I don't give app help here to keep your data focus sharp."
        case .complete: return "You're all set! For step-by-step guides on every feature, use 'App Help' in Settings anytime."
        }
    }
    
    // Which tab needs to be active for this step
    var targetTab: Int? {
        switch self {
        case .editBalance, .projects: return 0 // Dashboard
        case .addTransaction: return 1 // Transactions
        case .budgeting: return 3 // Budget
        case .aiChat: return 2 // Chat
        case .complete: return nil
        }
    }
}

@MainActor
class TutorialManager: ObservableObject {
    static let shared = TutorialManager()
    
    @Published var currentStep: TutorialStep = .editBalance
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
        showWelcome = false // Never show welcome on manual replay
        isActive = true
        currentStep = .editBalance
        selectedTab = 0
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
            // 1. Sync the current step with animation
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                currentStep = allSteps[currentIndex + 1]
            }
            
            // 2. Sync the selected tab directly
            if let tab = currentStep.targetTab {
                DispatchQueue.main.async {
                    self.selectedTab = tab
                }
                print("DEBUG: Tutorial advancing to \(currentStep) - switching to tab \(tab)")
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
