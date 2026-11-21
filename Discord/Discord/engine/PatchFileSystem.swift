import Foundation

protocol PatchFileSystem {
    var backendName: String { get }
    /// Absolute `<FreeFire.app>` when the shipped asset tree is reachable.
    /// Free Fire keeps `Data/Raw/ios/gameassetbundles` inside the signed
    /// bundle, not in the data container, so asset rules only resolve there.
    var bundleRoot: String? { get }
    /// `Library/Caches/<bundle id>`: the tree Free Fire actually loads once it
    /// has unpacked the hot-update assets into its own container.
    var hotRoot: String? { get }
    func exists(_ relativePath: String) throws -> Bool
    func read(_ relativePath: String) throws -> Data
    func write(_ data: Data, to relativePath: String) throws
    func delete(_ relativePath: String) throws
}

extension PatchFileSystem {
    var bundleRoot: String? { nil }
    var hotRoot: String? { nil }

    /// The package rules are container-relative and may target either
    /// `Documents/...` (current Free Fire layout) or the bare path used by
    /// older builds. Never create a missing file: it could not be restored.
    func resolveExisting(_ destination: String) throws -> String {
        let safe = try PatchPath.safeRelative(destination)
        var candidates: [String] = []
        if !safe.hasPrefix("Documents/") {
            candidates.append("Documents/\(safe)")
        }
        candidates.append(safe)
        for candidate in candidates {
            if try exists(candidate) {
                return candidate
            }
        }
        throw PatchServiceError.targetMissing(safe)
    }
}

struct LocalPatchFileSystem: PatchFileSystem {
    let rootPath: String
    let bundleRoot: String?
    let hotRoot: String?
    let backendName: String

    init(rootPath: String, bundleRoot: String? = nil, hotRoot: String? = nil) {
        self.rootPath = PatchPath.canonicalContainerPath(rootPath)
        self.bundleRoot = bundleRoot.map(PatchPath.canonicalContainerPath)
        self.hotRoot = hotRoot.map(PatchPath.canonicalContainerPath)
        self.backendName = "kernel/MCM"
    }

    /// `Data/Raw/ios/...` ships inside the `.app`; `Documents/`, `Library/`
    /// and `tmp/` always belong to the data container's own tree.
    private static let containerOnlyPrefixes = ["Documents/", "Library/", "tmp/"]

    private func candidateURLs(_ safe: String) -> [URL] {
        var urls: [URL] = []
        let bundleEligible = !Self.containerOnlyPrefixes.contains { safe.hasPrefix($0) }
        if bundleEligible, let bundleRoot {
            urls.append(URL(fileURLWithPath: bundleRoot).appendingPathComponent(safe))
        }
        if bundleEligible, let hotRoot {
            urls.append(URL(fileURLWithPath: hotRoot).appendingPathComponent(safe))
        }
        if !safe.hasPrefix("Documents/") {
            urls.append(
                URL(fileURLWithPath: rootPath)
                    .appendingPathComponent("Documents")
                    .appendingPathComponent(safe)
            )
        }
        urls.append(URL(fileURLWithPath: rootPath).appendingPathComponent(safe))
        return urls
    }

    private func isExistingFile(_ url: URL) -> Bool {
        let path = (url.path as NSString).standardizingPath
        let insideContainer = path.hasPrefix(rootPath + "/")
        let insideBundle = bundleRoot.map { path.hasPrefix($0 + "/") } ?? false
        let insideHot = hotRoot.map { path.hasPrefix($0 + "/") } ?? false
        guard insideContainer || insideBundle || insideHot else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }

    /// Resolves to the file the game actually loads. Nothing is created.
    private func targetURL(_ relativePath: String) throws -> URL {
        let safe = try PatchPath.safeRelative(relativePath)
        for url in candidateURLs(safe) {
            if isExistingFile(url) {
                return url
            }
        }
        log("patch: \(safe) is not on this device — \(describe(safe))", level: .warning)
        throw PatchServiceError.targetMissing(safe)
    }

    /// The missing target is the only clue a mismatched game build leaves, so
    /// the directories that should hold it are listed next to the error.
    private func describe(_ safe: String) -> String {
        let parent = (safe as NSString).deletingLastPathComponent
        var notes: [String] = []
        for base in [bundleRoot, hotRoot, rootPath + "/Documents", rootPath].compactMap({ $0 }) {
            let directory = (base as NSString).appendingPathComponent(parent)
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory),
                  !names.isEmpty else { continue }
            let shown = names.sorted().prefix(12).joined(separator: ", ")
            notes.append("\(directory): \(shown)")
        }
        return notes.isEmpty ? "no candidate directory is readable" : notes.joined(separator: " | ")
    }

    func exists(_ relativePath: String) throws -> Bool {
        let safe = try PatchPath.safeRelative(relativePath)
        return candidateURLs(safe).contains { isExistingFile($0) }
    }

    func read(_ relativePath: String) throws -> Data {
        try Data(contentsOf: try targetURL(relativePath))
    }

    func write(_ data: Data, to relativePath: String) throws {
        try data.write(to: try targetURL(relativePath), options: .atomic)
    }

    func delete(_ relativePath: String) throws {
        try FileManager.default.removeItem(at: try targetURL(relativePath))
    }
}

final class AirliftPatchFileSystem: PatchFileSystem {
    let backendName = "pairing/AFC"
    private let tunnel: AirliftTunnel

    init(tunnel: AirliftTunnel) {
        self.tunnel = tunnel
    }

    func exists(_ relativePath: String) throws -> Bool {
        let safe = try PatchPath.safeRelative(relativePath)
        return tunnel.fileExists(path: safe)
    }

    func read(_ relativePath: String) throws -> Data {
        let safe = try PatchPath.safeRelative(relativePath)
        return try tunnel.readFile(path: safe)
    }

    func write(_ data: Data, to relativePath: String) throws {
        let safe = try PatchPath.safeRelative(relativePath)
        try tunnel.writeFile(path: safe, data: data)
    }

    func delete(_ relativePath: String) throws {
        let safe = try PatchPath.safeRelative(relativePath)
        try tunnel.removeFile(path: safe)
    }
}
