import Foundation

struct BackupRecord: Codable, Equatable {
    let path: String
    let bundleID: String
    let group: String
    let size: Int
    let sha256: String
    let createdAt: Date
}

struct LedgerEntry: Codable {
    let date: Date
    let action: String
    let productID: String
    let packageName: String
    let bundleID: String
    let backend: String
    let paths: [String]
    let result: String
    let message: String
}

enum BackupStore {
    static var rootURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("Discord", isDirectory: true)
    }

    static var originalsURL: URL {
        rootURL.appendingPathComponent("originals", isDirectory: true)
    }

    static var ledgerURL: URL {
        rootURL.appendingPathComponent("ledger.jsonl", isDirectory: false)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func ensureDirectories() throws {
        try FileManager.default.createDirectory(
            at: originalsURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private static func binaryURL(_ key: String) -> URL {
        originalsURL.appendingPathComponent("\(key).bin")
    }

    private static func metadataURL(_ key: String) -> URL {
        originalsURL.appendingPathComponent("\(key).json")
    }

    static func record(bundleID: String, relativePath: String) -> BackupRecord? {
        let key = PatchPath.backupKey(bundleID: bundleID, relativePath: relativePath)
        guard let data = try? Data(contentsOf: metadataURL(key)),
              let record = try? decoder.decode(BackupRecord.self, from: data) else {
            return nil
        }
        return record
    }

    static func hasBackup(bundleID: String, relativePath: String) -> Bool {
        let key = PatchPath.backupKey(bundleID: bundleID, relativePath: relativePath)
        let fileManager = FileManager.default
        return fileManager.fileExists(atPath: metadataURL(key).path)
            && fileManager.fileExists(atPath: binaryURL(key).path)
    }

    @discardableResult
    static func capture(
        _ data: Data,
        bundleID: String,
        relativePath: String
    ) throws -> BackupRecord {
        try ensureDirectories()
        let key = PatchPath.backupKey(bundleID: bundleID, relativePath: relativePath)
        if let existing = record(bundleID: bundleID, relativePath: relativePath) {
            return existing
        }

        let binary = binaryURL(key)
        let metadata = metadataURL(key)
        try data.write(to: binary, options: .atomic)

        let record = BackupRecord(
            path: relativePath,
            bundleID: bundleID,
            group: PatchPath.groupStem(for: relativePath),
            size: data.count,
            sha256: PatchPath.sha256Hex(data),
            createdAt: Date()
        )
        let encoded = try encoder.encode(record)
        try encoded.write(to: metadata, options: .atomic)
        return record
    }

    static func read(bundleID: String, relativePath: String) throws -> Data {
        let key = PatchPath.backupKey(bundleID: bundleID, relativePath: relativePath)
        let binary = binaryURL(key)
        guard FileManager.default.fileExists(atPath: binary.path) else {
            throw PatchServiceError.missingBackup(relativePath)
        }
        return try Data(contentsOf: binary)
    }

    static func totalBytes() -> Int {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: originalsURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        return files
            .filter { $0.pathExtension == "bin" }
            .reduce(0) { total, url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return total + size
            }
    }

    static func backupCount() -> Int {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: originalsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        return files.filter { $0.pathExtension == "json" }.count
    }

    static func clearAll() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: originalsURL.path) {
            try fileManager.removeItem(at: originalsURL)
        }
        if fileManager.fileExists(atPath: ledgerURL.path) {
            try fileManager.removeItem(at: ledgerURL)
        }
    }

    static func appendLedger(_ entry: LedgerEntry) {
        do {
            try ensureDirectories()
            let data = try encoder.encode(entry)
            var line = data
            line.append(0x0A)

            let fileManager = FileManager.default
            if !fileManager.fileExists(atPath: ledgerURL.path) {
                try line.write(to: ledgerURL, options: .atomic)
                return
            }

            let handle = try FileHandle(forWritingTo: ledgerURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } catch {
            log("ledger: could not append entry — \(error.localizedDescription)", level: .warning)
        }
    }
}

/// A hot-update file is content addressed, so a patched asset is stored under
/// the name of its own bytes. The backup stays keyed on the shipped name; this
/// record is what lets restore remove the renamed copy afterwards.
struct RenamedTarget {
    let original: String
    let applied: String
}

enum RenamedTargetsStore {
    private static func key(productID: String, bundleID: String) -> String {
        "discord.renamedTargets.\(bundleID).\(productID)"
    }

    static func save(_ targets: [RenamedTarget], productID: String, bundleID: String) {
        let encoded = targets.map { "\($0.original)|\($0.applied)" }
        UserDefaults.standard.set(encoded, forKey: key(productID: productID, bundleID: bundleID))
    }

    static func load(productID: String, bundleID: String) -> [RenamedTarget] {
        let raw = UserDefaults.standard.stringArray(
            forKey: key(productID: productID, bundleID: bundleID)
        ) ?? []
        return raw.compactMap { entry in
            let parts = entry.components(separatedBy: "|")
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
                return nil
            }
            return RenamedTarget(original: parts[0], applied: parts[1])
        }
    }

    static func clear(productID: String, bundleID: String) {
        UserDefaults.standard.removeObject(forKey: key(productID: productID, bundleID: bundleID))
    }
}

enum AppliedTargetsStore {
    private static func key(productID: String, bundleID: String) -> String {
        "discord.appliedTargets.\(bundleID).\(productID)"
    }

    static func save(_ paths: [String], productID: String, bundleID: String) {
        UserDefaults.standard.set(paths, forKey: key(productID: productID, bundleID: bundleID))
    }

    static func load(productID: String, bundleID: String) -> [String]? {
        UserDefaults.standard.stringArray(forKey: key(productID: productID, bundleID: bundleID))
    }

    static func clear(productID: String, bundleID: String) {
        UserDefaults.standard.removeObject(forKey: key(productID: productID, bundleID: bundleID))
    }
}
