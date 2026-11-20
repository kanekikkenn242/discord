import Foundation
import Combine

@MainActor
final class PatchController: ObservableObject {
    @Published private(set) var statuses: [String: PatchProductStatus] = [:]
    @Published private(set) var busyProductID: String?
    @Published private(set) var backend: String = "not available"
    @Published private(set) var lastError: String?

    private var refreshInFlight = false

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
        refreshInFlight = true

        let products = FreeFireCatalog.products
        Task.detached(priority: .userInitiated) {
            var resolved: [String: PatchProductStatus] = [:]
            for product in products where !FreeFireCatalog.hasPackage(for: product) {
                resolved[product.id] = .packageMissing
            }

            var backendName = PatchRuntime.backendDescription(game: game)

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
                    return (map, fileSystem.backendName)
                }
                resolved.merge(outcome.0) { _, new in new }
                backendName = outcome.1
            } catch {
                let message = Self.short(error)
                let full = Self.full(error)
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

    private nonisolated static func full(_ error: Error) -> String {
        (error as? PatchServiceError)?.errorDescription ?? error.localizedDescription
    }

    private nonisolated static func short(_ error: Error) -> String {
        let text = full(error)
        return text.count > 96 ? String(text.prefix(93)) + "…" : text
    }
}
