import Foundation
import Combine

@MainActor
final class PatchController: ObservableObject {
    @Published private(set) var statuses: [String: PatchProductStatus] = [:]
    @Published private(set) var busyProductID: String?
    @Published private(set) var backend: String = "not available"
    @Published private(set) var lastError: String?
    @Published private(set) var exportNote: String?

    private var refreshInFlight = false
    private var retryTask: Task<Void, Never>?
    private var autoRefreshTimer: Timer?

    /// Free Fire rewrites its hot-update manifest and re-downloads the shipped
    /// asset on every launch. The status pass below re-applies a `.partial`
    /// patch, but it only runs when Discord becomes active — too late for a
    /// match already in progress. The pairing service keeps this app alive in
    /// the background (background audio keep-alive), so a short repeating
    /// refresh puts the patch back within seconds of the game undoing it.
    private func startAutoRefresh(game: FreeFireGame) {
        guard autoRefreshTimer == nil else { return }
        autoRefreshTimer = Timer.scheduledTimer(
            withTimeInterval: 3,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.statuses.values.contains(where: { $0.isLoaded }) else { return }
                self.refresh(game: game)
            }
        }
    }

    var isBusy: Bool { busyProductID != nil }

    func status(for product: PatchProduct) -> PatchProductStatus {
        if busyProductID == product.id {
            return statuses[product.id] ?? .notLoaded
        }
        return statuses[product.id]
            ?? (FreeFireCatalog.hasPackage(for: product) ? .notLoaded : .packageMissing)
    }

    func refresh(game: FreeFireGame) {
        guard busyProductID == nil, !refreshInFlight else { return }
        retryTask?.cancel()
        retryTask = nil
        startRefresh(game: game, attempt: 0)
    }

    /// The pairing route resolves asynchronously: the tunnel can time out on
    /// the first probe and answer a few seconds later, and the cached
    /// worse_query container only appears after that. A single failed probe
    /// must not leave every switch disabled until the user taps refresh, so
    /// the whole-backend failure is retried a bounded number of times.
    private func startRefresh(game: FreeFireGame, attempt: Int) {
        guard busyProductID == nil, !refreshInFlight else { return }
        refreshInFlight = true

        let products = FreeFireCatalog.products
        Task.detached(priority: .userInitiated) {
            var resolved: [String: PatchProductStatus] = [:]
            for product in products where !FreeFireCatalog.hasPackage(for: product) {
                resolved[product.id] = .packageMissing
            }

            var backendName = PatchRuntime.backendDescription(game: game)
            var backendFailed = false

            do {
                let outcome = try PatchRuntime.withFileSystem(game: game, allowKernel: false) { fileSystem -> ([String: PatchProductStatus], String) in
                    var map: [String: PatchProductStatus] = [:]
                    for product in products where FreeFireCatalog.hasPackage(for: product) {
                        map[product.id] = PatchService.status(
                            product: product,
                            bundleID: game.rawValue,
                            fileSystem: fileSystem
                        )
                    }

                    // Free Fire rewrites its content-addressed hot asset on
                    // launch, so a patch that was in place yesterday comes
                    // back as .partial today. Re-apply it here instead of
                    // waiting for the user to notice the card switched off.
                    for product in products where FreeFireCatalog.hasPackage(for: product) {
                        guard case .partial = map[product.id] ?? .notLoaded,
                              let url = FreeFireCatalog.packageURL(for: product),
                              let package = try? PatchPackage.load(from: url) else { continue }
                        do {
                            _ = try PatchService.apply(
                                package: package,
                                product: product,
                                bundleID: game.rawValue,
                                fileSystem: fileSystem
                            )
                            log("patch: \(product.id) — re-applied after the game replaced its asset",
                                level: .success)
                            map[product.id] = .loaded
                        } catch {
                            log("patch: \(product.id) auto re-apply failed — \(error.localizedDescription)",
                                level: .warning)
                        }
                    }
                    return (map, fileSystem.backendName)
                }
                resolved.merge(outcome.0) { _, new in new }
                backendName = outcome.1
            } catch {
                let message = Self.short(error)
                let full = Self.full(error)
                backendFailed = true
                for product in products where FreeFireCatalog.hasPackage(for: product) {
                    resolved[product.id] = .unavailable(message)
                }
                log("patch: status unavailable — \(full)", level: .warning)
            }

            let finalStatuses = resolved
            let finalBackend = backendName
            await MainActor.run {
                self.refreshInFlight = false
                self.statuses = finalStatuses
                self.backend = finalBackend
                guard backendFailed, attempt < 2 else { return }
                self.retryTask?.cancel()
                self.retryTask = Task { @MainActor [weak self] in
                    let delay: UInt64 = attempt == 0 ? 4_000_000_000 : 15_000_000_000
                    try? await Task.sleep(nanoseconds: delay)
                    guard !Task.isCancelled, let self else { return }
                    self.startRefresh(game: game, attempt: attempt + 1)
                }
            }
        }
    }

    /// Puts every applied file back to its shipped bytes. Used by Safe mode.
    func restoreAll(game: FreeFireGame, allowKernel: Bool) {
        guard busyProductID == nil else { return }
        retryTask?.cancel()
        retryTask = nil
        busyProductID = "restoreAll"
        lastError = nil
        let bundleID = game.rawValue
        Task.detached(priority: .userInitiated) {
            defer {
                Task { @MainActor [weak self] in
                    self?.busyProductID = nil
                    self?.refresh(game: game)
                }
            }
            do {
                try PatchRuntime.withFileSystem(game: game, allowKernel: allowKernel) { fileSystem in
                    for product in FreeFireCatalog.products {
                        guard AppliedTargetsStore.load(
                            productID: product.id, bundleID: bundleID
                        ) != nil else { continue }
                        let package = FreeFireCatalog.packageURL(for: product)
                            .flatMap { try? PatchPackage.load(from: $0) }
                        do {
                            try PatchService.restore(
                                product: product,
                                bundleID: bundleID,
                                package: package,
                                fileSystem: fileSystem
                            )
                            log("ui: safe mode restored \(product.id)", level: .success)
                        } catch {
                            log("ui: safe mode could not restore \(product.id) — \(error.localizedDescription)",
                                level: .warning)
                        }
                    }
                }
            } catch {
                log("ui: safe mode backend unavailable — \(error.localizedDescription)", level: .warning)
            }
        }
    }

    func setEnabled(
        _ enabled: Bool,
        product: PatchProduct,
        game: FreeFireGame,
        allowKernel: Bool
    ) {
        guard busyProductID == nil else { return }

        retryTask?.cancel()
        retryTask = nil
        busyProductID = product.id
        lastError = nil

        let bundleID = game.rawValue
        let slot = product.slot
        let productID = product.id
        let conflicting = FreeFireCatalog.products.filter { $0.slot == slot && $0.id != productID }

        log("ui: \(enabled ? "apply" : "restore") \(productID) on \(bundleID)", level: .info)

        Task.detached(priority: .userInitiated) {
            do {
                let backendName = try PatchRuntime.withFileSystem(
                    game: game,
                    allowKernel: allowKernel
                ) { fileSystem -> String in
                    if enabled {
                        // One product per slot: the cache packages share the
                        // same cache_res pair, so the previous occupant is
                        // restored before the new bytes land.
                        for other in conflicting {
                            guard AppliedTargetsStore.load(
                                productID: other.id,
                                bundleID: bundleID
                            ) != nil else { continue }

                            let package = FreeFireCatalog.packageURL(for: other)
                                .flatMap { try? PatchPackage.load(from: $0) }
                            do {
                                try PatchService.restore(
                                    product: other,
                                    bundleID: bundleID,
                                    package: package,
                                    fileSystem: fileSystem
                                )
                                log("ui: cleared \(other.id) before applying \(productID)", level: .info)
                            } catch {
                                log("ui: could not clear \(other.id) — \(error.localizedDescription)", level: .warning)
                            }
                        }

                        guard let url = FreeFireCatalog.packageURL(for: product) else {
                            throw PatchServiceError.packageMissing(
                                product.packageNames.first ?? product.id
                            )
                        }
                        let package = try PatchPackage.load(from: url)
                        let result = try PatchService.apply(
                            package: package,
                            product: product,
                            bundleID: bundleID,
                            fileSystem: fileSystem
                        )
                        log(
                            "ui: \(result.packageName) applied through \(result.backend) — \(result.paths.count) file(s)",
                            level: .success
                        )
                    } else {
                        let package = FreeFireCatalog.packageURL(for: product)
                            .flatMap { try? PatchPackage.load(from: $0) }
                        let restored = try PatchService.restore(
                            product: product,
                            bundleID: bundleID,
                            package: package,
                            fileSystem: fileSystem
                        )
                        log("ui: restored \(restored.count) file(s) for \(productID)", level: .success)
                    }
                    return fileSystem.backendName
                }

                await MainActor.run {
                    self.busyProductID = nil
                    self.backend = backendName
                    self.statuses[productID] = enabled ? .loaded : .notLoaded
                    if enabled {
                        for other in conflicting where self.statuses[other.id]?.isLoaded == true {
                            self.statuses[other.id] = .notLoaded
                        }
                    }
                    if enabled {
                        self.startAutoRefresh(game: game)
                    }
                    SoundPlayer.shared.playEffect(enabled ? "activar" : "desactivar")
                }
            } catch {
                let message = Self.short(error)
                let full = Self.full(error)
                log("ui: \(productID) failed — \(full)", level: .error)
                await MainActor.run {
                    self.busyProductID = nil
                    self.lastError = full
                    self.statuses[productID] = .unavailable(message)
                }
            }
        }
    }

    /// Copies the avatar bundle the game is actually reading into this app's
    /// own Documents folder (visible in Files), so the exact build on the
    /// device can be inspected instead of guessed from the shipped base.
    func exportAvatarAsset(game: FreeFireGame) {
        guard busyProductID == nil else { return }

        busyProductID = "export.avatar"
        lastError = nil
        exportNote = nil

        Task.detached(priority: .userInitiated) {
            do {
                let written = try PatchRuntime.withFileSystem(
                    game: game,
                    allowKernel: false
                ) { fileSystem -> [String] in
                    guard let product = FreeFireCatalog.products.first(where: {
                        $0.slot == .avatar && FreeFireCatalog.hasPackage(for: $0)
                    }), let url = FreeFireCatalog.packageURL(for: product) else {
                        throw PatchServiceError.packageMissing("avatar")
                    }
                    let package = try PatchPackage.load(from: url)
                    let targets = try PatchService.resolvedRules(
                        package: package,
                        bundleID: game.rawValue,
                        fileSystem: fileSystem
                    )
                    let directory = FileManager.default
                        .urls(for: .documentDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("export", isDirectory: true)
                    try FileManager.default.createDirectory(
                        at: directory,
                        withIntermediateDirectories: true
                    )

                    var names: [String] = []
                    for target in targets {
                        let data = try fileSystem.read(target.relativePath)
                        let name = (target.relativePath as NSString).lastPathComponent + ".bin"
                        try data.write(
                            to: directory.appendingPathComponent(name),
                            options: .atomic
                        )
                        names.append("\(name) (\(data.count) B)")
                        log(
                            "patch: exported \(target.relativePath) — \(data.count) B, "
                                + "sha256 \(PatchPath.sha256Hex(data).prefix(16))",
                            level: .success
                        )
                    }
                    return names
                }

                await MainActor.run {
                    self.busyProductID = nil
                    self.exportNote = written.joined(separator: ", ")
                    log(
                        "ui: avatar asset exported — Files › Discord › export › \(self.exportNote ?? "")",
                        level: .success
                    )
                }
            } catch {
                let message = Self.short(error)
                let full = Self.full(error)
                log("ui: export failed — \(full)", level: .error)
                await MainActor.run {
                    self.busyProductID = nil
                    self.lastError = full
                    self.exportNote = message
                }
            }
        }
    }

    private nonisolated static func full(_ error: Error) -> String {
        (error as? PatchServiceError)?.errorDescription ?? error.localizedDescription
    }

    private nonisolated static func short(_ error: Error) -> String {
        let text = full(error)
        return text.count > 96 ? String(text.prefix(93)) + "…" : text
    }
}
