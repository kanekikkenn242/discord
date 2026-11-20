import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var activation: ActivationStore
    @Environment(\.t) private var t

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                membershipCard
                activateRow
                gameSection
                noticesRow
                musicRow

                if activation.isActivated {
                    Button {
                        activation.deactivate()
                    } label: {
                        Text(t("profile.deactivate"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Theme.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Text(String(format: t("home.footer"), state.version))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, Theme.pageInset)
            .padding(.top, 10)
        }
    }

    private var membershipCard: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Theme.orange.opacity(0.12))
                Image(systemName: activation.isActivated ? "checkmark.shield.fill" : "lock.shield")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.orange)
            }
            .frame(width: 54, height: 54)

            Text(activation.isActivated ? t("profile.membership.active") : t("profile.membership.none"))
                .font(.system(size: 18, weight: .bold))

            Text(membershipSubtitle)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .appCard(padding: 16)
    }

    private var membershipSubtitle: String {
        if activation.isActivated {
            let date = activation.activatedAt?.formatted(date: .abbreviated, time: .omitted) ?? "—"
            return String(
                format: t("profile.membership.activeSubtitle"),
                activation.activatedKeyMasked,
                date
            )
        }
        return t("profile.membership.subtitle")
    }

    private var activateRow: some View {
        Button {
            state.showActivation = true
        } label: {
            HStack(spacing: 12) {
                IconBadge(systemName: "key.fill", size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("profile.activate"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(t("profile.activate.subtitle"))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary.opacity(0.6))
            }
            .appCard(padding: 14)
        }
        .buttonStyle(.plain)
    }

    private var gameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: t("profile.game"))

            VStack(alignment: .leading, spacing: 12) {
                Text(t("profile.game.subtitle"))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    ForEach(FreeFireGame.allCases) { game in
                        GameCard(game: game, selected: state.selectedGame == game) {
                            state.selectedGame = game
                        }
                    }
                }
            }
            .appCard(padding: 14)
        }
    }

    private var noticesRow: some View {
        Button {
            state.showNotices = true
        } label: {
            HStack(spacing: 12) {
                IconBadge(systemName: "bell.fill", size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("profile.notices"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(t("profile.notices.subtitle"))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary.opacity(0.6))
            }
            .appCard(padding: 14)
        }
        .buttonStyle(.plain)
    }

    private var musicRow: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: "music.note", size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(t("profile.music"))
                    .font(.system(size: 14, weight: .semibold))
                Text(t("profile.music.subtitle"))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Toggle("", isOn: $state.musicEnabled)
                .labelsHidden()
                .tint(Theme.orange)
        }
        .appCard(padding: 14)
    }
}

struct ActivationSheet: View {
    @EnvironmentObject private var activation: ActivationStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.t) private var t

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(t("activation.title"))
                    .font(.system(size: 20, weight: .bold))

                Text(t("activation.field"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)

                TextField("XXXX-XXXX-XXXX", text: $activation.key)
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.border, lineWidth: 0.5)
                    )

                if let message = activation.errorMessage {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.red)
                }

                Button {
                    Task { await activation.activate() }
                } label: {
                    HStack(spacing: 8) {
                        if activation.isBusy {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.75)
                        }
                        Text(t("activation.button"))
                    }
                }
                .buttonStyle(PrimaryButtonStyle(enabled: !activation.isBusy))
                .disabled(activation.isBusy)

                Spacer()
            }
            .padding(Theme.pageInset)
            .padding(.top, 8)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(t("common.close")) { dismiss() }
                        .foregroundStyle(Theme.orange)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
