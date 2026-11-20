import SwiftUI

struct OnboardingView: View {
    let onFinished: () -> Void

    @EnvironmentObject private var state: AppState
    @Environment(\.t) private var t

    @State private var step = 0
    @State private var showIOS27Builds = false

    private let stepCount = 5

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Theme.pageInset)
                .padding(.top, 12)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    stepContent
                        .padding(.top, 22)
                }
                .padding(.horizontal, Theme.pageInset)
                .padding(.bottom, 24)
            }

            bottomBar
                .padding(.horizontal, Theme.pageInset)
                .padding(.bottom, 18)
        }
        .background(Theme.background.ignoresSafeArea())
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            ProgressSegments(total: stepCount, current: step)
            Text(String(format: t("onboarding.step"), step + 1))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Steps

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: welcomeStep
        case 1: languageStep
        case 2: setupStep
        case 3: versionsStep
        default: certificateStep
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 24)
            AppTile(size: 92, letter: "D")
            Text(t("onboarding.welcome.title"))
                .font(.system(size: 24, weight: .bold))
                .multilineTextAlignment(.center)
            Text(t("onboarding.welcome.subtitle"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            PageDots(total: stepCount, current: step)
                .padding(.top, 8)
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 420)
    }

    private var languageStep: some View {
        VStack(spacing: 16) {
            stepIcon("globe")
            stepTitle(t("onboarding.language.title"), subtitle: t("onboarding.language.subtitle"))

            VStack(spacing: 0) {
                ForEach(AppLanguage.allCases.indices, id: \.self) { index in
                    Button {
                        state.language = AppLanguage.allCases[index]
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(AppLanguage.allCases[index].displayName)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text(AppLanguage.allCases[index].subtitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: state.language == AppLanguage.allCases[index]
                                  ? "checkmark.circle.fill"
                                  : "circle")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(state.language == AppLanguage.allCases[index] ? Theme.orange : Theme.textSecondary.opacity(0.5))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < AppLanguage.allCases.count - 1 {
                        DividerLine()
                    }
                }
            }
            .appCard(padding: 0)
        }
    }

    private var setupStep: some View {
        VStack(spacing: 16) {
            stepIcon("slider.horizontal.3")
            stepTitle(t("onboarding.setup.title"), subtitle: t("onboarding.setup.subtitle"))

            VStack(alignment: .leading, spacing: 10) {
                Text(t("onboarding.setup.appearance"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)

                SegmentedBar(
                    values: AppAppearance.allCases,
                    title: { appearance in
                        switch appearance {
                        case .system: return t("onboarding.setup.system")
                        case .light: return t("onboarding.setup.light")
                        case .dark: return t("onboarding.setup.dark")
                        }
                    },
                    selection: $state.appearance
                )
            }
            .appCard()

            VStack(alignment: .leading, spacing: 10) {
                Text(t("onboarding.setup.game"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)

                HStack(spacing: 10) {
                    ForEach(FreeFireGame.allCases) { game in
                        GameCard(
                            game: game,
                            selected: state.selectedGame == game
                        ) {
                            state.selectedGame = game
                        }
                    }
                }
            }
            .appCard()
        }
    }

    private var versionsStep: some View {
        VStack(spacing: 16) {
            stepIcon("iphone")
            stepTitle(t("onboarding.versions.title"), subtitle: t("onboarding.versions.subtitle"))

            VStack(spacing: 0) {
                versionRow(major: 17, count: ExploitSupportPolicy.verifiedIOS17BuildCount)
                DividerLine()
                versionRow(major: 18, count: ExploitSupportPolicy.verifiedIOS18BuildCount)
                DividerLine()
                versionRow(major: 26, count: ExploitSupportPolicy.verifiedIOS26BuildCount)
                DividerLine()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showIOS27Builds.toggle()
                    }
                } label: {
                    versionRowContent(
                        major: 27,
                        count: ExploitSupportPolicy.verifiedIOS27Builds.count,
                        expanded: showIOS27Builds
                    )
                }
                .buttonStyle(.plain)

                if showIOS27Builds {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(ExploitSupportPolicy.verifiedIOS27Builds.indices, id: \.self) { index in
                            HStack {
                                Text("iOS 27 beta \(ExploitSupportPolicy.verifiedIOS27Builds[index].beta)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(ExploitSupportPolicy.verifiedIOS27Builds[index].build)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .transition(.opacity)
                }
            }
            .appCard(padding: 0)

            Text(String(format: t("onboarding.versions.thisDevice"), AppInfo.osVersion, AppInfo.osBuild))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var certificateStep: some View {
        VStack(spacing: 16) {
            stepIcon("checkmark.shield")
            stepTitle(t("onboarding.cert.title"), subtitle: t("onboarding.cert.subtitle"))

            VStack(alignment: .leading, spacing: 14) {
                bullet(
                    icon: "checkmark.circle.fill",
                    color: Theme.green,
                    text: t("onboarding.cert.bullet1")
                )
                bullet(
                    icon: "xmark.circle.fill",
                    color: Theme.red,
                    text: t("onboarding.cert.bullet2")
                )
                bullet(
                    icon: "info.circle.fill",
                    color: Theme.textSecondary,
                    text: t("onboarding.cert.note")
                )
            }
            .appCard()
        }
    }

    // MARK: - Pieces

    private func stepIcon(_ name: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.orange.opacity(0.14))
            Image(systemName: name)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.orange)
        }
        .frame(width: 64, height: 64)
        .padding(.top, 8)
    }

    private func stepTitle(_ title: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
    }

    private func bullet(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func versionRow(major: Int, count: Int) -> some View {
        versionRowContent(major: major, count: count, expanded: false)
    }

    private func versionRowContent(major: Int, count: Int, expanded: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.green)

            Text("iOS \(major)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            Text(String(format: t("onboarding.versions.builds"), count))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary.opacity(0.6))
                .rotationEffect(.degrees(expanded ? 90 : 0))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button {
                guard step > 0 else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    step -= 1
                }
            } label: {
                Text(t("common.back"))
            }
            .buttonStyle(SecondaryButtonStyle())
            .opacity(step == 0 ? 0.45 : 1)
            .disabled(step == 0)

            Button {
                if step == stepCount - 1 {
                    onFinished()
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        step += 1
                    }
                }
            } label: {
                Text(step == stepCount - 1 ? t("common.finish") : t("common.next"))
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }
}

struct GameCard: View {
    let game: FreeFireGame
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(selected ? Theme.orange : Theme.secondary)
                    Image(systemName: game == .freeFire ? "flame.fill" : "crown.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(selected ? .white : Theme.textSecondary)
                }
                .frame(height: 56)

                Text(game.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selected ? .primary : Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.secondary.opacity(0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? Theme.orange.opacity(0.7) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
