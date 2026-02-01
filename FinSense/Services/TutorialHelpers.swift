import SwiftUI

// PreferenceKey for Frame Tracking
struct TutorialTargetKey: PreferenceKey {
    static var defaultValue: [TutorialStep: CGRect] = [:]
    static func reduce(value: inout [TutorialStep: CGRect], nextValue: () -> [TutorialStep: CGRect]) {
        let next = nextValue()
        for (step, rect) in next {
            if let existing = value[step] {
                value[step] = existing.union(rect)
            } else {
                value[step] = rect
            }
        }
    }
}

// Modifier to report frame
struct TutorialTargetModifier: ViewModifier {
    let step: TutorialStep
    
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(key: TutorialTargetKey.self, value: [step: geo.frame(in: .global)])
                }
            )
    }
}

extension View {
    func tutorialTarget(_ step: TutorialStep) -> some View {
        modifier(TutorialTargetModifier(step: step))
    }
}
