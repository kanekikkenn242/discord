import Foundation
import Darwin

struct ContainerMetadata {
    let bundleID: String
    let displayName: String
}

enum ContainerStore {
    static let appDataRoot = "/var/mobile/Containers/Data/Application"
    static let appBundleRoot = "/var/containers/Bundle/Application"

    /// Last MCM refusal together with the identity this build is signed with.
    /// An install route that rewrites the bundle identifier (personal/free
    /// signing) makes the MCM lookup impossible, and the detail is the only
    /// place that shows it, so it is carried up to the patch error.
    private(set) static var lastMCMFailure: String?

    static var diagnosticSuffix: String {
        guard let failure = lastMCMFailure else { return "" }
        return "\nContainer check: \(failure)"
    }

    static func resolveAppContainerPath(bundleID: String) -> String? {
        guard (try? PatchPath.safeRelative(bundleID)) == bundleID else {
            return nil
        }

        var lookupError: NSString?
        if let path = MCMActivateContainerPath(2, bundleID, false, &lookupError),
           isApplicationContainerPath(path) {
            lastMCMFailure = nil
            log("patch: MCM resolved \(bundleID)")
            return PatchPath.canonicalContainerPath(path)
        }

        let detail = lookupError.map(String.init) ?? "unavailable"
        lastMCMFailure = "\(detail) [app id \(AppInfo.bundleID)]"
        log(
            "patch: MCM could not resolve \(bundleID), detail=\(detail), app id=\(AppInfo.bundleID)",
            level: .warning
        )

        if let scanned = resolveByMetadataScan(bundleID: bundleID) {
            lastMCMFailure = nil
            log("patch: metadata scan resolved \(bundleID)")
            return scanned
        }

        if let escaped = resolveByAppGroupEscape(bundleID: bundleID) {
            lastMCMFailure = nil
            log("patch: worse_query resolved \(bundleID)")
            return escaped
        }

        if MCMAppGroupIdentifier() == nil {
            lastMCMFailure = (lastMCMFailure ?? "unavailable")
                + " — this signature has no com.apple.security.application-groups"
                + " entitlement, so the free worse_query route cannot run"
        }
        return nil
    }

    static let bundleCachePrefix = "container.bundle."

    /// `<bundle container>/<Name>.app`. Free Fire's shipped asset tree
    /// (`Data/Raw/ios/...`) lives here, so asset packages need this root in
    /// addition to the data container's `Documents`.
    ///
    /// A re-signed build gets `lookup denied` for MCM class 1, so the bundle
    /// root is enumerated through the same worse_query grant the data
    /// containers use. Only a `.app` whose `CFBundleIdentifier` matches is
    /// accepted, so a neighbouring app is never patched by mistake.
    static func resolveApplicationBundlePath(bundleID: String) -> String? {
        // The cached path is validated with a fresh grant, never trusted
        // blindly: an app update moves the bundle container.
        if let cached = UserDefaults.standard.string(forKey: bundleCachePrefix + bundleID),
           cached.hasPrefix(appBundleRoot + "/"),
           activateSandboxAccess(to: cached),
           bundleIdentifier(atBundlePath: cached) == bundleID {
            return cached
        }

        var lookupError: NSString?
        if let raw = MCMContainerPathForIdentifier(1, bundleID, false, &lookupError) {
            let container = PatchPath.canonicalContainerPath(raw)
            if container.hasPrefix(appBundleRoot + "/") {
                var readable = false
                if let app = appBundle(
                    in: container,
                    bundleID: bundleID,
                    activating: false,
                    anyReadable: &readable
                ) {
                    rememberBundle(app, bundleID: bundleID)
                    return app
                }
            }
        } else {
            log(
                "patch: MCM could not resolve the bundle container for \(bundleID), detail="
                    + (lookupError.map(String.init) ?? "unavailable"),
                level: .trace
            )
        }

        guard activateSandboxAccess(to: appBundleRoot) else {
            log(
                "patch: no sandbox access to \(appBundleRoot) — asset targets stay unresolved",
                level: .warning
            )
            return nil
        }

        let containers = enumerateDirectories(path: appBundleRoot)
            .map { PatchPath.canonicalContainerPath($0) }
            .filter {
                $0.hasPrefix(appBundleRoot + "/")
                    && UUID(uuidString: ($0 as NSString).lastPathComponent) != nil
            }

        // Pass 1 reads each Info.plist through the root grant only; a grant on
        // every bundle in turn would cost seconds. Pass 2 is the fallback for
        // devices where that read is denied.
        var plistsReadable = false
        for container in containers {
            if let app = appBundle(
                in: container,
                bundleID: bundleID,
                activating: false,
                anyReadable: &plistsReadable
            ) {
                rememberBundle(app, bundleID: bundleID)
                return app
            }
        }
        if !plistsReadable {
            for container in containers {
                var readable = false
                if let app = appBundle(
                    in: container,
                    bundleID: bundleID,
                    activating: true,
                    anyReadable: &readable
                ) {
                    rememberBundle(app, bundleID: bundleID)
                    return app
                }
            }
        }

        log("patch: no .app for \(bundleID) inside \(appBundleRoot)", level: .warning)
        return nil
    }

    /// The bundle volume is closed on 27.x (class 7 and class 13 both answer
    /// `-3` from containermanagerd), so the data container is the only tree a
    /// package can live in. It never ships `Data/Raw` itself, and the game
    /// decides where it reads hot-update assets, so its layout has to be in
    /// the log: that listing is what says whether an asset target exists at
    /// all or the package is pointed at a path this build never reads.
    private static var didDescribeDataContainer = false

    static func logDataContainerLayout(_ root: String) {
        guard !didDescribeDataContainer else { return }
        didDescribeDataContainer = true
        let fileManager = FileManager.default
        func listing(_ relative: String) -> String? {
            let path = relative.isEmpty
                ? root
                : (root as NSString).appendingPathComponent(relative)
            guard fileManager.fileExists(atPath: path),
                  let names = try? fileManager.contentsOfDirectory(atPath: path) else {
                return nil
            }
            if names.isEmpty { return "<empty>" }
            let limit = 14
            let shown = names.sorted().prefix(limit).joined(separator: ", ")
            return names.count > limit ? shown + " …(\(names.count))" : shown
        }
        var notes: [String] = []
        for relative in [
            "",
            "Documents",
            "Documents/Data",
            "Documents/Data/Raw",
            "Documents/Data/Raw/ios",
            "Documents/Data/Raw/ios/gameassetbundles",
            "Library",
            "Library/Caches",
            "Library/Application Support"
        ] {
            guard let note = listing(relative) else { continue }
            notes.append("\(relative.isEmpty ? "root" : relative): \(note)")
        }
        log(
            "patch: data container layout — "
                + (notes.isEmpty ? "nothing is readable" : notes.joined(separator: " | ")),
            level: .info
        )
    }

    /// Free Fire keeps no `Documents/Data`, but it does write the hot-update
    /// tree it loads at runtime inside its own container (`Library/Caches`,
    /// `Documents/contentcache`). Only a bounded walk can name the file the
    /// package has to land on, so the walk reports it with its size.
    private static var didSearchAssetTree = false

    static func logAssetTreeSearch(_ root: String) {
        guard !didSearchAssetTree else { return }
        didSearchAssetTree = true
        let fileManager = FileManager.default
        let needles = ["assetindexer", "gameassetbundles", "fileinfo", "com.dts.freefireth", "avatar"]
        let maxDepth = 8
        let maxDirectories = 4_000

        var queue: [(path: String, depth: Int)] = [(root, 0)]
        var visited = 0
        var files: [String] = []
        var directories: [String] = []

        while !queue.isEmpty, visited < maxDirectories, files.count < 20 {
            let (path, depth) = queue.removeFirst()
            visited += 1
            guard let children = try? fileManager.contentsOfDirectory(atPath: path) else {
                continue
            }
            for child in children {
                let full = (path as NSString).appendingPathComponent(child)
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: full, isDirectory: &isDirectory) else {
                    continue
                }
                let relative = full.count > root.count + 1
                    ? String(full.dropFirst(root.count + 1))
                    : child
                let lowered = child.lowercased()
                if needles.contains(where: { lowered.contains($0) }) {
                    if isDirectory.boolValue {
                        if directories.count < 16 { directories.append(relative) }
                    } else if files.count < 20 {
                        var size: Int64 = 0
                        if let attributes = try? fileManager.attributesOfItem(atPath: full),
                           let number = attributes[.size] as? NSNumber {
                            size = number.int64Value
                        }
                        files.append("\(relative) (\(size) B)")
                    }
                }
                if isDirectory.boolValue, depth < maxDepth {
                    queue.append((full, depth + 1))
                }
            }
        }

        log(
            "patch: asset tree search — \(visited) dirs, files: "
                + (files.isEmpty ? "none" : files.joined(separator: ", "))
                + ", dirs: "
                + (directories.isEmpty ? "none" : directories.joined(separator: ", ")),
            level: .info
        )
        logHotUpdateLayout(root)
    }

    /// The hot-update trees the game loads, one level deeper than the asset
    /// search so a package target can be matched exactly: whether
    /// `ios/gameassetbundles` mirrors the bundle (`avatar/assetindexer...`) or
    /// flattens it (`gameassetbundles.<token>`).
    static func logHotUpdateLayout(_ root: String) {
        let fileManager = FileManager.default
        func names(_ path: String, limit: Int = 24) -> [String] {
            guard let contents = try? fileManager.contentsOfDirectory(atPath: path) else {
                return []
            }
            return contents.sorted().prefix(limit).map { $0 }
        }
        func describe(_ relative: String) -> String? {
            let path = URL(fileURLWithPath: root).appendingPathComponent(relative).path
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                return nil
            }
            let listing = names(path)
            return "\(relative): " + (listing.isEmpty ? "<empty>" : listing.joined(separator: ", "))
        }

        let contentCache = "Documents/contentcache"
        var notes: [String] = []
        for category in names(URL(fileURLWithPath: root).appendingPathComponent(contentCache).path) {
            let base = "\(contentCache)/\(category)"
            for relative in [
                base,
                "\(base)/ios",
                "\(base)/ios/gameassetbundles",
                "\(base)/ios/gameassetbundles/avatar"
            ] {
                if let note = describe(relative) { notes.append(note) }
            }
        }
        log(
            "patch: hot-update layout — "
                + (notes.isEmpty ? "nothing readable" : notes.joined(separator: " | ")),
            level: .info
        )
    }

    private static func rememberBundle(_ path: String, bundleID: String) {
        UserDefaults.standard.set(path, forKey: bundleCachePrefix + bundleID)
        log("patch: app bundle resolved at \(path)")
    }

    /// `<container>/<Name>.app`, matched by its Info.plist identifier.
    private static func appBundle(
        in container: String,
        bundleID: String,
        activating: Bool,
        anyReadable: inout Bool
    ) -> String? {
        var names = (try? FileManager.default.contentsOfDirectory(atPath: container)) ?? []
        if names.isEmpty {
            _ = activateSandboxAccess(to: container)
            names = (try? FileManager.default.contentsOfDirectory(atPath: container)) ?? []
        }

        for name in names where name.hasSuffix(".app") {
            let candidate = PatchPath.canonicalContainerPath(
                (container as NSString).appendingPathComponent(name)
            )
            if activating {
                _ = activateSandboxAccess(to: candidate)
            }
            guard let identifier = bundleIdentifier(atBundlePath: candidate) else { continue }
            anyReadable = true
            guard identifier == bundleID else { continue }
            let activated = activateSandboxAccess(to: candidate)
            guard activated
                || (try? FileManager.default.contentsOfDirectory(atPath: candidate)) != nil else {
                continue
            }
            return candidate
        }
        return nil
    }

    private static func bundleIdentifier(atBundlePath path: String) -> String? {
        let plistPath = (path as NSString).appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: plistPath)),
              let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ) as? [String: Any] else {
            return nil
        }
        return plist["CFBundleIdentifier"] as? String
    }

    /// Grants this process a read-write sandbox extension for an absolute
    /// path. Two independent routes: worse_query (needs an App Group and is
    /// refused for everything outside the data containers) and the
    /// part-domain traversal in bad_query, which is the only one that reaches
    /// `/var/containers/Bundle/Application`. The traversal is tried with this
    /// build's own group first and with the system group as the fallback.
    static func activateSandboxAccess(to path: String) -> Bool {
        // worse_query only ever resolves inside the data volume, so the swap
        // is skipped for bundle paths instead of paying a refusal per call.
        let canonical = PatchPath.canonicalContainerPath(path)
        let inDataVolume = canonical.hasPrefix(
            PatchPath.canonicalContainerPath(appDataRoot) + "/"
        )
        if inDataVolume,
           let group = MCMAppGroupIdentifier(),
           activateEscape(path, group: group) {
            return true
        }
        return activateBadQuery(path)
    }

    private static let badQueryLock = NSLock()
    /// Consumed extensions stay consumed for the life of the process, so the
    /// handles are kept instead of released.
    private static var badQueryHandles: [Int64] = []

    private static func activateBadQuery(_ path: String) -> Bool {
        let clean = path.hasSuffix("/") ? String(path.dropLast()) : path
        guard clean.hasPrefix("/") else { return false }

        // Class 7 asks for a group this build is actually entitled to, and
        // containermanagerd resolves its part without confining part_domain
        // (that is the whole worse_query escape). Class 13 needs the
        // systemgroup identity of a build signed as com.apple.*, which a
        // re-signed app does not have: on 27.0.1 it answers `no result` (-3)
        // for /var/containers/Bundle/Application, so it goes last.
        if let group = MCMAppGroupIdentifier(),
           consumeBadQuery(clean, group: group) {
            log("patch: bad_query granted access to \(clean) via group \(group)")
            return true
        }
        if consumeBadQuery(clean, group: nil) {
            log("patch: bad_query granted access to \(clean) via system group")
            return true
        }
        return false
    }

    /// `create` is only a guard flag in bad_query.c (it skips the lstat), and
    /// the query itself is identical, so a target the sandbox cannot stat is
    /// still traversed.
    private static func consumeBadQuery(_ clean: String, group: String?) -> Bool {
        var pathC = clean.utf8CString.map { $0 }
        let handle: Int64
        if var groupC = group.map({ identifier in Array(identifier.utf8CString) }) {
            handle = groupC.withUnsafeMutableBufferPointer { buffer in
                bad_query(&pathC, true, buffer.baseAddress, false)
            }
        } else {
            handle = bad_query(&pathC, true, nil, false)
        }
        guard handle >= 0 else {
            log(
                "patch: bad_query refused \(clean) via \(group ?? "systemgroup") -> \(handle)",
                level: .info
            )
            return false
        }
        badQueryLock.lock()
        badQueryHandles.append(handle)
        badQueryLock.unlock()
        return true
    }

    // MARK: - Free route (worse_query, iOS 26.0–27.3)

    // containermanagerd mints a sandbox extension for the *resolved* part path
    // without checking that the resolution stays inside the container, so a
    // group's Library/Caches symlinked at a foreign container becomes a
    // read-write token for that container. Only an App Group entitlement is
    // needed, which AltStore / SideStore / Impactor provision with a free
    // Apple ID: no certificate, no kernel r/w, no MobileHouseArrest identity.

    static let escapeCachePrefix = "container.worse."
    static let escapeScanPrefix = "container.worse.scan."
    /// Container path reported by the pairing tunnel (InstallationProxy). It
    /// is exact, so it is tried before any inode walk.
    static let escapeHintPrefix = "container.hint."
    /// Rise of the inode walk when the group container's own inode is unknown.
    /// A fixed 2M cap stops before the newest containers: on iOS 27 the group
    /// container inode is already 16M, so every third-party app sits above it.
    static let escapeScanInodeBase: Int64 = 2_000_000
    /// Inodes walked on each side of the group container inode first; a miss
    /// falls back to the full range anchored to that same inode.
    static let escapeScanWindow: Int64 = 1_000_000
    /// A failed scan costs seconds; status refreshes call this repeatedly, so
    /// a miss backs off instead of stalling every refresh and the tunnel.
    static let escapeScanRetryInterval: TimeInterval = 20

    static func resolveByAppGroupEscape(bundleID: String) -> String? {
        guard let group = MCMAppGroupIdentifier() else {
            log("patch: worse_query unavailable — signature has no App Group", level: .warning)
            return nil
        }

        if let cached = cachedEscapeContainer(bundleID: bundleID),
           activateEscape(cached, group: group),
           containerBelongsTo(cached, bundleID: bundleID) {
            log("patch: worse_query reused cached container \(cached)")
            return PatchPath.canonicalContainerPath(cached)
        }

        // A path reported by the pairing tunnel costs one activate call, no
        // inode walk and no back-off wait, and it is the only way to reach a
        // container the scan window does not cover.
        if let hint = knownContainerHint(bundleID: bundleID),
           activateEscape(hint, group: group),
           containerBelongsTo(hint, bundleID: bundleID) {
            rememberEscapeContainer(hint, bundleID: bundleID)
            log(
                "patch: worse_query matched \(bundleID) at \(hint) (path from pairing)",
                level: .success
            )
            return PatchPath.canonicalContainerPath(hint)
        }

        // A miss is remembered briefly: the status view resolves the container
        // on every refresh, and repeating a full inode walk each time makes
        // the app unresponsive. The retry below still re-scans after 20s.
        let scanKey = escapeScanPrefix + bundleID
        if let lastAttempt = UserDefaults.standard.object(forKey: scanKey) as? Date {
            let elapsed = Date().timeIntervalSince(lastAttempt)
            if elapsed < escapeScanRetryInterval {
                log(
                    "patch: worse_query backoff — retrying in "
                        + "\(Int(escapeScanRetryInterval - elapsed))s",
                    level: .info
                )
                return nil
            }
        }
        UserDefaults.standard.set(Date(), forKey: scanKey)
        logEscapeScanWindow(group: group)

        // Containers are numbered by inode on the shared data volume and the
        // scan can only see up to the cap it is given. Recent iOS numbers the
        // app containers far above any fixed cap (the group container alone is
        // at 16M+ on 27.x), so the window around the group container's inode is
        // walked first and the full range still ends past it.
        var candidates = scanCandidates(group: group)
            .filter { isApplicationContainerPath($0) }
        if candidates.isEmpty {
            candidates = enumerateDirectories(path: appDataRoot)
                .filter { isApplicationContainerPath($0) }
        }
        guard !candidates.isEmpty else {
            log("patch: worse_query found no app containers to probe", level: .warning)
            return nil
        }

        // Containers are addressed by UUID, and the inode scan is the only
        // enumeration available before the escape is active. Probe them in
        // order and stop at the first one that answers for this bundle id.
        log(
            "patch: worse_query probing \(candidates.count) app containers, group \(group)",
            level: .info
        )
        var activated = 0
        var readable = 0
        var redirected = 0
        var seen: [String] = []
        for (index, candidate) in candidates.enumerated() {
            guard activateEscape(candidate, group: group) else {
                if index % 50 == 0 {
                    log("patch: worse_query probe \(index)/\(candidates.count) refused", level: .info)
                }
                continue
            }
            activated += 1

            // If containermanagerd answers with a different path than the one
            // the symlink points at, the token belongs to another container
            // and every read below fails no matter how the match is checked.
            if let resolved = MCMWorseQueryResolvedPath(candidate) {
                let canonicalResolved = PatchPath.canonicalContainerPath(resolved)
                let canonicalCandidate = PatchPath.canonicalContainerPath(candidate)
                if canonicalResolved != canonicalCandidate {
                    redirected += 1
                    if redirected <= 3 {
                        log(
                            "patch: worse_query resolved \(canonicalCandidate) as \(canonicalResolved)",
                            level: .warning
                        )
                    }
                }
            }

            if let identifier = containerIdentifierHint(candidate) {
                readable += 1
                if seen.count < 40, !seen.contains(identifier) {
                    seen.append(identifier)
                }
            }

            if containerBelongsTo(candidate, bundleID: bundleID) {
                rememberEscapeContainer(candidate, bundleID: bundleID)
                log("patch: worse_query matched \(bundleID) at \(candidate)", level: .success)
                return PatchPath.canonicalContainerPath(candidate)
            }
            MCMWorseQueryRelease(candidate)
        }

        MCMWorseQueryReleaseAll()
        log(
            "patch: worse_query probed \(candidates.count): activated \(activated),"
                + " identifiers readable \(readable), resolved elsewhere \(redirected)",
            level: .warning
        )
        if !seen.isEmpty {
            log("patch: worse_query containers seen: \(seen.sorted().joined(separator: ", "))")
        }
        if activated == 0 {
            log(
                "patch: worse_query could not activate any container — the App Group"
                    + " container is not writable by this signature",
                level: .warning
            )
        }
        log("patch: worse_query escaped but found no \(bundleID) container", level: .warning)
        return nil
    }

    /// Remembers the data container the pairing tunnel reported for a bundle
    /// id, so the escape can target it directly instead of walking the volume.
    static func noteContainerPath(_ path: String, bundleID: String) {
        let canonical = PatchPath.canonicalContainerPath(path)
        guard isApplicationContainerPath(canonical) else { return }
        if UserDefaults.standard.string(forKey: escapeHintPrefix + bundleID) != canonical {
            log("patch: remembered \(bundleID) container \(canonical)")
        }
        UserDefaults.standard.set(canonical, forKey: escapeHintPrefix + bundleID)
    }

    private static func knownContainerHint(bundleID: String) -> String? {
        guard let value = UserDefaults.standard.string(forKey: escapeHintPrefix + bundleID),
              isApplicationContainerPath(value) else {
            return nil
        }
        return value
    }

    private static func rememberEscapeContainer(_ path: String, bundleID: String) {
        UserDefaults.standard.set(path, forKey: escapeCachePrefix + bundleID)
        UserDefaults.standard.removeObject(forKey: escapeScanPrefix + bundleID)
    }

    private static func groupContainerInode(group: String) -> Int64? {
        guard let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: group
        ) else { return nil }
        var info = stat()
        return url.path.withCString { path in
            stat(path, &info) == 0 ? Int64(info.st_ino) : nil
        }
    }

    /// Full-range cap, anchored to the group container inode. A cap below that
    /// inode can never see a container installed on this iOS generation.
    private static func escapeScanInodeCap(group: String) -> Int64 {
        guard let inode = groupContainerInode(group: group) else {
            return escapeScanInodeBase
        }
        return max(escapeScanInodeBase, inode + escapeScanInodeBase)
    }

    private static func scanCandidates(group: String) -> [String] {
        var candidates: [String] = []
        var seen: Set<String> = []
        func collect(_ paths: [String]) {
            for path in paths where seen.insert(path).inserted {
                candidates.append(path)
            }
        }

        if let inode = groupContainerInode(group: group), inode > 1 {
            let lower = max(1, inode - escapeScanWindow)
            collect(MCMScanAppContainersRange(group, lower, inode + escapeScanWindow))
        }
        if candidates.isEmpty {
            collect(MCMScanAppContainersRange(group, 1, escapeScanInodeCap(group: group)))
        }
        return candidates
    }

    /// The inode window is the only lever when the escape finds nothing, so
    /// the group container's own inode is logged next to the ranges walked.
    private static func logEscapeScanWindow(group: String) {
        let inode = groupContainerInode(group: group)
        let fullCap = escapeScanInodeCap(group: group)
        let window = inode.map {
            "\(max(1, $0 - escapeScanWindow))…\($0 + escapeScanWindow) then 1…\(fullCap)"
        } ?? "1…\(fullCap)"
        log(
            "patch: worse_query scanning inodes \(window)"
                + " (group container inode \(inode.map(String.init) ?? "unknown"))"
        )
    }

    private static func containerIdentifierHint(_ path: String) -> String? {
        if let metadata = readContainerMetadata(containerPath: path), !metadata.bundleID.isEmpty {
            return metadata.bundleID
        }
        return MCMContainerIdentifierForPath(path)
    }

    static func activateEscape(_ path: String, group: String) -> Bool {
        var escapeError: NSString?
        let activated = MCMWorseQueryActivate(path, group, &escapeError)
        if !activated, let escapeError {
            log("patch: worse_query refused \(path) — \(escapeError)", level: .info)
        }
        return activated
    }

    private static func cachedEscapeContainer(bundleID: String) -> String? {
        guard let value = UserDefaults.standard.string(forKey: escapeCachePrefix + bundleID),
              isApplicationContainerPath(value),
              FileManager.default.fileExists(atPath: value) else {
            return nil
        }
        return value
    }

    /// Metadata first, then the container xattr, then files the game itself
    /// writes, so a wrong container is never patched.
    private static func containerBelongsTo(_ path: String, bundleID: String) -> Bool {
        if let metadata = readContainerMetadata(containerPath: path),
           metadata.bundleID == bundleID {
            return true
        }
        // The metadata keys have moved between iOS releases, so the record is
        // also searched as raw bytes before the container is written off.
        if metadataRecordContains(path, bundleID: bundleID) {
            return true
        }
        if MCMContainerIdentifierForPath(path) == bundleID {
            return true
        }
        let markers = [
            "Library/Preferences/\(bundleID).plist",
            "Documents/Data/Raw/ios/gameassetbundles/cache_res.fileinfo"
        ]
        return markers.contains {
            FileManager.default.fileExists(
                atPath: (path as NSString).appendingPathComponent($0)
            )
        }
    }

    static func resolveByMetadataScan(bundleID: String) -> String? {
        if KernelExploit.requiresSandboxEscape, !KernelExploit.hasSandboxAccess() {
            log("patch: metadata scan skipped — sandbox access is not active", level: .warning)
            return nil
        }

        let directories = enumerateDirectories(path: appDataRoot)
        guard !directories.isEmpty else {
            log("patch: metadata scan found no app containers", level: .warning)
            return nil
        }

        for directory in directories {
            guard UUID(uuidString: (directory as NSString).lastPathComponent) != nil else {
                continue
            }
            guard let metadata = readContainerMetadata(containerPath: directory),
                  metadata.bundleID == bundleID else {
                continue
            }
            let canonical = PatchPath.canonicalContainerPath(directory)
            guard isApplicationContainerPath(canonical) else { continue }
            return canonical
        }
        return nil
    }

    static func isApplicationContainerPath(_ path: String) -> Bool {
        let canonicalRoot = PatchPath.canonicalContainerPath(appDataRoot)
        let canonicalPath = PatchPath.canonicalContainerPath(path)
        guard canonicalPath.hasPrefix(canonicalRoot + "/") else { return false }
        return UUID(uuidString: (canonicalPath as NSString).lastPathComponent) != nil
    }

    static func enumerateDirectories(path: String) -> [String] {
        let clean = path.hasSuffix("/") ? String(path.dropLast()) : path
        guard clean.hasPrefix("/") else { return [] }

        if let names = try? FileManager.default.contentsOfDirectory(atPath: clean), !names.isEmpty {
            return names.map { (clean as NSString).appendingPathComponent($0) }
        }

        var pathC = clean.utf8CString.map { Int8($0) }
        guard let result = bad_query_list(&pathC, 2_000_000) else {
            log("enumerate: bad_query_list returned NULL for \(clean)", level: .warning)
            return []
        }
        defer { free(result) }
        let list = String(cString: result)
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
        if !list.isEmpty {
            log("enumerate: inode fallback for \(clean) -> \(list.count) entries")
        }
        return list
    }

    private static func metadataRecordContains(_ containerPath: String, bundleID: String) -> Bool {
        let metadataPath = (containerPath as NSString).appendingPathComponent(
            ".com.apple.mobile_container_manager.metadata.plist"
        )
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: metadataPath)),
              !data.isEmpty else {
            return false
        }
        var needles = [Data(bundleID.utf8)]
        if let utf16 = bundleID.data(using: .utf16LittleEndian) {
            needles.append(utf16)
        }
        return needles.contains { data.range(of: $0) != nil }
    }

    static func readContainerMetadata(containerPath: String) -> ContainerMetadata? {
        let metadataPath = (containerPath as NSString).appendingPathComponent(
            ".com.apple.mobile_container_manager.metadata.plist"
        )
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: metadataPath)),
              let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ) as? [String: Any] else {
            return nil
        }

        let bundleID = (plist["MCMMetadataIdentifier"] as? String) ?? ""
        guard !bundleID.isEmpty else { return nil }

        var displayName = ""
        if let info = plist["MCMMetadataInfo"] as? [String: Any] {
            displayName = (info["CFBundleDisplayName"] as? String)
                ?? (info["CFBundleName"] as? String)
                ?? ""
        }
        return ContainerMetadata(bundleID: bundleID, displayName: displayName)
    }

    static func containerExists(bundleID: String) -> Bool {
        var lookupError: NSString?
        if let path = MCMContainerPathForIdentifier(2, bundleID, false, &lookupError),
           isApplicationContainerPath(path) {
            return true
        }
        return resolveAppContainerPath(bundleID: bundleID) != nil
    }
}
