import Foundation

protocol PatchFileSystem {
    var backendName: String { get }
    func exists(_ relativePath: String) throws -> Bool
    func read(_ relativePath: String) throws -> Data
    func write(_ data: Data, to relativePath: String) throws
    func delete(_ relativePath: String) throws
}

extension PatchFileSystem {
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
    let backendName: String

    init(rootPath: String) {
        self.rootPath = PatchPath.canonicalContainerPath(rootPath)
        self.backendName = "kernel/MCM"
    }

    private func absolute(_ relativePath: String) throws -> URL {
        let safe = try PatchPath.safeRelative(relativePath)
        let full = (rootPath as NSString).appendingPathComponent(safe)
        let standardized = (full as NSString).standardizingPath
        guard standardized == rootPath || standardized.hasPrefix(rootPath + "/") else {
            throw PatchServiceError.unsafePath(relativePath)
        }
        return URL(fileURLWithPath: standardized)
    }

    func exists(_ relativePath: String) throws -> Bool {
        let url = try absolute(relativePath)
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }

    func read(_ relativePath: String) throws -> Data {
        try Data(contentsOf: try absolute(relativePath))
    }

    func write(_ data: Data, to relativePath: String) throws {
        try data.write(to: try absolute(relativePath), options: .atomic)
    }

    func delete(_ relativePath: String) throws {
        try FileManager.default.removeItem(at: try absolute(relativePath))
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
