import Foundation

enum PatchServiceError: LocalizedError {
    case invalidPackage(String)
    case incompatibleAsset(String)
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
        case .incompatibleAsset(let detail):
            return "This patch does not match the installed game asset: \(detail). Update the patch for this game build and try again."
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

/// One file the apply intends to write. A hot-update asset is content
/// addressed, so its patched bytes are stored under a new file name beside the
/// shipped one; `originalPath` stays the path the backup is keyed on.
private struct PlannedWrite {
    let originalPath: String
    var path: String
    let data: Data
    let label: String
    var renamedTo: String?
}

/// One file the apply already wrote, for rollback and for restore.
private struct AppliedWrite {
    let originalPath: String
    var appliedPath: String
    let renamed: Bool
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

    static func resolveCacheToken(fileSystem: PatchFileSystem, bundleID: String) throws -> String {
        // Free Fire ships the hot-update manifest as `Data/Raw/ios/fileinfo`
        // inside the `.app`; older builds also carried a copy next to the
        // bundles, which is why both shapes are tried.
        let candidates = [
            "Documents/Data/Raw/ios/fileinfo",
            "Data/Raw/ios/fileinfo",
            "Documents/Data/Raw/ios/gameassetbundles/cache_res.fileinfo",
            "Data/Raw/ios/gameassetbundles/cache_res.fileinfo",
            "Documents/contentcache/Compulsory/ios/fileinfo"
        ]

        // The gzip-digest column this resolver reads is the same column our
        // CacheManifest.repair rewrites. Reading the live manifest after a
        // repair returns the digest of the patched copy, so the next apply
        // resolves to that copy instead of the shipped asset and skips the
        // collider shift. Prefer the pristine manifest captured before any
        // patching; fall back to the live copy only on a first-ever apply.
        for candidate in candidates {
            guard let data = try? BackupStore.read(
                bundleID: bundleID,
                relativePath: candidate
            ), let token = cacheToken(from: data) else { continue }
            log("patch: cache_res gzip token \(token) (pristine manifest)", level: .trace)
            return token
        }

        for candidate in candidates {
            guard try fileSystem.exists(candidate) else { continue }
            if let token = cacheToken(from: try fileSystem.read(candidate)) {
                log("patch: cache_res gzip token \(token)", level: .trace)
                return token
            }
        }

        throw PatchServiceError.cacheManifestUnavailable
    }

    private static func cacheToken(from data: Data) -> String? {
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        for line in text.components(separatedBy: .newlines) where line.hasPrefix("cache_res,") {
            let fields = line
                .split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard fields.count >= 5 else { continue }

            // `{gz}` has to be the digest the stored file is named after, i.e.
            // the gzip. The row carries two digest/size pairs and their order
            // is not fixed between builds. The gzip's byte count is the smaller
            // of the two, so it names the right pair; the digest is then the
            // column just before that size. Reading a fixed column (the old
            // code used 4) returns the raw digest on a build that stores them
            // the other way round, the exact destination never exists, and the
            // patch only lands by the name-prefix fallback — then the manifest
            // repair writes the wrong column and the game re-downloads.
            var preferred = 1
            if fields.count > 5,
               let first = Int(fields[2]),
               let fifth = Int(fields[5]),
               first > fifth {
                preferred = 4
            }
            for index in [preferred, 1, 4] where index < fields.count {
                if let token = PatchPath.decodeBase64SHA1(fields[index]) {
                    return token
                }
            }
        }
        return nil
    }

    // MARK: - Rule resolution

    static func resolvedRules(
        package: PatchPackage,
        bundleID: String,
        fileSystem: PatchFileSystem
    ) throws -> [(rule: PatchRule, relativePath: String)] {
        let cacheToken = try package.needsCacheToken
            ? resolveCacheToken(fileSystem: fileSystem, bundleID: bundleID)
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

            // `.raw.tmp` is the decompressed scratch copy of an asset. The
            // hot-update tree keeps no such file, and the gzip bundle is what
            // the game reads, so the rule is skipped instead of failing the
            // whole package.
            if destination.hasSuffix(".raw.tmp") {
                let present = (try? fileSystem.exists(destination)) ?? false
                if !present {
                    log(
                        "patch: \(destination) is absent — the gzip asset carries the change",
                        level: .info
                    )
                    continue
                }
            }

            // dope's texture rows use content-addressed names (`_62`, `_66`).
            // Those files are downloaded on demand and are often absent until
            // the matching character is equipped. Like the injector, write the
            // exact name and create it when needed — never spray the payload
            // over unrelated `optionalab_avatar_*` bundles.
            let createsIfMissing = Self.writesInPlace(rule.source)

            let relative: String
            if createsIfMissing,
               let resolved = try? fileSystem.resolveExisting(destination) {
                relative = resolved
            } else if createsIfMissing {
                // A payload file that is not on this build yet: keep the
                // container-relative destination so `apply` can create it.
                if destination.hasPrefix("Documents/") || destination.hasPrefix("Library/") {
                    relative = destination
                } else {
                    let mirrored = destination.hasPrefix("Data/Raw/")
                        ? String(destination.dropFirst("Data/Raw/".count))
                        : destination
                    relative = "Documents/contentcache/Compulsory/" + mirrored
                }
            } else {
                relative = try fileSystem.resolveExisting(destination)
            }
            guard seen.insert(relative).inserted else {
                throw PatchServiceError.invalidPackage("duplicate destination \(relative)")
            }
            result.append((rule, relative))

            // A texture can be loaded from a cached copy under
            // `Library/Caches/<bundle id>` rather than from the contentcache
            // original. Patch every copy of the *same* avatar index; never
            // touch the other characters' bundles.
            if rule.source.hasPrefix("texture_") {
                let logical = ((destination as NSString).lastPathComponent as NSString)
                    .components(separatedBy: ".").first ?? ""
                for note in fileSystem.textureDiagnostics(logical: logical) {
                    log("patch: textura \(logical) — \(note)", level: .info)
                }
                for copy in fileSystem.matchingFiles(prefix: logical) where seen.insert(copy.path).inserted {
                    log(
                        "patch: \(rule.source) also writes cached copy \(copy.path) (\(copy.size) B)",
                        level: .info
                    )
                    result.append((rule, copy.path))
                }
            }
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
        // A patched asset sits under the digest of its own bytes, so applying
        // again would extend an already patched build instead of the shipped
        // one. Put the original back first: the shift always starts from the
        // build the game shipped.
        if let saved = AppliedTargetsStore.load(productID: product.id, bundleID: bundleID),
           !saved.isEmpty {
            log(
                "patch: \(product.packageNames.first ?? product.id) is already applied — restoring the shipped build before writing again",
                level: .info
            )
            try restore(product: product, bundleID: bundleID, package: nil, fileSystem: fileSystem)
        }

        let targets = try resolvedRules(package: package, bundleID: bundleID, fileSystem: fileSystem)
        let blobs = try targets.map {
            try blob(for: $0, package: package, fileSystem: fileSystem)
        }

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
            // The injector creates its Documents payload files when they are
            // not present; a sideloaded game build may or may not have them.
            if Self.writesInPlace(target.rule.source),
               !(try fileSystem.exists(target.relativePath)) {
                log("patch: \(target.relativePath) absent — payload will create it", level: .info)
                continue
            }
            guard try fileSystem.exists(target.relativePath) else {
                throw PatchServiceError.targetMissing(target.relativePath)
            }
        }

        // Capture the exact original once per path. Existing backups are
        // never overwritten, so a second package cannot record modded bytes
        // as the original.
        var shipped: [String: Data] = [:]
        let priorRenames = RenamedTargetsStore.load(productID: product.id, bundleID: bundleID)
        for target in targets {
            // The resolver may pick a previously renamed copy (already
            // patched). Its backup belongs to the original name, so never
            // capture the patched bytes as a new "original".
            let backupKey = priorRenames
                .first(where: { $0.applied == target.relativePath })?.original
                ?? target.relativePath
            if BackupStore.hasBackup(bundleID: bundleID, relativePath: backupKey) {
                log("patch: backup already present for \(backupKey)", level: .trace)
                if let existing = try? BackupStore.read(
                    bundleID: bundleID,
                    relativePath: backupKey
                ) {
                    shipped[target.relativePath] = existing
                }
                continue
            }
            guard let original = try? fileSystem.read(target.relativePath) else {
                // No shipped copy exists (on-demand texture bundle). Applying
                // creates it; restore removes it through CreatedTargetsStore.
                log("patch: no shipped copy for \(backupKey) — will create it", level: .info)
                continue
            }
            shipped[target.relativePath] = original
            let record = try BackupStore.capture(
                original,
                bundleID: bundleID,
                relativePath: backupKey
            )
            log(
                "patch: captured \(PatchPath.prettyBytes(record.size)) original for \(backupKey)",
                level: .info
            )
        }

        // The hot-update tree is content addressed: the file name carries the
        // SHA-1 of the bytes and the category manifest records the same digest.
        // A patched asset therefore has to be stored under the name of its own
        // bytes, with the manifest moved along, or Free Fire decides the cached
        // file is stale and quietly downloads the original back over it.
        var plans: [PlannedWrite] = []
        var manifests: [CacheManifest.Replacement] = []
        for (index, target) in targets.enumerated() {
            let originalPath = target.relativePath
            let blob = blobs[index]
            let original = shipped[originalPath]
            let current = (try? fileSystem.read(originalPath)) ?? original
            var plan = PlannedWrite(
                originalPath: originalPath,
                path: originalPath,
                data: blob,
                label: target.rule.source,
                renamedTo: nil
            )

            // The working sideloaded injector overwrites `assetindexer` in
            // place and never renames it or edits `fileinfo`. Free Fire resolves
            // that asset by its original name, so a renamed copy plus a rewritten
            // row is ignored even though the bytes verify on disk. The bone
            // rename package follows that proven route: same name, new bytes.
            if !Self.writesInPlace(target.rule.source),
               originalPath.contains("/contentcache/"), let current, current != blob {
                let fileName = (originalPath as NSString).lastPathComponent
                let directory = (originalPath as NSString).deletingLastPathComponent
                if let newName = HotAssetName.name(for: blob, replacing: fileName, current: current) {
                    plan.path = directory + "/" + newName
                    plan.renamedTo = newName
                    log(
                        "patch: \(fileName) is named after its own content — the patched asset is stored as \(newName), original kept",
                        level: .info
                    )
                } else {
                    log(
                        "patch: \(fileName) does not carry its content digest — keeping the shipped name",
                        level: .warning
                    )
                }
                if let replacement = try CacheManifest.repair(
                    asset: originalPath,
                    current: current,
                    shipped: original,
                    patched: blob,
                    patchedStored: blob,
                    patchedCounterpart: target.relativePath.contains("/cache_res")
                        ? (GzipData.decompress(blob) ?? blob)
                        : GzipData.compress(blob),
                    renamedFrom: plan.renamedTo == nil ? nil : fileName,
                    renamedTo: plan.renamedTo,
                    fileSystem: fileSystem
                ) {
                    manifests.append(replacement)
                }
            }
            plans.append(plan)
        }
        for manifest in manifests where !BackupStore.hasBackup(bundleID: bundleID, relativePath: manifest.path) {
            let original = try fileSystem.read(manifest.path)
            _ = try BackupStore.capture(
                original,
                bundleID: bundleID,
                relativePath: manifest.path
            )
            log("patch: captured original for \(manifest.path)", level: .info)
        }

        var attempted: [AppliedWrite] = []
        var createdPaths: [String] = []
        do {
            for plan in plans {
                var applied = AppliedWrite(
                    originalPath: plan.originalPath,
                    appliedPath: plan.path,
                    renamed: plan.renamedTo != nil
                )
                attempted.append(applied)
                // Keep the shipped file in place. Free Fire looks up the
                // original content-addressed name on every launch; deleting
                // it made the game download the clean copy back over the
                // patch. The manifest now points at this copy, so the shipped
                // bytes left on disk are never read.
                let isCopy = plan.renamedTo != nil
                let note = isCopy
                    ? " (copy; original \((plan.originalPath as NSString).lastPathComponent) kept)"
                    : ""
                log("patch: writing \(plan.label) -> \(plan.path)\(note) [\(fileSystem.backendName)]")
                let targetExists = try fileSystem.exists(plan.path)
                if (isCopy || Self.writesInPlace(plan.label)) && !targetExists {
                    // A copy or an on-demand texture bundle does not exist yet;
                    // `write` resolves through the discovery map and refuses a
                    // missing target. `create` writes the new file in place.
                    try fileSystem.create(plan.data, at: plan.path)
                    createdPaths.append(plan.path)
                } else {
                    try fileSystem.write(plan.data, to: plan.path)
                }

                let readBack = try fileSystem.read(applied.appliedPath)
                guard readBack == plan.data else {
                    throw PatchServiceError.verificationFailed(applied.appliedPath)
                }
                log("patch: verified \(applied.appliedPath)", level: .success)
            }
            for manifest in manifests {
                attempted.append(
                    AppliedWrite(originalPath: manifest.path, appliedPath: manifest.path, renamed: false)
                )
                log("patch: updating \(manifest.path) — \(manifest.summary) [\(fileSystem.backendName)]")
                try fileSystem.write(manifest.data, to: manifest.path)
                let readBack = try fileSystem.read(manifest.path)
                guard readBack == manifest.data else {
                    throw PatchServiceError.verificationFailed(manifest.path)
                }
                log("patch: verified \(manifest.path)", level: .success)
            }
        } catch {
            log("patch: write failed — rolling back \(attempted.count) target(s)", level: .error)
            rollback(
                writes: attempted,
                bundleID: bundleID,
                fileSystem: fileSystem
            )
            appendLedger(
                action: "apply",
                product: product,
                package: package,
                bundleID: bundleID,
                backend: fileSystem.backendName,
                paths: attempted.map { $0.originalPath },
                result: "failed",
                message: error.localizedDescription
            )
            throw error
        }

        // Post-write verification: Free Fire (or the system) can overwrite
        // patched bytes right after we release them. Re-apply up to 3 times
        // if anything came back as the shipped original.
        //
        // Verify the bytes we actually wrote, under the name we actually
        // wrote them. A renamed asset no longer exists under its original
        // name, so reading the original path reports a false "reverted" and
        // starts a restore loop with a name that has no backup.
        var written: [(path: String, expected: Data)] = []
        for plan in plans {
            written.append((plan.path, plan.data))
        }
        for manifest in manifests {
            written.append((manifest.path, manifest.data))
        }
        var verifyAttempt = 0
        while verifyAttempt < 3 {
            verifyAttempt += 1
            var reverted: [String] = []
            for item in written {
                guard let current = try? fileSystem.read(item.path),
                      current == item.expected else {
                    reverted.append(item.path)
                    continue
                }
            }
            guard !reverted.isEmpty else { break }
            log(
                "patch: \(product.packageNames.first ?? product.id) — \(reverted.count) file(s) reverted by the game, re-applying (\(verifyAttempt)/3)",
                level: .warning
            )
            try restore(product: product, bundleID: bundleID, package: package, fileSystem: fileSystem)
            return try apply(package: package, product: product, bundleID: bundleID, fileSystem: fileSystem)
        }

        RenamedTargetsStore.save(
            attempted.filter(\.renamed).map {
                RenamedTarget(original: $0.originalPath, applied: $0.appliedPath)
            },
            productID: product.id,
            bundleID: bundleID
        )
        // Record the manifest rows this apply wrote. Status compares them with
        // the live `fileinfo` instead of guessing from a file name, and restore
        // puts back only these rows so a second patch's row survives.
        let manifestRows = manifests.flatMap { manifest in
            manifest.rows.map {
                ManifestRowRecord(
                    manifest: manifest.path,
                    key: $0.key,
                    original: $0.original,
                    patched: $0.patched
                )
            }
        }
        // A repair that found the manifest already patched returns no rows; do
        // not drop the rows a previous apply recorded, or status loses its only
        // way to tell a live rewrite from its own edit.
        if !manifestRows.isEmpty {
            ManifestRowsStore.save(manifestRows, productID: product.id, bundleID: bundleID)
        }
        let paths = targets.map { $0.relativePath } + manifests.map { $0.path }
        AppliedTargetsStore.save(paths, productID: product.id, bundleID: bundleID)
        CreatedTargetsStore.save(createdPaths, productID: product.id, bundleID: bundleID)
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

    /// Packages whose bytes go over the existing hot-update file without a
    /// rename or a `fileinfo` edit. The sideloaded injector whose payload was
    /// recovered in `Payload-2/InjectorApp.app` overwrites `assetindexer` in
    /// place on iOS 27.0.1; Free Fire resolves that asset by its original name,
    /// so a renamed copy plus a rewritten manifest row is ignored.
    private static func writesInPlace(_ source: String) -> Bool {
        source == "asset_neck.raw"
            || source.hasPrefix("proxy_")
            || source.hasPrefix("dope_")
            || source.hasPrefix("texture_")
    }

    /// The blob to write for one resolved target. The hot-update trees store an
    /// asset as one raw file, while a package ships a gzip blob for the signed
    /// build and the raw one for the scratch copy, so the raw blob is used
    /// there. Because that file belongs to a newer build than the package was
    /// made from, its own bytes are kept and only the changed floats are
    /// shifted in; the packaged blob is written whole only when the file is
    /// byte-identical to the shipped base.
    private static func blob(
        for target: (rule: PatchRule, relativePath: String),
        package: PatchPackage,
        fileSystem: PatchFileSystem
    ) throws -> Data {
        guard let source = package.files[target.rule.source] else {
            throw PatchServiceError.invalidPackage("missing source \(target.rule.source)")
        }
        guard target.relativePath.contains("/contentcache/") else {
            return source
        }

        let rawName = (target.rule.source as NSString).deletingPathExtension + ".raw"
        guard let raw = package.files[rawName] ?? package.files[target.rule.source],
              raw.count != 0,
              let device = try? fileSystem.read(target.relativePath) else {
            return source
        }

        // cache_res ships as a complete rebuilt UnityFS bundle: `cache_res_raw.bin`
        // is the exact asset and `cache_res_mod.bin` is its gzip. The old path
        // re-gzipped the device copy instead, which discarded every geometry
        // edit the package carries and forced all 37 hit helpers to HEAD — the
        // head capsule never moved, so a neck shot still resolved to TORSO.
        // Write the packaged bytes verbatim and let CacheManifest describe both
        // the raw and the gzip digest of the file the game will load.
        if target.relativePath.contains("/cache_res") {
            if let packagedRaw = package.files["cache_res_raw.bin"]
                ?? package.files.first(where: { $0.key.hasSuffix("_raw.bin") })?.value {
                log(
                    "patch: \(target.relativePath) — packaged cache_res bundle, \(packagedRaw.count) B raw",
                    level: .info
                )
            }
            return source
        }

        // These packages carry complete hot-update avatar blobs and must be
        // written over the existing file, never diffed or recompressed. The
        // working injector on iOS 27 does exactly this.
        if Self.writesInPlace(target.rule.source) {
            log(
                "patch: \(target.relativePath) — writing \(source.count) B in place",
                level: .info
            )
            return source
        }

        guard let base = AssetShift.baseData(forByteCount: raw.count) ?? AssetShift.baseData() else {
            log(
                "patch: shipped avatar base is missing — writing \(target.rule.source) as is",
                level: .warning
            )
            return source
        }
        if device == base || device == raw {
            return raw
        }
        if let shifted = AssetShift.apply(patched: raw, to: device, base: base) {
            return shifted
        }
        throw PatchServiceError.incompatibleAsset(
            "\(target.relativePath) is a different build and the edited fields could not be located safely"
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
            paths = try resolvedRules(package: package, bundleID: bundleID, fileSystem: fileSystem)
                .map { $0.relativePath }
        } else {
            throw PatchServiceError.packageMissing(product.packageNames.first ?? product.id)
        }

        // A saved target may be the renamed name; its backup is keyed by the
        // original name. Resolve that mapping before checking/restoring.
        let renames = RenamedTargetsStore.load(productID: product.id, bundleID: bundleID)
        func backupKey(for path: String) -> String {
            if BackupStore.hasBackup(bundleID: bundleID, relativePath: path) { return path }
            return renames.first(where: { $0.applied == path })?.original ?? path
        }

        // A texture bundle that was not on the device before was created by
        // the injector; there is no shipped copy to put back. Delete it on
        // restore instead of demanding a backup that can never exist.
        let created = Set(CreatedTargetsStore.load(productID: product.id, bundleID: bundleID))

        // Preflight: never restore half of a group.
        for path in paths where !created.contains(path) && !BackupStore.hasBackup(
            bundleID: bundleID,
            relativePath: backupKey(for: path)
        ) {
            throw PatchServiceError.missingBackup(path)
        }

        // A patched asset lives under the name of its own bytes, so the shipped
        // name is gone. Drop the renamed copy first, or the tree would keep both
        // and the resolver would see two candidates for one asset.
        for rename in RenamedTargetsStore.load(productID: product.id, bundleID: bundleID)
        where rename.applied != rename.original {
            guard (try? fileSystem.exists(rename.applied)) == true else { continue }
            try? fileSystem.delete(rename.applied)
            log("patch: removed renamed copy \(rename.applied)", level: .info)
        }

        var restored: [String] = []
        do {
            let recorded = ManifestRowsStore.load(productID: product.id, bundleID: bundleID)
            for path in paths {
                // Several patches share one `fileinfo`. Writing the backup back
                // wholesale erases every other patch's row, so the manifest is
                // restored row by row whenever this app recorded its own rows.
                if (path as NSString).lastPathComponent == "fileinfo",
                   recorded.contains(where: { $0.manifest == path }) {
                    let rows = recorded
                        .filter { $0.manifest == path }
                        .map { CacheManifest.RowChange(key: $0.key, original: $0.original, patched: $0.patched) }
                    _ = try? CacheManifest.restoreRows(rows, in: path, fileSystem: fileSystem)
                    log("patch: restored the \(rows.count) row(s) this patch wrote in \(path)", level: .info)
                    restored.append(path)
                    continue
                }
                if created.contains(path) {
                    if (try? fileSystem.exists(path)) == true {
                        try fileSystem.delete(path)
                        log("patch: removed created file \(path)", level: .info)
                    }
                    restored.append(path)
                    continue
                }
                let original = try BackupStore.read(
                    bundleID: bundleID,
                    relativePath: backupKey(for: path)
                )
                log("patch: restoring \(path) [\(fileSystem.backendName)]")
                if (try? fileSystem.exists(path)) == true {
                    try fileSystem.write(original, to: path)
                } else {
                    try fileSystem.create(original, at: path)
                }
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
        CreatedTargetsStore.clear(productID: product.id, bundleID: bundleID)
        RenamedTargetsStore.clear(productID: product.id, bundleID: bundleID)
        ManifestRowsStore.clear(productID: product.id, bundleID: bundleID)
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
        // A hot-update asset is not replaced with the packaged bytes: only the
        // changed floats are shifted into the build the device already has, so
        // a byte comparison against the package can never match after a
        // successful apply. The recorded targets are authoritative, and they
        // still count only while the file really differs from its backup.
        if let applied = AppliedTargetsStore.load(productID: product.id, bundleID: bundleID),
           !applied.isEmpty {
            let inPlace = appliedStillInPlace(
                applied,
                productID: product.id,
                bundleID: bundleID,
                fileSystem: fileSystem
            )
            log(
                inPlace
                    ? "patch: \(product.id) — the patched asset is still on disk"
                    : "patch: \(product.id) — the game replaced the patched asset or its manifest",
                level: inPlace ? .success : .warning
            )
            if inPlace { return .loaded }
            return .partial
        }
        do {
            let package = try PatchPackage.load(from: url)
            let targets = try resolvedRules(package: package, bundleID: bundleID, fileSystem: fileSystem)
            var matching = 0
            for target in targets {
                guard let source = package.files[target.rule.source] else { continue }
                // A dope payload may not exist yet on this build; that is
                // simply "not loaded", not an unavailable backend.
                if let current = try? fileSystem.read(target.relativePath),
                   PatchPath.sha256Hex(current) == PatchPath.sha256Hex(source) {
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

    private static func appliedStillInPlace(
        _ paths: [String],
        productID: String,
        bundleID: String,
        fileSystem: PatchFileSystem
    ) -> Bool {
        let renames = RenamedTargetsStore.load(productID: productID, bundleID: bundleID)
        let renamedOriginals = Set(renames.map { $0.original })
        var checked = 0

        for path in paths where !renamedOriginals.contains(path) {
            guard let relative = try? PatchPath.safeRelative(path),
                  let current = try? fileSystem.read(relative),
                  let original = try? BackupStore.read(
                    bundleID: bundleID,
                    relativePath: relative
                  ) else {
                return false
            }
            if current == original { return false }
            checked += 1
        }

        // The renamed copy is the asset itself: it still counts only while it
        // exists, still differs from the shipped bytes, and the manifest still
        // points at it. Free Fire re-downloads its own copy on launch and
        // rewrites `fileinfo`, so a file that merely exists is not enough.
        //
        // Compare the rows this app wrote, not the file-name token: a manifest
        // that records only digests never contains the token, and reading that
        // as "replaced" made every status pass restore and rewrite the asset.
        let recorded = ManifestRowsStore.load(productID: productID, bundleID: bundleID)
        for manifest in Set(recorded.map { $0.manifest }) {
            let rows = recorded
                .filter { $0.manifest == manifest }
                .map { CacheManifest.RowChange(key: $0.key, original: $0.original, patched: $0.patched) }
            if !CacheManifest.rowsIntact(rows, in: manifest, fileSystem: fileSystem) {
                return false
            }
        }

        for rename in renames {
            guard let applied = try? fileSystem.read(rename.applied),
                  let original = try? BackupStore.read(
                    bundleID: bundleID,
                    relativePath: rename.original
                  ) else {
                return false
            }
            if applied == original { return false }
            checked += 1
        }
        return checked > 0
    }

    private static func rollback(
        writes: [AppliedWrite],
        bundleID: String,
        fileSystem: PatchFileSystem
    ) {
        for write in writes.reversed() {
            guard BackupStore.hasBackup(bundleID: bundleID, relativePath: write.originalPath) else {
                log("patch: rollback has no backup for \(write.originalPath)", level: .warning)
                continue
            }
            do {
                let original = try BackupStore.read(bundleID: bundleID, relativePath: write.originalPath)
                if write.renamed {
                    if (try? fileSystem.exists(write.appliedPath)) == true {
                        try? fileSystem.delete(write.appliedPath)
                    }
                    try fileSystem.create(original, at: write.originalPath)
                } else {
                    try fileSystem.write(original, to: write.originalPath)
                }
                let readBack = try fileSystem.read(write.originalPath)
                if readBack == original {
                    log("patch: rolled back \(write.originalPath)", level: .success)
                } else {
                    log("patch: rollback verification failed for \(write.originalPath)", level: .error)
                }
            } catch {
                log("patch: rollback failed for \(write.originalPath) — \(error.localizedDescription)", level: .error)
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
