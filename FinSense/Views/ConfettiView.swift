import SwiftUI

/// Confetti/Celebration particle effect view
struct ConfettiView: View {
    @State private var particles: [ConfettiParticle] = []
    @State private var timer: Timer?
    
    let colors: [Color] = [.red, .blue, .green, .yellow, .orange, .pink, .purple, .mint, .indigo]
    
    struct ConfettiParticle: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        var rotation: Double
        var scale: CGFloat
        var color: Color
        var shape: Int // 0 = circle, 1 = rectangle, 2 = star
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(particles) { particle in
                    confettiShape(for: particle)
                        .fill(particle.color)
                        .frame(width: 10 * particle.scale, height: 10 * particle.scale)
                        .rotationEffect(.degrees(particle.rotation))
                        .position(x: particle.x, y: particle.y)
                }
            }
            .onAppear {
                startConfetti(in: geometry.size)
            }
            .onDisappear {
                timer?.invalidate()
            }
        }
        .allowsHitTesting(false)
    }
    
    private func confettiShape(for particle: ConfettiParticle) -> AnyShape {
        switch particle.shape {
        case 0: return AnyShape(Circle())
        case 1: return AnyShape(Rectangle())
        default: return AnyShape(Circle())
        }
    }
    
    private func startConfetti(in size: CGSize) {
        // Initial burst
        for _ in 0..<50 {
            addParticle(in: size, fromTop: true)
        }
        
        // Continuous light confetti
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if particles.count < 100 {
                addParticle(in: size, fromTop: true)
            }
            updateParticles(in: size)
        }
    }
    
    private func addParticle(in size: CGSize, fromTop: Bool) {
        let particle = ConfettiParticle(
            x: CGFloat.random(in: 0...size.width),
            y: fromTop ? -20 : CGFloat.random(in: 0...size.height * 0.3),
            rotation: Double.random(in: 0...360),
            scale: CGFloat.random(in: 0.5...1.5),
            color: colors.randomElement() ?? .blue,
            shape: Int.random(in: 0...1)
        )
        particles.append(particle)
    }
    
    private func updateParticles(in size: CGSize) {
        particles = particles.compactMap { particle in
            var p = particle
            p.y += CGFloat.random(in: 3...8)
            p.x += CGFloat.random(in: -2...2)
            p.rotation += Double.random(in: -10...10)
            
            // Remove if off screen
            if p.y > size.height + 20 {
                return nil
            }
            return p
        }
    }
}

/// Party popper burst effect
struct PartyPopperView: View {
    @State private var show = false
    
    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                Circle()
                    .fill([Color.red, .yellow, .blue, .green, .orange, .pink, .purple, .mint][i])
                    .frame(width: 12, height: 12)
                    .offset(x: show ? CGFloat.random(in: -80...80) : 0,
                            y: show ? CGFloat.random(in: -80...80) : 0)
                    .opacity(show ? 0 : 1)
                    .scaleEffect(show ? 2 : 0.5)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                show = true
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black.opacity(0.8)
        ConfettiView()
    }
}
