import SwiftUI
import UniformTypeIdentifiers

struct GameView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var patches: PatchController
    @EnvironmentObject private var remote: RemotePatches
    @Environment(\.t) private var t

    @State private var category: PatchCategory = .aimbot
    @State private var tab: AimbotTab = .cache
    @State private var showImporter = false
    @State private var importError: String?

    private var products: [PatchProduct] {
        FreeFireCatalog.products(for: category, tab: category == .aimbot ? tab : nil)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                header

                if let note = patches.exportNote {
                    Text("Documents/export — \(note)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                categoryChips
                remoteCard

                if category == .aimbot {
                    SegmentedBar(
                        values: AimbotTab.allCases,
                        title: { t($0.titleKey) },
                        selection: $tab
                    )
                }

                if let error = patches.lastError {
                    errorBanner(error)
                }

                if products.isEmpty {
                    EmptyStateCard(
                        icon: "shippingbox",
                        title: t("game.empty.title"),
                        subtitle: t("game.empty.subtitle")
                    )
                } else {
                    VStack(spacing: 10) {
                        ForEach(products) { product in
                            PatchCard(
                                product: product,
                                status: patches.status(for: product),
                                busy: patches.busyProductID == product.id
                            ) { enabled in
                                state.setPatch(product, enabled: enabled)
                            }
                        }
                    }
                }

                LogConsole()

                Text(String(format: t("home.footer"), state.version))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, Theme.pageInset)
            .padding(.top, 10)
        }
        .onAppear {
            state.refreshPatches()
        }
        .onChange(of: remote.lastReport) { _ in
            state.refreshPatches()
        }
        .onChange(of: state.selectedGame) { _ in
            state.refreshPatches()
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [UTType(filenameExtension: "3105") ?? .data, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    _ = try FreeFireCatalog.importPackage(from: url)
                    state.refreshPatches()
                } catch {
                    importError = error.localizedDescription
                }
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .alert(
            t("game.import.error"),
            isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )
        ) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.orange.opacity(0.16))
                Image(systemName: state.selectedGame == .freeFire ? "flame.fill" : "crown.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.orange)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 3) {
                Text(state.selectedGame.displayName)
                    .font(.system(size: 18, weight: .bold))
                Text(state.activation.isActivated ? t("game.ready") : t("game.locked"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(state.activation.isActivated ? Theme.green : Theme.orange)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(state.packageCount)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(t("game.packages"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }

            CircleIconButton(systemName: "square.and.arrow.up", tint: Theme.textSecondary) {
                patches.exportAvatarAsset(game: state.selectedGame)
            }

            CircleIconButton(systemName: "square.and.arrow.down", tint: Theme.textSecondary) {
                showImporter = true
            }

            CircleIconButton(systemName: "arrow.clockwise", tint: Theme.textSecondary) {
                state.refreshPatches()
            }
        }
        .appCard(padding: 14)
    }

    /// Products are pulled from the user's library on demand — the IPA ships
    /// without a single patch byte.
    private var remoteCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.orange.opacity(0.14))
                Image(systemName: remote.isSyncing ? "arrow.triangle.2.circlepath" : "icloud.and.arrow.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.orange)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(t("remote.title"))
                    .font(.system(size: 13, weight: .semibold))
                Text(remote.isSyncing
                     ? (remote.progressText ?? t("remote.syncing"))
                     : (remote.lastReport ?? t("remote.hint")))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            Button {
                Task {
                    await remote.sync()
                    state.refreshPatches()
                }
            } label: {
                Text(remote.isSyncing ? t("remote.syncing") : t("remote.sync"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(remote.isSyncing ? Theme.textSecondary : Theme.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.orange.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(remote.isSyncing)
        }
        .appCard(padding: 12)
    }

    private var categoryChips: some View {
        HStack(spacing: 8) {
            ForEach(PatchCategory.allCases) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        category = item
                    }
                } label: {
                    Text(t(item.titleKey))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(category == item ? .white : Theme.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(category == item ? Theme.orange : Theme.card)
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(Theme.border, lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.red)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(Theme.red.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(10)
        .background(Theme.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
