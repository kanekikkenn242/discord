import Foundation
import Darwin

struct ContainerMetadata {
    let bundleID: String
    let displayName: String
}

enum ContainerStore {
    static let appDataRoot = "/var/mobile/Containers/Data/Application"

    static func resolveAppContainerPath(bundleID: String) -> String? {
        guard (try? PatchPath.safeRelative(bundleID)) == bundleID else {
            return nil
        }

        var lookupError: NSString?
        if let path = MCMActivateContainerPath(2, bundleID, false, &lookupError),
           isApplicationContainerPath(path) {
            log("patch: MCM resolved \(bundleID)")
            return PatchPath.canonicalContainerPath(path)
        }

        let detail = lookupError.map(String.init) ?? "unavailable"
        log("patch: MCM could not resolve \(bundleID), detail=\(detail)", level: .warning)

        if let scanned = resolveByMetadataScan(bundleID: bundleID) {
            log("patch: metadata scan resolved \(bundleID)")
            return scanned
        }
        return nil
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
