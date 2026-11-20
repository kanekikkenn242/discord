import SwiftUI
import UIKit

enum Theme {
    static let orange = Color(red: 1.00, green: 0.478, blue: 0.00)
    static let green = Color(red: 0.20, green: 0.80, blue: 0.40)
    static let red = Color(red: 0.90, green: 0.30, blue: 0.30)

    static let background = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.059, green: 0.059, blue: 0.078, alpha: 1)
            : UIColor.systemGroupedBackground
    })

    static let card = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.122, green: 0.122, blue: 0.141, alpha: 1)
            : UIColor.secondarySystemGroupedBackground
    })

    static let secondary = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.180, green: 0.180, blue: 0.200, alpha: 1)
            : UIColor.tertiarySystemFill
    })

    static let border = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.06)
            : UIColor(white: 0, alpha: 0.06)
    })

    static let textSecondary = Color(uiColor: .secondaryLabel)

    static let cardRadius: CGFloat = 16
    static let buttonRadius: CGFloat = 14
    static let pageInset: CGFloat = 16
    static let sectionSpacing: CGFloat = 18
    static let tabBarHeight: CGFloat = 64
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

struct CardBackground: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 0.5)
            )
    }
}

extension View {
    func appCard(padding: CGFloat = 16) -> some View {
        modifier(CardBackground(padding: padding))
    }

    func pageWidth() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AppTile: View {
    var size: CGFloat = 52
    var letter: String = "D"

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Theme.orange, Theme.orange.opacity(0.72)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Text(letter)
                    .font(.system(size: size * 0.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            )
            .frame(width: size, height: size)
            .shadow(color: Theme.orange.opacity(0.25), radius: size * 0.18, y: size * 0.08)
            .accessibilityHidden(true)
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 4)
    }
}

struct StatusPill: View {
    let text: String
    var color: Color = Theme.green
    var icon: String?

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.14), in: Capsule())
    }
}

struct IconBadge: View {
    let systemName: String
    var tint: Color = Theme.orange
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.14))
            Image(systemName: systemName)
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct SettingRow: View {
    let icon: String
    let title: String
    var value: String?
    var valueColor: Color = Theme.textSecondary
    var chevron: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: icon, size: 30)
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(valueColor)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
            }
        }
        .contentShape(Rectangle())
    }
}

struct DividerLine: View {
    var body: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 0.5)
            .padding(.leading, 42)
    }
}

struct SegmentedBar<Value: Hashable>: View {
    let values: [Value]
    let title: (Value) -> String
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 4) {
            ForEach(values, id: \.self) { value in
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        selection = value
                    }
                } label: {
                    Text(title(value))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(selection == value ? .white : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selection == value ? Theme.secondary : .clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.secondary.opacity(0.55), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous)
                    .fill(enabled ? Theme.orange : Theme.secondary)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous)
                    .fill(Theme.secondary)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct CircleIconButton: View {
    let systemName: String
    var tint: Color = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(Theme.card, in: Circle())
                .overlay(Circle().strokeBorder(Theme.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

struct ProgressSegments: View {
    let total: Int
    let current: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? Theme.orange : Theme.secondary)
                    .frame(height: 4)
            }
        }
    }
}

struct PageDots: View {
    let total: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index == current ? Theme.orange : Theme.secondary)
                    .frame(width: index == current ? 7 : 5, height: index == current ? 7 : 5)
            }
        }
    }
}
