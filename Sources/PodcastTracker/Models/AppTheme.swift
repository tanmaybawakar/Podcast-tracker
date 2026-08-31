import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case ocean
    case orchid
    case forest
    case sunset
    case midnight

    static let storageKey = "appTheme"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .system: "System"
        case .ocean: "Ocean"
        case .orchid: "Orchid"
        case .forest: "Forest"
        case .sunset: "Sunset"
        case .midnight: "Midnight"
        }
    }

    var detail: String {
        switch self {
        case .system: "Follows your Mac accent and appearance"
        case .ocean: "Clear blue for focused listening"
        case .orchid: "A calm violet workspace"
        case .forest: "Grounded green for steady progress"
        case .sunset: "Warm coral energy"
        case .midnight: "Deep indigo with a dark appearance"
        }
    }

    var tint: Color {
        switch self {
        case .system: .accentColor
        case .ocean: Color(red: 0.08, green: 0.48, blue: 0.78)
        case .orchid: Color(red: 0.48, green: 0.27, blue: 0.82)
        case .forest: Color(red: 0.12, green: 0.52, blue: 0.35)
        case .sunset: Color(red: 0.88, green: 0.30, blue: 0.23)
        case .midnight: Color(red: 0.36, green: 0.43, blue: 0.96)
        }
    }

    var previewColors: [Color] {
        switch self {
        case .system: [.accentColor, .secondary.opacity(0.45)]
        case .ocean: [Color(red: 0.08, green: 0.48, blue: 0.78), Color(red: 0.19, green: 0.72, blue: 0.82)]
        case .orchid: [Color(red: 0.48, green: 0.27, blue: 0.82), Color(red: 0.78, green: 0.35, blue: 0.72)]
        case .forest: [Color(red: 0.12, green: 0.52, blue: 0.35), Color(red: 0.42, green: 0.70, blue: 0.30)]
        case .sunset: [Color(red: 0.88, green: 0.30, blue: 0.23), Color(red: 0.97, green: 0.61, blue: 0.18)]
        case .midnight: [Color(red: 0.19, green: 0.22, blue: 0.48), Color(red: 0.36, green: 0.43, blue: 0.96)]
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .ocean, .orchid, .forest, .sunset:
            .light
        case .midnight:
            .dark
        }
    }

    var backgroundColors: [Color] {
        switch self {
        case .system:
            [Color(nsColor: .windowBackgroundColor), Color(nsColor: .underPageBackgroundColor)]
        case .ocean:
            [Color(red: 0.87, green: 0.95, blue: 0.98), Color(red: 0.74, green: 0.87, blue: 0.95)]
        case .orchid:
            [Color(red: 0.96, green: 0.91, blue: 0.99), Color(red: 0.88, green: 0.81, blue: 0.96)]
        case .forest:
            [Color(red: 0.89, green: 0.96, blue: 0.90), Color(red: 0.78, green: 0.90, blue: 0.79)]
        case .sunset:
            [Color(red: 1.00, green: 0.93, blue: 0.87), Color(red: 0.98, green: 0.82, blue: 0.72)]
        case .midnight:
            [Color(red: 0.06, green: 0.07, blue: 0.16), Color(red: 0.12, green: 0.15, blue: 0.33)]
        }
    }
}

struct ThemeBackdrop: View {
    @AppStorage(AppTheme.storageKey) private var storedTheme = AppTheme.system.rawValue

    private var theme: AppTheme { AppTheme(rawValue: storedTheme) ?? .system }

    var body: some View {
        LinearGradient(
            colors: theme.backgroundColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(theme.tint.opacity(theme == .system ? 0.05 : 0.16))
                .frame(width: 520, height: 520)
                .blur(radius: 90)
                .offset(x: 150, y: -220)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private struct ThemedCardModifier: ViewModifier {
    @AppStorage(AppTheme.storageKey) private var storedTheme = AppTheme.system.rawValue
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let theme = AppTheme(rawValue: storedTheme) ?? .system
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(theme.tint.opacity(theme == .system ? 0.06 : 0.13))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(theme.tint.opacity(theme == .system ? 0.08 : 0.18), lineWidth: 1)
            }
    }
}

private struct AppThemeModifier: ViewModifier {
    @AppStorage(AppTheme.storageKey) private var storedTheme = AppTheme.system.rawValue

    func body(content: Content) -> some View {
        let theme = AppTheme(rawValue: storedTheme) ?? .system
        content
            .tint(theme.tint)
            .preferredColorScheme(theme.preferredColorScheme)
    }
}

extension View {
    func applyingAppTheme() -> some View {
        modifier(AppThemeModifier())
    }

    func themedCard(cornerRadius: CGFloat) -> some View {
        modifier(ThemedCardModifier(cornerRadius: cornerRadius))
    }
}
