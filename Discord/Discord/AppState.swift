import Foundation
import SwiftUI
import UIKit
import Combine

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    static let storageKey = "discord.appearance"
}

enum ExploitStatus {
    case unknown
    case supported
    case unsupported
    case running
    case ready
    case failed
}

@MainActor
final class AppState: ObservableObject {
    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.storageKey) }
    }

    @Published var appearance: AppAppearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: AppAppearance.storageKey) }
    }

    @Published var selectedGame: FreeFireGame {
        didSet { UserDefaults.standard.set(selectedGame.rawValue, forKey: Self.gameKey) }
    }

    @Published var musicEnabled: Bool {
        didSet {
            UserDefaults.standard.set(musicEnabled, forKey: Self.musicKey)
            SoundPlayer.shared.setEnabled(musicEnabled)
        }
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: Self.onboardingKey) }
    }

    @Published var showSettings = false
    @Published var showActivation = false
    @Published var showNotices = false
    @Published var kernelRunning = false
    @Published var kernelOutcome: Bool?

    let activation = ActivationStore()
    let patches = PatchController()
    let pairing = PairingController.shared
    let log = AppLog.shared

    private static let gameKey = "discord.selectedGame"
    private static let musicKey = "discord.musicEnabled"
    private static let onboardingKey = "discord.onboardingComplete"

    init() {
        let defaults = UserDefaults.standard

        language = AppLanguage(
            rawValue: defaults.string(forKey: AppLanguage.storageKey) ?? ""
        ) ?? .english

        appearance = AppAppearance(
            rawValue: defaults.string(forKey: AppAppearance.storageKey) ?? ""
        ) ?? .dark

        selectedGame = FreeFireGame(
            rawValue: defaults.string(forKey: Self.gameKey) ?? ""
        ) ?? .freeFire

        musicEnabled = defaults.bool(forKey: Self.musicKey)
        hasCompletedOnboarding = defaults.bool(forKey: Self.onboardingKey)

        if hasCompletedOnboarding {
            SoundPlayer.shared.setEnabled(musicEnabled)
            patches.refresh(game: selectedGame)
        }
    }

    // MARK: - Support

    var version: String { AppInfo.fullVersion }

    var deviceModel: String { AppInfo.machine }

    var deviceOS: String { "\(AppInfo.osVersion) (\(AppInfo.osBuild))" }

    var exploitStatus: ExploitStatus {
        if kernelRunning { return .running }
        if let kernelOutcome {
            return kernelOutcome ? .ready : .failed
        }
        // This row is specifically about the kernel route. The pairing route
        // has its own status card and works on builds where kfd does not.
        return kernelApplicable ? .supported : .unsupported
    }

    var kernelApplicable: Bool {
        let tuple = AppInfo.versionTuple
        return KernelExploit.isApplicable(
            major: tuple.major,
            minor: tuple.minor,
            patch: tuple.patch,
            build: AppInfo.osBuild
        )
    }

    var pairingConnected: Bool { pairing.status.isConnected }

    var packageCount: Int { FreeFireCatalog.installedProductCount() }

    var backupCount: Int { BackupStore.backupCount() }

    var backupBytes: String { PatchPath.prettyBytes(BackupStore.totalBytes()) }

    // MARK: - Actions

    func setPatch(_ product: PatchProduct, enabled: Bool) {
        guard activation.isActivated else {
            Discord.log("ui: activation required before patching", level: .warning)
            showActivation = true
            return
        }
        patches.setEnabled(
            enabled,
            product: product,
            game: selectedGame,
            allowKernel: kernelApplicable
        )
    }

    func refreshPatches() {
        patches.refresh(game: selectedGame)
    }

    func runKernelExploit() {
        guard !kernelRunning else { return }
        kernelRunning = true
        kernelOutcome = nil
        Task.detached(priority: .userInitiated) {
            let ok = KernelExploit.run()
            await MainActor.run {
                self.kernelRunning = false
                self.kernelOutcome = ok
                self.patches.refresh(game: self.selectedGame)
            }
        }
    }

    func patchSummary() -> (loaded: Int, idle: Int, unavailable: Int) {
        var loaded = 0
        var idle = 0
        var unavailable = 0
        for product in FreeFireCatalog.products {
            switch patches.status(for: product) {
            case .loaded: loaded += 1
            case .notLoaded: idle += 1
            default: unavailable += 1
            }
        }
        return (loaded, idle, unavailable)
    }

    func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        UIApplication.shared.open(url)
    }

    func openLocalDevVPN() {
        if let url = URL(string: "localdevvpn://"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            openURL("https://apps.apple.com/search?term=LocalDevVPN")
        }
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
