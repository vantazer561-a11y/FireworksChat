import SwiftUI

/// Cyberpunk neon-samurai inspired theme: deep night-blue background,
/// electric cyan and magenta accents, glowing strokes on UI surfaces.
enum CyberTheme {
    // Core palette
    static let background = Color(red: 0.04, green: 0.04, blue: 0.10)        // near-black indigo
    static let surface    = Color(red: 0.08, green: 0.08, blue: 0.18)        // panel / bubble
    static let surfaceAlt = Color(red: 0.12, green: 0.10, blue: 0.22)        // elevated panel
    static let cyan       = Color(red: 0.00, green: 0.90, blue: 1.00)        // #00E5FF
    static let magenta    = Color(red: 1.00, green: 0.00, blue: 0.90)        // #FF00E5
    static let purple     = Color(red: 0.55, green: 0.20, blue: 1.00)
    static let textPrimary = Color(white: 0.95)
    static let textSecondary = Color(white: 0.65)

    // Gradients
    static let neonGradient = LinearGradient(
        colors: [cyan, purple, magenta],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let userBubbleGradient = LinearGradient(
        colors: [cyan.opacity(0.85), purple.opacity(0.85)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let assistantBubbleGradient = LinearGradient(
        colors: [surface, surfaceAlt],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.02, green: 0.02, blue: 0.08),
            Color(red: 0.06, green: 0.04, blue: 0.16),
            Color(red: 0.02, green: 0.02, blue: 0.08)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    // Fonts
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// A view modifier that adds a neon glow border around any view.
struct NeonGlow: ViewModifier {
    var color: Color = CyberTheme.cyan
    var radius: CGFloat = 8
    var lineWidth: CGFloat = 1
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(color, lineWidth: lineWidth)
                    .shadow(color: color.opacity(0.7), radius: radius)
                    .shadow(color: color.opacity(0.4), radius: radius * 2)
            )
    }
}

extension View {
    func neonGlow(color: Color = CyberTheme.cyan, radius: CGFloat = 8, lineWidth: CGFloat = 1, cornerRadius: CGFloat = 16) -> some View {
        modifier(NeonGlow(color: color, radius: radius, lineWidth: lineWidth, cornerRadius: cornerRadius))
    }
}

/// Subtle animated grid backdrop, like a synthwave horizon.
struct CyberGridBackground: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                CyberTheme.backgroundGradient.ignoresSafeArea()
                Canvas { ctx, size in
                    let spacing: CGFloat = 32
                    var path = Path()
                    var x: CGFloat = phase.truncatingRemainder(dividingBy: spacing)
                    while x < size.width {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        x += spacing
                    }
                    var y: CGFloat = phase.truncatingRemainder(dividingBy: spacing)
                    while y < size.height {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                        y += spacing
                    }
                    ctx.stroke(path, with: .color(CyberTheme.cyan.opacity(0.08)), lineWidth: 0.5)
                }
                .blendMode(.screen)
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .onAppear {
                withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) {
                    phase = 32
                }
            }
        }
        .ignoresSafeArea()
    }
}
