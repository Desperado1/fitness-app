import SwiftUI

// Dark-first, minimalist palette. Near-black base (not pure black, to
// avoid OLED harshness and text halation), hierarchy carried by a
// neutral gray ramp, and a single accent reserved for primary actions,
// active states, and progress. Body text on dark surfaces meets
// WCAG AA (4.5:1): #F5F5F4 on #121214 ≈ 16:1, #8A8A8F on #1A1A1D ≈ 5:1.
extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// Primary background: deep charcoal.
    static let appBackground = Color(hex: 0x121214)
    /// Elevated surfaces: cards, rows, sheets.
    static let appSurface = Color(hex: 0x1A1A1D)
    /// Primary text: off-white, not pure white.
    static let appTextPrimary = Color(hex: 0xF5F5F4)
    /// Secondary / muted text.
    static let appTextSecondary = Color(hex: 0x8A8A8F)
    /// Borders and dividers.
    static let appBorder = Color(hex: 0x2A2A2E)
    /// Inactive icons.
    static let appIconInactive = Color(hex: 0x5A5A60)
    /// The single accent: primary actions, active states, progress.
    /// Light enough for ~8:1 on the charcoal base; filled controls use
    /// charcoal text on it (also ~8:1).
    static let appAccent = Color(hex: 0x64B5C9)
}

extension View {
    /// Screen canvas: hides the system scroll background and paints the
    /// charcoal base.
    func themedScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color.appBackground.ignoresSafeArea())
    }

    /// Row treatment for Form/List sections: elevated surface + border-
    /// toned separators.
    func themedRow() -> some View {
        self
            .listRowBackground(Color.appSurface)
            .listRowSeparatorTint(Color.appBorder)
    }
}

/// Filled accent button for the one primary action per screen.
/// Charcoal label on the accent keeps contrast ~8:1.
struct PrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.appBackground)
            .tint(Color.appBackground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                Color.appAccent.opacity(configuration.isPressed ? 0.75 : (isEnabled ? 1 : 0.35)),
                in: Capsule()
            )
    }
}

extension ButtonStyle where Self == PrimaryActionButtonStyle {
    static var primaryAction: PrimaryActionButtonStyle { PrimaryActionButtonStyle() }
}

/// Design-system constants plus one-time UIKit appearance for the
/// chrome SwiftUI doesn't expose (tab bar and navigation bar colors).
enum Theme {
    /// Horizontal screen padding.
    static let screenPadding: CGFloat = 20
    /// Corner radius for cards and option tiles.
    static let cardRadius: CGFloat = 16
    /// Vertical rhythm between sections.
    static let sectionGap: CGFloat = 24

    static func configureAppearance() {
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(Color.appBackground)
        let item = UITabBarItemAppearance()
        item.normal.iconColor = UIColor(Color.appIconInactive)
        item.normal.titleTextAttributes = [.foregroundColor: UIColor(Color.appIconInactive)]
        item.selected.iconColor = UIColor(Color.appAccent)
        item.selected.titleTextAttributes = [.foregroundColor: UIColor(Color.appAccent)]
        tab.stackedLayoutAppearance = item
        tab.inlineLayoutAppearance = item
        tab.compactInlineLayoutAppearance = item
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(Color.appBackground)
        nav.titleTextAttributes = [.foregroundColor: UIColor(Color.appTextPrimary)]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor(Color.appTextPrimary)]
        nav.shadowColor = UIColor(Color.appBorder)
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
    }
}
