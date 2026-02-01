import SwiftUI

/// Creates the hole-punch effect
struct SpotlightShape: Shape {
    var targetRect: CGRect
    
    var animatableData: CGRect.AnimatableData {
        get { targetRect.animatableData }
        set { targetRect.animatableData = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Full screen
        path.addRect(rect)
        // Subtract target
        path.addRoundedRect(in: targetRect, cornerSize: CGSize(width: 12, height: 12))
        return path
    }
}

struct TutorialOverlay: View {
    @ObservedObject var tutorialManager: TutorialManager
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 1. DIMMER LAYER (Visual Only)
                // We use .allowsHitTesting(false) so the user can click THROUGH it to the app buttons
                Color.black.opacity(0.6)
                    .mask(
                        SpotlightShape(targetRect: currentRect(in: geo))
                            .fill(style: FillStyle(eoFill: true))
                    )
                    .ignoresSafeArea()
                    .allowsHitTesting(false) 
                
                // 2. INSTRUCTION BUBBLE (Visual Only)
                // Fallback: If rect is missing, show centered bubble so user isn't stuck
                let targetRect = tutorialManager.spotlightRects[tutorialManager.currentStep] ?? CGRect.zero
                instructionBubble(rect: targetRect, screenHeight: geo.size.height)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: tutorialManager.currentStep)
    }
    
    func currentRect(in geo: GeometryProxy) -> CGRect {
        // Return tracked rect or fallback off-screen for hole
        let rawRect = tutorialManager.spotlightRects[tutorialManager.currentStep] ?? CGRect.zero
        if rawRect == .zero { return .zero }
        
        // "Relaxed" padding: inflate by 12 points on all sides
        return rawRect.insetBy(dx: -12, dy: -12)
    }
    
    func instructionBubble(rect: CGRect, screenHeight: CGFloat) -> some View {
        // Determine placement: Top or Bottom based on target Y position
        // If target is missing (CGRect.zero), center the bubble
        let isLowOnScreen = rect.minY > screenHeight * 0.6
        let isZero = rect == .zero
        
        return VStack {
            // Spacer to push bubble down if target is high (and not zero)
            if !isLowOnScreen && !isZero { 
                Spacer().frame(height: rect.maxY + 20) 
            } else if isZero {
                Spacer() // Center vertically if zero
            }
            
            VStack(spacing: 12) {
                Text(tutorialManager.currentStep.instruction)
                    .font(.body)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                    .shadow(radius: 10)
                
                // "Next" button ALWAYS available so user can proceed
                Button(action: { tutorialManager.advance() }) {
                    Text("Next")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.indigo)
                        .cornerRadius(8)
                }
                
                // Skip is always available, but smaller
                Button("Skip Tutorial") {
                    tutorialManager.skipTutorial()
                }
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 40)
            .allowsHitTesting(true) // Bubble elements MUST be interactive
            
            // Spacer to push bubble up if target is low
            if isLowOnScreen && !isZero { 
                Spacer().frame(height: screenHeight - rect.minY + 20) 
            } else if isZero {
                Spacer() // Center vertically if zero
            }
        }
        .frame(maxWidth: .infinity)
    }
}
