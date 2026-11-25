import SwiftUI

enum AppLinks {
    static let discord = "https://discord.com"
    static let telegram = "https://t.me"
    static let github = "https://github.com"

    /// When `discord.api.base` is set to the deployed UDID gateway, the install
    /// profile is generated per device and carries the MDM check-in URL that
    /// binds the licence key to the real iPhone UDID. Otherwise the static
    /// hosted profile is used.
    static var installProfile: String {
        let defaults = UserDefaults.standard
        let base = (defaults.string(forKey: "discord.api.base") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !base.isEmpty else {
            let token = defaults.string(forKey: "discord.udid.token") ?? UUID()
                .uuidString.replacingOccurrences(of: "-", with: "").uppercased()
            defaults.set(token, forKey: "discord.udid.token")
            return "https://dope-udid-zada-2026.dope-udid-zada.workers.dev/udid/web?l=es&v=3&t=\(token)"
        }
        let token = defaults.string(forKey: "discord.udid.token") ?? UUID()
            .uuidString.replacingOccurrences(of: "-", with: "").uppercased()
        defaults.set(token, forKey: "discord.udid.token")
        return "\(base)/udid/web?l=es&v=3&t=\(token)"
    }
}

struct SupportView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var patches: PatchController
    @Environment(\.t) private var t

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                header

                VStack(spacing: 0) {
                    supportRow(
                        icon: "bubble.left.and.bubble.right.fill",
                        title: t("support.discord"),
                        subtitle: t("support.discord.subtitle")
                    ) {
                        state.openURL(AppLinks.discord)
                    }

                    DividerLine()

                    supportRow(
                        icon: "megaphone.fill",
                        title: t("support.announcements"),
                        subtitle: t("support.announcements.subtitle")
                    ) {
                        state.openURL(AppLinks.discord)
                    }

                    DividerLine()

                    supportRow(
                        icon: "checklist",
                        title: t("support.status"),
                        subtitle: t("support.status.subtitle")
                    ) {
                        state.refreshPatches()
                    }
                }
                .appCard(padding: 14)

                statusCard

                Text(String(format: t("home.footer"), state.version))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, Theme.pageInset)
            .padding(.top, 10)
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Theme.orange.opacity(0.12))
                Image(systemName: "headphones")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.orange)
            }
            .frame(width: 62, height: 62)

            Text(t("support.center"))
                .font(.system(size: 20, weight: .bold))

            Text(t("support.subtitle"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .appCard(padding: 16)
    }

    private var statusCard: some View {
        let summary = state.patchSummary()

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(t("support.status.title"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    state.refreshPatches()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.orange)
                        .frame(width: 28, height: 28)
                        .background(Theme.orange.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 0) {
                statusStat(
                    value: "\(summary.loaded)",
                    label: t("status.loaded"),
                    color: Theme.green
                )

                Rectangle()
                    .fill(Theme.border)
                    .frame(width: 0.5, height: 30)

                statusStat(
                    value: "\(summary.idle)",
                    label: t("status.notLoaded"),
                    color: Theme.textSecondary
                )

                Rectangle()
                    .fill(Theme.border)
                    .frame(width: 0.5, height: 30)

                statusStat(
                    value: "\(summary.unavailable)",
                    label: t("status.packageMissing"),
                    color: Theme.red
                )
            }
        }
        .appCard(padding: 14)
    }

    private func statusStat(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func supportRow(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconBadge(systemName: icon, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary.opacity(0.6))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
