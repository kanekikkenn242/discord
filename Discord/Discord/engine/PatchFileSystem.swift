import Foundation

protocol PatchFileSystem {
    var backendName: String { get }
    /// Absolute `<FreeFire.app>` when the shipped asset tree is reachable.
    /// Free Fire keeps `Data/Raw/ios/gameassetbundles` inside the signed
    /// bundle, not in the data container, so asset rules only resolve there.
    var bundleRoot: String? { get }
    /// Trees Free Fire loads instead of the signed bundle:
    /// `Library/Caches/<bundle id>` and each `Documents/contentcache/<category>`,
    /// whose `ios/` directory mirrors the bundle's `Data/Raw/ios`.
    var hotRoots: [String] { get }
    func exists(_ relativePath: String) throws -> Bool
    func read(_ relativePath: String) throws -> Data
    func write(_ data: Data, to relativePath: String) throws
    func delete(_ relativePath: String) throws
    /// Declared as a requirement on purpose: with only an extension method,
    /// calls through the `PatchFileSystem` existential dispatch statically and
    /// `LocalPatchFileSystem`'s hot-update discovery is never reached.
    func resolveExisting(_ relativePath: String) throws -> String
    /// Stores `data` beside an existing file under a new name and removes the
    /// old one; returns the new container-relative path. Hot-update assets are
    /// content addressed, so patched bytes have to live under their own name.
    func replaceWithNewName(_ newName: String, data: Data, at relativePath: String) throws -> String
    /// Writes a file that does not exist yet, inside a directory that does.
    func create(_ data: Data, at relativePath: String) throws
}

extension PatchFileSystem {
    var bundleRoot: String? { nil }
    var hotRoots: [String] { [] }

    func replaceWithNewName(_ newName: String, data: Data, at relativePath: String) throws -> String {
        throw PatchServiceError.noAccess("\(backendName) cannot rename \(relativePath)")
    }

    func create(_ data: Data, at relativePath: String) throws {
        throw PatchServiceError.noAccess("\(backendName) cannot create \(relativePath)")
    }

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
        log("patch: \(safe) is not on this device [\(backendName)]", level: .warning)
        throw PatchServiceError.targetMissing(safe)
    }
}

struct LocalPatchFileSystem: PatchFileSystem {
    let rootPath: String
    let bundleRoot: String?
    let hotRoots: [String]
    let backendName: String

    init(rootPath: String, bundleRoot: String? = nil, hotRoots: [String] = []) {
        self.rootPath = PatchPath.canonicalContainerPath(rootPath)
        self.bundleRoot = bundleRoot.map(PatchPath.canonicalContainerPath)
        self.hotRoots = hotRoots.map(PatchPath.canonicalContainerPath)
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
        if bundleEligible {
            // `contentcache/<category>/ios` is the bundle's `Data/Raw/ios`, so an
            // asset rule keeps its own tail once that prefix is replaced;
            // `Library/Caches/<id>` appends the whole path instead.
            let mirrored = safe.hasPrefix("Data/Raw/")
                ? String(safe.dropFirst("Data/Raw/".count))
                : safe
            for hotRoot in hotRoots {
                urls.append(URL(fileURLWithPath: hotRoot).appendingPathComponent(safe))
                if mirrored != safe {
                    urls.append(URL(fileURLWithPath: hotRoot).appendingPathComponent(mirrored))
                }
            }
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
        let insideHot = hotRoots.contains { path.hasPrefix($0 + "/") }
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
        let bases = [bundleRoot].compactMap({ $0 }) + hotRoots + [rootPath + "/Documents", rootPath]
        for base in bases {
            let directory = (base as NSString).appendingPathComponent(parent)
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory),
                  !names.isEmpty else { continue }
            let shown = names.sorted().prefix(12).joined(separator: ", ")
            notes.append("\(directory): \(shown)")
        }
        return notes.isEmpty ? "no candidate directory is readable" : notes.joined(separator: " | ")
    }

    /// A hot-update bundle is stored as `<logical name>.<token>`, and the token
    /// is minted per download, so the shipped `<name>.<ext>~2F<token>~3D` rule
    /// can never match by name. When the exact path is absent the mirrored
    /// directory is listed and the single file that starts with the logical
    /// name is used; its container-relative path is returned so every later
    /// access goes through the normal resolver.
    func resolveExisting(_ relativePath: String) throws -> String {
        let safe = try PatchPath.safeRelative(relativePath)
        var candidates: [String] = []
        if !safe.hasPrefix("Documents/") {
            candidates.append("Documents/\(safe)")
        }
        candidates.append(safe)
        for candidate in candidates where (try? exists(candidate)) == true {
            return candidate
        }
        if let discovered = discoverHotUpdateFile(safe) {
            return discovered
        }
        log("patch: \(safe) is not on this device — \(describe(safe))", level: .warning)
        throw PatchServiceError.targetMissing(safe)
    }

    private func discoverHotUpdateFile(_ safe: String) -> String? {
        guard safe.hasPrefix("Data/Raw/") else { return nil }
        let mirrored = String(safe.dropFirst("Data/Raw/".count))
        let parent = (mirrored as NSString).deletingLastPathComponent
        let file = (mirrored as NSString).lastPathComponent
        guard !parent.isEmpty, !file.isEmpty else { return nil }
        let logical = file.components(separatedBy: "~").first ?? file
        let stem = (logical as NSString).deletingPathExtension
        let prefixes = [logical, stem].filter { !$0.isEmpty && $0 != "." }
        guard !prefixes.isEmpty else { return nil }
        let fileManager = FileManager.default

        // A patched asset is stored under the digest of its own bytes, so the
        // shipped token is gone and the file has to be found by name. The
        // container's own `Documents/contentcache/...` tree is searched too:
        // that is where the asset lives, and it is the only root that can be
        // rewritten in place.
        var roots = hotRoots
        let cacheBase = rootPath + "/Documents/contentcache"
        if let categories = try? fileManager.contentsOfDirectory(atPath: cacheBase) {
            for category in categories.sorted() {
                roots.append(cacheBase + "/" + category)
            }
        }
        roots.append(rootPath)

        for hotRoot in roots {
            let directory = URL(fileURLWithPath: hotRoot).appendingPathComponent(parent).path
            let names = (try? fileManager.contentsOfDirectory(atPath: directory)) ?? []
            let matches = names.filter { name in
                prefixes.contains { name.hasPrefix($0 + ".") }
            }
            guard !matches.isEmpty else { continue }
            // Free Fire writes its own copy back under the shipped digest, so a
            // tree can hold both that copy and the one this app renamed. The
            // newest file is the one the game last wrote or accepted, and it is
            // the build the floats have to be shifted into.
            let match = matches.max { lhs, rhs in
                modificationDate(directory, lhs) < modificationDate(directory, rhs)
            } ?? matches[0]
            if matches.count > 1 {
                log(
                    "patch: \(parent) holds \(matches.count) copies for \(logical) — using the newest, \(match)",
                    level: .info
                )
            }
            let full = URL(fileURLWithPath: hotRoot)
                .appendingPathComponent(parent)
                .appendingPathComponent(match)
                .path
            guard full.hasPrefix(rootPath + "/") else { continue }
            log("patch: \(mirrored) resolves to \(full)", level: .info)
            return String(full.dropFirst(rootPath.count + 1))
        }
        return nil
    }

    private func modificationDate(_ directory: String, _ name: String) -> Date {
        let path = (directory as NSString).appendingPathComponent(name)
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return (attributes?[.modificationDate] as? Date) ?? .distantPast
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

    /// Renames inside the directory the asset already lives in, so a hot-update
    /// tree keeps its layout and only the content-addressed component changes.
    func replaceWithNewName(_ newName: String, data: Data, at relativePath: String) throws -> String {
        let safe = try PatchPath.safeRelative(relativePath)
        let current = try targetURL(safe)
        let directory = current.deletingLastPathComponent()
        let destination = directory.appendingPathComponent(newName).standardizedFileURL
        let path = (destination.path as NSString).standardizingPath
        let insideContainer = path.hasPrefix(rootPath + "/")
        let insideBundle = bundleRoot.map { path.hasPrefix($0 + "/") } ?? false
        let insideHot = hotRoots.contains { path.hasPrefix($0 + "/") }
        guard insideContainer || insideBundle || insideHot else {
            throw PatchServiceError.unsafePath(path)
        }
        try data.write(to: destination, options: .atomic)
        if path != (current.path as NSString).standardizingPath {
            try FileManager.default.removeItem(at: current)
        }
        guard insideContainer else { return safe }
        return String(path.dropFirst(rootPath.count + 1))
    }

    func create(_ data: Data, at relativePath: String) throws {
        let safe = try PatchPath.safeRelative(relativePath)
        let url = URL(fileURLWithPath: rootPath).appendingPathComponent(safe).standardizedFileURL
        let path = (url.path as NSString).standardizingPath
        guard path.hasPrefix(rootPath + "/") else {
            throw PatchServiceError.unsafePath(path)
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: url.deletingLastPathComponent().path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw PatchServiceError.targetMissing((safe as NSString).deletingLastPathComponent)
        }
        try data.write(to: url, options: .atomic)
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
