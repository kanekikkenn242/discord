import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .home

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()

            Group {
                switch tab {
                case .home: HomeView()
                case .game: GameView()
                case .profile: ProfileView()
                case .support: SupportView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 78)

            AppTabBar(selection: $tab)
        }
        .sheet(isPresented: $state.showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $state.showActivation) {
            ActivationSheet()
        }
        .sheet(isPresented: $state.showNotices) {
            NoticesSheet()
        }
        .onChange(of: state.selectedGame) { _ in
            state.refreshPatches()
        }
        // Pairing, the tunnel and worse_query all finish after the first probe
        // has already reported "no backend". Re-resolving on those transitions
        // and on returning to the app keeps the patch switches usable without
        // a manual refresh.
        .onChange(of: state.pairing.status) { _ in
            state.refreshPatches()
        }
        .onChange(of: state.pairing.hasPairingFile) { _ in
            state.refreshPatches()
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            state.activation.revalidate()
            state.pairing.refresh()
            state.refreshPatches()
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var pairing: PairingController
    @EnvironmentObject private var patches: PatchController
    @Environment(\.t) private var t

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Theme.sectionSpacing) {
                header
                deviceSection
                pairingSection
                librarySection

                Text(String(format: t("home.footer"), state.version))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
                    .padding(.top, 6)
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, Theme.pageInset)
            .padding(.top, 10)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AppTile(size: 52)

                VStack(alignment: .leading, spacing: 2) {
                    Text("dope")
                        .font(.system(size: 20, weight: .bold))
                    Text(t("home.subtitle"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer(minLength: 4)

                HStack(spacing: 8) {
                    CircleIconButton(systemName: "gift.fill") {
                        state.showActivation = true
                    }
                    CircleIconButton(systemName: "gearshape.fill") {
                        state.showSettings = true
                    }
                }
            }

            HStack(spacing: 8) {
                StatusPill(
                    text: state.selectedGame.displayName,
                    color: Theme.green,
                    icon: state.selectedGame == .freeFire ? "flame.fill" : "crown.fill"
                )

                StatusPill(
                    text: patches.backend,
                    color: Theme.textSecondary,
                    icon: "point.3.connected.trianglepath.dotted"
                )

                Spacer()
            }
        }
        .padding(.top, 4)
    }

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: t("home.device.title"))

            VStack(spacing: 0) {
                SettingRow(
                    icon: "iphone",
                    title: t("home.device.hardware"),
                    value: AppInfo.machine
                )
                DividerLine()
                SettingRow(
                    icon: "gear",
                    title: t("home.device.ios"),
                    value: state.deviceOS
                )
                DividerLine()
                SettingRow(
                    icon: "bolt.fill",
                    title: t("home.device.exploit"),
                    value: exploitLabel,
                    valueColor: exploitColor
                )
            }
            .appCard(padding: 14)
        }
    }

    private var pairingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: t("home.pairing.title"))

            HStack(spacing: 12) {
                IconBadge(
                    systemName: "shield.lefthalf.filled",
                    tint: pairing.hasPairingFile ? Theme.green : Theme.orange,
                    size: 34
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(pairing.statusText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(pairing.detailText)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Button {
                    state.showSettings = true
                } label: {
                    Text(t("home.pairing.settings"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.orange.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .appCard(padding: 14)
        }
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: t("home.library.title"))

            HStack(spacing: 0) {
                statBlock(
                    value: "\(state.packageCount)/\(FreeFireCatalog.products.count)",
                    label: t("home.library.packages")
                )

                Rectangle()
                    .fill(Theme.border)
                    .frame(width: 0.5, height: 34)

                statBlock(
                    value: "\(state.backupCount)",
                    label: t("home.library.originals"),
                    detail: state.backupBytes
                )
            }
            .appCard(padding: 14)
        }
    }

    private func statBlock(value: String, label: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.orange)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            if let detail {
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private var exploitLabel: String {
        switch state.exploitStatus {
        case .supported: return t("settings.exploit.supported")
        case .unsupported: return t("settings.exploit.unsupported")
        case .running: return t("settings.exploit.running")
        case .ready: return t("status.loaded")
        case .failed: return t("notices.failed")
        case .unknown: return "—"
        }
    }

    private var exploitColor: Color {
        switch state.exploitStatus {
        case .supported, .ready: return Theme.green
        case .running: return Theme.orange
        case .failed, .unsupported: return Theme.red
        case .unknown: return Theme.textSecondary
        }
    }
}
