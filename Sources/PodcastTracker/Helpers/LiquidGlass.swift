import SwiftUI

extension View {
    func liquidGlass(
        cornerRadius: CGFloat = 16,
        interactive: Bool = false,
        tint: Color? = nil,
        borderOpacity: Double = 0.15
    ) -> some View {
        let effect = interactive ? Glass.regular.tint(tint ?? .clear).interactive() : Glass.regular.tint(tint ?? .clear)
        return glassEffect(effect, in: .rect(cornerRadius: cornerRadius))
    }
}

struct InteractiveGlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 16
    var tint: Color?
    var action: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
                .liquidGlass(cornerRadius: cornerRadius, interactive: true, tint: tint)
        } else {
            content.liquidGlass(cornerRadius: cornerRadius, tint: tint)
        }
    }
}

struct LiquidGlassButton: View {
    let title: String
    let systemImage: String
    var tint: Color = .accentColor
    var isProminent = true
    let action: () -> Void

    var body: some View {
        Group {
            if isProminent {
                Button(title, systemImage: systemImage, action: action).buttonStyle(.glassProminent)
            } else {
                Button(title, systemImage: systemImage, action: action).buttonStyle(.glass)
            }
        }.tint(tint)
    }
}
