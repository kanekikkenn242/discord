import Foundation
import Darwin

struct ContainerMetadata {
    let bundleID: String
    let displayName: String
}

enum ContainerStore {
    static let appDataRoot = "/var/mobile/Containers/Data/Application"

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

    // MARK: - Free route (worse_query, iOS 26.0–27.3)

    // containermanagerd mints a sandbox extension for the *resolved* part path
    // without checking that the resolution stays inside the container, so a
    // group's Library/Caches symlinked at a foreign container becomes a
    // read-write token for that container. Only an App Group entitlement is
    // needed, which AltStore / SideStore / Impactor provision with a free
    // Apple ID: no certificate, no kernel r/w, no MobileHouseArrest identity.

    static let escapeCachePrefix = "container.worse."
    static let escapeScanPrefix = "container.worse.scan."
    /// Inodes walked per attempt. The app container root cannot be listed
    /// before the escape is active, so containers are found by inode and the
    /// cap has to reach the newest install, not just the stock apps.
    static let escapeScanInodeCap: Int64 = 2_000_000
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
        // scan can only see up to the cap it is given. A 400k cap covers the
        // stock Apple apps but stops before recently installed third-party
        // apps — the game is usually the newest container on the device — so
        // the full range the metadata scan uses is walked here too.
        var candidates = MCMScanAppContainers(group, escapeScanInodeCap)
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
                UserDefaults.standard.set(candidate, forKey: escapeCachePrefix + bundleID)
                UserDefaults.standard.removeObject(forKey: scanKey)
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

    /// The inode window is the only lever when the escape finds nothing, so
    /// the group container's own inode is logged next to the cap: if it is far
    /// above the cap, the scan never reaches the newer containers.
    private static func logEscapeScanWindow(group: String) {
        guard let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: group
        ) else { return }
        var info = stat()
        let inode: UInt64? = url.path.withCString { path in
            stat(path, &info) == 0 ? UInt64(info.st_ino) : nil
        }
        log(
            "patch: worse_query scanning inodes 1…\(escapeScanInodeCap)"
                + " (group container inode \(inode.map(String.init) ?? "unknown"))"
        )
    }

    private static func containerIdentifierHint(_ path: String) -> String? {
        if let metadata = readContainerMetadata(containerPath: path), !metadata.bundleID.isEmpty {
            return metadata.bundleID
        }
        return MCMContainerIdentifierForPath(path)
    }

    private static func activateEscape(_ path: String, group: String) -> Bool {
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
