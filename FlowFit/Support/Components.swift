import SwiftUI

// The FlowFit component library: cards on a dark canvas, bold headers,
// icon wells, chips, and custom selectors. Hierarchy comes from the
// neutral gray ramp; the accent marks only actions and active states.

/// Scrollable screen scaffold: charcoal canvas, screen padding,
/// consistent section rhythm.
struct Screen<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionGap) {
                content
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
    }
}

/// Big bold screen title with optional subtitle and leading logo.
struct ScreenHeader: View {
    let title: String
    var subtitle: String?
    var showLogo = false

    var body: some View {
        HStack(spacing: 12) {
            if showLogo {
                LogoMark(size: 42)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.appTextPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.appTextSecondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// The FF brand mark: surface tile, heavy initials, accent dot.
struct LogoMark: View {
    var size: CGFloat = 42

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28)
                .fill(Color.appSurface)
            RoundedRectangle(cornerRadius: size * 0.28)
                .stroke(Color.appBorder, lineWidth: 1)
            HStack(alignment: .lastTextBaseline, spacing: size * 0.04) {
                Text("FF")
                    .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.appTextPrimary)
                Circle()
                    .fill(Color.appAccent)
                    .frame(width: size * 0.11, height: size * 0.11)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Elevated surface card — the container all content lives in.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(padding)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(Color.appBorder, lineWidth: 1)
        )
    }
}

/// Bold section title rendered outside cards.
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline.weight(.bold))
            .foregroundStyle(Color.appTextPrimary)
    }
}

/// Circular icon container; accent only when active.
struct IconWell: View {
    let systemName: String
    var active = false
    var size: CGFloat = 38

    var body: some View {
        ZStack {
            Circle().fill(Color.appBorder)
            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundStyle(active ? Color.appAccent : Color.appIconInactive)
        }
        .frame(width: size, height: size)
    }
}

/// Capsule chip: metadata tags and selectable options.
struct Chip: View {
    let label: String
    var systemImage: String?
    var selected = false

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage).font(.caption2)
            }
            Text(label).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(selected ? Color.appAccent : Color.appBorder, in: Capsule())
        .foregroundStyle(selected ? Color.appBackground : Color.appTextSecondary)
    }
}

/// Two-or-more segment pill selector (e.g. Home / Gym).
struct PillToggle<T: Hashable>: View {
    @Binding var selection: T
    let options: [(value: T, label: String, icon: String?)]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selection = option.value }
                } label: {
                    HStack(spacing: 6) {
                        if let icon = option.icon {
                            Image(systemName: icon).font(.subheadline)
                        }
                        Text(option.label).font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(selection == option.value ? Color.appAccent : .clear, in: Capsule())
                    .foregroundStyle(selection == option.value ? Color.appBackground : Color.appTextSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pill-\(option.label)")
            }
        }
        .padding(4)
        .background(Color.appSurface, in: Capsule())
        .overlay(Capsule().stroke(Color.appBorder, lineWidth: 1))
    }
}

/// Selectable option tile (e.g. energy level) — accent border when picked.
struct OptionCard: View {
    let emoji: String
    let label: String
    var selected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(emoji).font(.title2)
            Text(label)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(selected ? Color.appTextPrimary : Color.appTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 4)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(selected ? Color.appAccent : Color.appBorder, lineWidth: selected ? 1.5 : 1)
        )
    }
}

/// − / + stepper with a large center value.
struct CapsuleStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 5
    var unit = "min"

    var body: some View {
        HStack {
            stepButton("minus") { value = max(range.lowerBound, value - step) }
            Spacer()
            VStack(spacing: 0) {
                Text("\(value)")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Color.appTextPrimary)
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
            }
            Spacer()
            stepButton("plus") { value = min(range.upperBound, value + step) }
        }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(Color.appTextPrimary)
                .frame(width: 44, height: 44)
                .background(Color.appBorder, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("stepper-\(symbol)")
    }
}

/// Thin accent progress bar (weekly plan completion).
struct ThinProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.appBorder)
                Capsule()
                    .fill(Color.appAccent)
                    .frame(width: max(0, min(1, progress)) * geo.size.width)
            }
        }
        .frame(height: 6)
    }
}

/// Small caption label above a text field, for inputs inside cards.
struct LabeledField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.appTextSecondary)
            TextField(placeholder, text: $text, axis: .vertical)
                .foregroundStyle(Color.appTextPrimary)
        }
    }
}

/// Low-emphasis text button for secondary actions.
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.appTextSecondary.opacity(configuration.isPressed ? 0.6 : 1))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
    }
}

extension ButtonStyle where Self == GhostButtonStyle {
    static var ghost: GhostButtonStyle { GhostButtonStyle() }
}
