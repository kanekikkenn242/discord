import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var pairing: PairingController
    @EnvironmentObject private var patches: PatchController
    @EnvironmentObject private var remote: RemotePatches
    @Environment(\.dismiss) private var dismiss
    @Environment(\.t) private var t

    @State private var showImport = false
    @State private var importError: String?
    @State private var showIOS27Builds = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    versionCard
                    languageCard
                    appearanceCard
                    deviceCard
                    exploitCard
                    pairingCard
                    remoteCard
                    verifiedCard
                    socialCard
                }
                .padding(Theme.pageInset)
                .padding(.bottom, 20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(t("settings.title"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .fileImporter(
            isPresented: $showImport,
            allowedContentTypes: [.data, .propertyList, .xml, .json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    log("pairing: no url selected", level: .warning)
                    return
                }
                log("pairing: attempting import of \(url.lastPathComponent)", level: .info)
                do {
                    let path = try pairing.importPairingFile(from: url)
                    log("pairing: imported OK -> \(path)", level: .success)
                    state.refreshPatches()
                } catch {
                    log("pairing: import failed: \(error)", level: .error)
                    importError = error.localizedDescription
                }
            case .failure(let error):
                log("pairing: fileImporter failed: \(error)", level: .error)
                importError = error.localizedDescription
            }
        }
        .alert(
            t("settings.pairing.import"),
            isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )
        ) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(t("common.done")) { dismiss() }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.orange)
            }
        }
    }

    // MARK: - Version

    private var versionCard: some View {
        HStack(spacing: 12) {
            AppTile(size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("evergarden")
                    .font(.system(size: 16, weight: .bold))
                Text("v\(state.version)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Text("\(t("settings.version.bundle")) \(AppInfo.bundleID)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer()
        }
        .appCard(padding: 14)
    }

    // MARK: - Preferences

    private var languageCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: t("settings.language"))
            SegmentedBar(
                values: AppLanguage.allCases,
                title: { $0.displayName },
                selection: $state.language
            )
            .appCard(padding: 8)
        }
    }

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: t("settings.appearance"))
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
            .appCard(padding: 8)
        }
    }

    // MARK: - Device

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: t("settings.device"))
            VStack(spacing: 0) {
                SettingRow(icon: "iphone", title: t("home.device.hardware"), value: AppInfo.machine)
                DividerLine()
                SettingRow(icon: "gear", title: t("home.device.ios"), value: state.deviceOS)
            }
            .appCard(padding: 14)
        }
    }

    // MARK: - Exploit

    private var exploitCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: t("settings.exploit.title"))

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    IconBadge(systemName: "bolt.fill", tint: exploitColor, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("home.device.exploit"))
                            .font(.system(size: 14, weight: .semibold))
                        Text(state.kernelApplicable
                             ? t("settings.exploit.supported")
                             : t("settings.exploit.unsupported"))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    StatusPill(text: exploitPill, color: exploitColor)
                }

                Button {
                    state.runKernelExploit()
                } label: {
                    HStack(spacing: 8) {
                        if state.kernelRunning {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.75)
                        }
                        Text(state.kernelRunning ? t("settings.exploit.running") : t("settings.exploit.run"))
                    }
                }
                .buttonStyle(PrimaryButtonStyle(enabled: state.kernelApplicable && !state.kernelRunning))
                .disabled(!state.kernelApplicable || state.kernelRunning)
            }
            .appCard(padding: 14)
        }
    }

    private var exploitPill: String {
        switch state.exploitStatus {
        case .supported: return t("status.supported")
        case .unsupported: return t("status.unsupported")
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

    // MARK: - Pairing

    private var pairingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: t("settings.pairing"))

            VStack(alignment: .leading, spacing: 12) {
                SettingRow(
                    icon: "point.3.connected.trianglepath.dotted",
                    title: t("settings.pairing.runtime"),
                    value: patches.backend,
                    valueColor: Theme.textSecondary
                )

                DividerLine()

                SettingRow(
                    icon: "shield.lefthalf.filled",
                    title: t("settings.pairing.status"),
                    value: pairing.statusText,
                    valueColor: pairing.hasPairingFile ? Theme.green : Theme.orange
                )

                if let pin = pairing.currentPin {
                    HStack {
                        Image(systemName: "number")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.orange)
                        Text(String(format: t("settings.pairing.pin"), pin))
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.orange)
                            .tracking(6)
                        Spacer()
                    }
                    .padding(12)
                    .background(Theme.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Text(t("settings.pairing.hint"))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button {
                        if pairing.status.isBusy {
                            pairing.cancelPairing()
                        } else {
                            pairing.startPairing()
                        }
                    } label: {
                        Text(pairing.status.isBusy ? t("settings.pairing.stop") : t("settings.pairing.start"))
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button {
                        pairing.connect()
                    } label: {
                        Text(t("settings.pairing.verify"))
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                HStack(spacing: 8) {
                    Button {
                        state.openLocalDevVPN()
                    } label: {
                        Text(t("settings.pairing.openVpn"))
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button {
                        showImport = true
                    } label: {
                        Text(t("settings.pairing.import"))
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                // A refused Local Network permission is the one pairing failure
                // the user cannot recover from inside the app.
                if case .failed = pairing.status {
                    Button {
                        state.openSystemSettings()
                    } label: {
                        Text(t("settings.pairing.openSettings"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.orange)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Theme.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                if pairing.hasPairingFile {
                    Button {
                        pairing.forgetPairing()
                    } label: {
                        Text(t("settings.pairing.forget"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Theme.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .appCard(padding: 14)
        }
    }

    // MARK: - Remote library

    /// Patch payloads live on the user's own host; the build itself ships none.
    private var remoteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: t("settings.remote.title"))

            VStack(alignment: .leading, spacing: 10) {
                TextField(t("settings.remote.url"), text: $remote.libraryURL)
                    .font(.system(size: 12, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.URL)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Theme.border, lineWidth: 0.5)
                    )

                Text(t("settings.remote.hint"))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Task {
                        await remote.sync()
                        state.refreshPatches()
                    }
                } label: {
                    Text(remote.isSyncing ? t("remote.syncing") : t("remote.sync"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(remote.isSyncing ? Theme.textSecondary : Theme.orange)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(remote.isSyncing)

                if let report = remote.lastReport {
                    Text(report)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .appCard(padding: 14)
        }
    }

    // MARK: - Verified versions

    private var verifiedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: t("settings.verified.title"))

            VStack(spacing: 0) {
                HStack {
                    Text(t("home.device.exploit"))
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    StatusPill(text: exploitPill, color: exploitColor)
                }
                .padding(14)

                DividerLine()

                ForEach([17, 18, 26], id: \.self) { major in
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.green)
                        Text("iOS \(major)")
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                        Text(String(format: t("onboarding.versions.builds"), buildCount(major)))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary.opacity(0.6))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                    DividerLine()
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showIOS27Builds.toggle()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.green)
                        Text("iOS 27")
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                        Text(String(format: t("onboarding.versions.betas"), ExploitSupportPolicy.verifiedIOS27Builds.count))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary.opacity(0.6))
                            .rotationEffect(.degrees(showIOS27Builds ? 90 : 0))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showIOS27Builds {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(ExploitSupportPolicy.verifiedIOS27Builds.indices, id: \.self) { index in
                            HStack {
                                Text("beta \(ExploitSupportPolicy.verifiedIOS27Builds[index].beta)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Theme.textSecondary)
                                Spacer()
                                Text(ExploitSupportPolicy.verifiedIOS27Builds[index].build)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }

                DividerLine()

                Text(t("settings.verified.footer"))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(14)
            }
            .appCard(padding: 0)
        }
    }

    private func buildCount(_ major: Int) -> Int {
        switch major {
        case 17: return ExploitSupportPolicy.verifiedIOS17BuildCount
        case 18: return ExploitSupportPolicy.verifiedIOS18BuildCount
        case 26: return ExploitSupportPolicy.verifiedIOS26BuildCount
        default: return 0
        }
    }

    // MARK: - Social

    private var socialCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: t("settings.social.title"))

            VStack(spacing: 0) {
                socialRow(icon: "bubble.left.and.bubble.right.fill", title: t("settings.social.discord"), url: AppLinks.discord)
                DividerLine()
                socialRow(icon: "paperplane.fill", title: t("settings.social.telegram"), url: AppLinks.telegram)
                DividerLine()
                socialRow(icon: "chevron.left.forwardslash.chevron.right", title: t("settings.social.github"), url: AppLinks.github)
            }
            .appCard(padding: 14)
        }
    }

    private func socialRow(icon: String, title: String, url: String) -> some View {
        Button {
            state.openURL(url)
        } label: {
            SettingRow(icon: icon, title: title, value: nil, chevron: true)
        }
        .buttonStyle(.plain)
    }
}
