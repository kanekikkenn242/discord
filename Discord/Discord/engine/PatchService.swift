import Foundation

enum PatchServiceError: LocalizedError {
    case invalidPackage(String)
    case unsupportedVersion(Int)
    case decryptionFailed(String)
    case digestMismatch(expected: String, actual: String, file: String)
    case unsafePath(String)
    case targetMissing(String)
    case verificationFailed(String)
    case missingBackup(String)
    case noContainer(String)
    case noAccess(String)
    case pairingRequired
    case cacheManifestUnavailable
    case notActivated
    case packageMissing(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidPackage(let detail):
            return "Invalid .3105 package: \(detail)"
        case .unsupportedVersion(let version):
            return "Unsupported .3105 version \(version) (only v1 is supported)."
        case .decryptionFailed(let detail):
            return "Could not decrypt the package: \(detail)."
        case .digestMismatch(let expected, let actual, let file):
            return "Digest mismatch for \(file): expected \(expected.prefix(12))…, got \(actual.prefix(12))…."
        case .unsafePath(let path):
            return "Refusing unsafe path \(path)."
        case .targetMissing(let path):
            return "Target does not exist: \(path). The patch never creates missing files."
        case .verificationFailed(let path):
            return "Written file did not match the package bytes: \(path)."
        case .missingBackup(let path):
            return "No byte-exact backup for \(path). Refusing to pretend the original is back."
        case .noContainer(let bundleID):
            return "Could not resolve the data container for \(bundleID)."
        case .noAccess(let detail):
            return "No container access backend is available: \(detail)."
        case .pairingRequired:
            return "Pairing is not configured. Import a pairing file or pair this iPhone first."
        case .cacheManifestUnavailable:
            return "cache_res.fileinfo is missing or has no gzip SHA-1, so the cache path cannot be resolved safely."
        case .notActivated:
            return "Activate a key before loading patches."
        case .packageMissing(let name):
            return "Package \(name).3105 is not installed in this build."
        case .unknown(let detail):
            return detail
        }
    }
}

struct PatchApplyResult {
    let productID: String
    let packageName: String
    let bundleID: String
    let backend: String
    let paths: [String]
}

enum PatchProductStatus: Equatable {
    case packageMissing
    case loaded
    case notLoaded
    case partial
    case unavailable(String)

    var isLoaded: Bool { self == .loaded }
    var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .packageMissing: return "Package missing"
        case .loaded: return "Loaded"
        case .notLoaded: return "Not loaded"
        case .partial: return "Partial"
        case .unavailable(let detail): return detail
        }
    }
}

struct PatchStatusRow {
    let product: PatchProduct
    let status: PatchProductStatus
}

enum PatchService {
    // MARK: - Cache token

    static func resolveCacheToken(fileSystem: PatchFileSystem) throws -> String {
        // Free Fire ships the hot-update manifest as `Data/Raw/ios/fileinfo`
        // inside the `.app`; older builds also carried a copy next to the
        // bundles, which is why both shapes are tried.
        let candidates = [
            "Documents/Data/Raw/ios/fileinfo",
            "Data/Raw/ios/fileinfo",
            "Documents/Data/Raw/ios/gameassetbundles/cache_res.fileinfo",
            "Data/Raw/ios/gameassetbundles/cache_res.fileinfo"
        ]

        for candidate in candidates {
            guard try fileSystem.exists(candidate) else { continue }
            let data = try fileSystem.read(candidate)
            let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? ""
            for line in text.components(separatedBy: .newlines) {
                let fields = line
                    .split(separator: ",", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                guard fields.count >= 5, !fields[4].isEmpty else { continue }
                if let token = PatchPath.decodeBase64SHA1(fields[4]) {
                    log("patch: cache_res gzip token \(token)", level: .trace)
                    return token
                }
            }
        }

        throw PatchServiceError.cacheManifestUnavailable
    }

    // MARK: - Rule resolution

    static func resolvedRules(
        package: PatchPackage,
        fileSystem: PatchFileSystem
    ) throws -> [(rule: PatchRule, relativePath: String)] {
        let cacheToken = try package.needsCacheToken
            ? resolveCacheToken(fileSystem: fileSystem)
            : nil

        var result: [(rule: PatchRule, relativePath: String)] = []
        var seen = Set<String>()

        for rule in package.rules {
            var destination = rule.destination
            if destination.contains("{gz}") {
                guard let cacheToken else {
                    throw PatchServiceError.cacheManifestUnavailable
                }
                destination = destination.replacingOccurrences(of: "{gz}", with: cacheToken)
            }

            let relative = try fileSystem.resolveExisting(destination)
            guard seen.insert(relative).inserted else {
                throw PatchServiceError.invalidPackage("duplicate destination \(relative)")
            }
            result.append((rule, relative))
        }
        return result
    }

    // MARK: - Apply

    static func apply(
        package: PatchPackage,
        product: PatchProduct,
        bundleID: String,
        fileSystem: PatchFileSystem
    ) throws -> PatchApplyResult {
        let targets = try resolvedRules(package: package, fileSystem: fileSystem)

        // Preflight: every source blob must match its digest and every target
        // must already exist. Nothing is written before all checks pass.
        for target in targets {
            guard let source = package.files[target.rule.source] else {
                throw PatchServiceError.invalidPackage("missing source \(target.rule.source)")
            }
            let expected = package.digests[target.rule.source] ?? ""
            let actual = PatchPath.sha256Hex(source)
            guard expected == actual else {
                throw PatchServiceError.digestMismatch(
                    expected: expected,
                    actual: actual,
                    file: target.rule.source
                )
            }
            guard try fileSystem.exists(target.relativePath) else {
                throw PatchServiceError.targetMissing(target.relativePath)
            }
        }

        // Capture the exact original once per path. Existing backups are
        // never overwritten, so a second package cannot record modded bytes
        // as the original.
        for target in targets {
            if BackupStore.hasBackup(bundleID: bundleID, relativePath: target.relativePath) {
                log("patch: backup already present for \(target.relativePath)", level: .trace)
                continue
            }
            let original = try fileSystem.read(target.relativePath)
            let record = try BackupStore.capture(
                original,
                bundleID: bundleID,
                relativePath: target.relativePath
            )
            log(
                "patch: captured \(PatchPath.prettyBytes(record.size)) original for \(target.relativePath)",
                level: .info
            )
        }

        var attempted: [String] = []
        do {
            for target in targets {
                guard let source = package.files[target.rule.source] else {
                    throw PatchServiceError.invalidPackage("missing source \(target.rule.source)")
                }
                attempted.append(target.relativePath)
                log("patch: writing \(target.rule.source) -> \(target.relativePath) [\(fileSystem.backendName)]")
                try fileSystem.write(source, to: target.relativePath)

                let readBack = try fileSystem.read(target.relativePath)
                guard readBack == source else {
                    throw PatchServiceError.verificationFailed(target.relativePath)
                }
                log("patch: verified \(target.relativePath)", level: .success)
            }
        } catch {
            log("patch: write failed — rolling back \(attempted.count) target(s)", level: .error)
            rollback(
                paths: attempted,
                bundleID: bundleID,
                fileSystem: fileSystem
            )
            appendLedger(
                action: "apply",
                product: product,
                package: package,
                bundleID: bundleID,
                backend: fileSystem.backendName,
                paths: attempted,
                result: "failed",
                message: error.localizedDescription
            )
            throw error
        }

        let paths = targets.map { $0.relativePath }
        AppliedTargetsStore.save(paths, productID: product.id, bundleID: bundleID)
        appendLedger(
            action: "apply",
            product: product,
            package: package,
            bundleID: bundleID,
            backend: fileSystem.backendName,
            paths: paths,
            result: "success",
            message: "Applied \(paths.count) file(s)"
        )
        return PatchApplyResult(
            productID: product.id,
            packageName: package.displayName,
            bundleID: bundleID,
            backend: fileSystem.backendName,
            paths: paths
        )
    }

    // MARK: - Restore

    @discardableResult
    static func restore(
        product: PatchProduct,
        bundleID: String,
        package: PatchPackage?,
        fileSystem: PatchFileSystem
    ) throws -> [String] {
        let paths: [String]
        if let saved = AppliedTargetsStore.load(productID: product.id, bundleID: bundleID),
           !saved.isEmpty {
            paths = try saved.map { try PatchPath.safeRelative($0) }
        } else if let package {
            paths = try resolvedRules(package: package, fileSystem: fileSystem)
                .map { $0.relativePath }
        } else {
            throw PatchServiceError.packageMissing(product.packageNames.first ?? product.id)
        }

        // Preflight: never restore half of a group.
        for path in paths where !BackupStore.hasBackup(bundleID: bundleID, relativePath: path) {
            throw PatchServiceError.missingBackup(path)
        }

        var restored: [String] = []
        do {
            for path in paths {
                let original = try BackupStore.read(bundleID: bundleID, relativePath: path)
                log("patch: restoring \(path) [\(fileSystem.backendName)]")
                try fileSystem.write(original, to: path)
                let readBack = try fileSystem.read(path)
                guard readBack == original else {
                    throw PatchServiceError.verificationFailed(path)
                }
                restored.append(path)
                log("patch: restored \(path)", level: .success)
            }
        } catch {
            log("patch: restore stopped after \(restored.count) file(s): \(error.localizedDescription)", level: .error)
            appendLedger(
                action: "restore",
                product: product,
                package: package,
                bundleID: bundleID,
                backend: fileSystem.backendName,
                paths: paths,
                result: "failed",
                message: error.localizedDescription
            )
            throw error
        }

        AppliedTargetsStore.clear(productID: product.id, bundleID: bundleID)
        appendLedger(
            action: "restore",
            product: product,
            package: package,
            bundleID: bundleID,
            backend: fileSystem.backendName,
            paths: paths,
            result: "success",
            message: "Restored \(restored.count) file(s)"
        )
        return restored
    }

    // MARK: - Status

    static func status(
        product: PatchProduct,
        bundleID: String,
        fileSystem: PatchFileSystem
    ) -> PatchProductStatus {
        guard let url = FreeFireCatalog.packageURL(for: product) else {
            return .packageMissing
        }
        do {
            let package = try PatchPackage.load(from: url)
            let targets = try resolvedRules(package: package, fileSystem: fileSystem)
            var matching = 0
            for target in targets {
                guard let source = package.files[target.rule.source] else { continue }
                let current = try fileSystem.read(target.relativePath)
                if PatchPath.sha256Hex(current) == PatchPath.sha256Hex(source) {
                    matching += 1
                }
            }
            if matching == targets.count { return .loaded }
            if matching == 0 { return .notLoaded }
            return .partial
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private static func rollback(
        paths: [String],
        bundleID: String,
        fileSystem: PatchFileSystem
    ) {
        for path in paths.reversed() {
            guard BackupStore.hasBackup(bundleID: bundleID, relativePath: path) else {
                log("patch: rollback has no backup for \(path)", level: .warning)
                continue
            }
            do {
                let original = try BackupStore.read(bundleID: bundleID, relativePath: path)
                try fileSystem.write(original, to: path)
                let readBack = try fileSystem.read(path)
                if readBack == original {
                    log("patch: rolled back \(path)", level: .success)
                } else {
                    log("patch: rollback verification failed for \(path)", level: .error)
                }
            } catch {
                log("patch: rollback failed for \(path) — \(error.localizedDescription)", level: .error)
            }
        }
    }

    private static func appendLedger(
        action: String,
        product: PatchProduct,
        package: PatchPackage?,
        bundleID: String,
        backend: String,
        paths: [String],
        result: String,
        message: String
    ) {
        BackupStore.appendLedger(
            LedgerEntry(
                date: Date(),
                action: action,
                productID: product.id,
                packageName: package?.displayName ?? product.packageNames.first ?? product.id,
                bundleID: bundleID,
                backend: backend,
                paths: paths,
                result: result,
                message: message
            )
        )
    }
}
