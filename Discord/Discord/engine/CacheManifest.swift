import Foundation
import CommonCrypto

/// Free Fire validates every hot-update asset against the manifest beside it
/// (`contentcache/<Category>/ios/fileinfo`). A shifted asset keeps its file
/// size but changes bytes, so the digest recorded there no longer matches: the
/// game treats the tree as corrupt, re-downloads the hotfix, and the patch ends
/// up overwritten before it is ever used.
///
/// The manifest format is not documented, so the entry is not parsed by column
/// position. Instead the digests of the file as it is now (and of the shipped
/// copy, for a manifest that was never repaired) are computed and looked up by
/// value in the manifest; every hit is replaced with the matching digest of the
/// patched bytes, in the same encoding. When nothing matches, nothing is
/// written, the row is logged and the apply is refused rather than handing the
/// game another corrupt tree.
enum CacheManifest {
    struct Replacement {
        let path: String
        let data: Data
        let summary: String
        /// The rows this repair changed, keyed by their first column. Several
        /// patches share one `fileinfo`, so restore has to put back only its
        /// own rows; writing the whole backup would erase another product's.
        let rows: [RowChange]
    }

    struct RowChange {
        let key: String
        let original: String
        let patched: String
    }

    /// The manifest that lists `asset`, e.g.
    /// `Documents/contentcache/Compulsory/ios/fileinfo`.
    static func manifestPath(for asset: String) -> String? {
        let parts = asset.components(separatedBy: "/")
        guard let index = parts.firstIndex(of: "contentcache"),
              index + 1 < parts.count else {
            return nil
        }
        return parts[0...index].joined(separator: "/") + "/" + parts[index + 1] + "/ios/fileinfo"
    }

    /// Returns the manifest with the asset's digest moved to the patched bytes,
    /// nil when the manifest already matches or when the asset has no
    /// manifest at all.
    static func repair(
        asset: String,
        current: Data,
        shipped: Data?,
        patched: Data,
        patchedStored: Data? = nil,
        patchedCounterpart: Data? = nil,
        renamedFrom: String? = nil,
        renamedTo: String? = nil,
        fileSystem: PatchFileSystem
    ) throws -> Replacement? {
        guard let manifest = manifestPath(for: asset),
              try fileSystem.exists(manifest) else {
            log("patch: \(asset) has no contentcache manifest — the game's digest check stays untouched", level: .warning)
            return nil
        }
        let raw = try fileSystem.read(manifest)
        guard let text = String(data: raw, encoding: .utf8)
                ?? String(data: raw, encoding: .isoLatin1) else {
            log("patch: \(manifest) is not text — cannot repair its digest", level: .warning)
            return nil
        }

        var updated = text
        var notes: [String] = []
        var changed = false
        var matchedCurrent = false

        // A hot-update file is named after its own digest, so a renamed asset
        // is also renamed in the manifest when the row records the file name.
        if let from = renamedFrom, let to = renamedTo, from != to, updated.contains(from) {
            let count = updated.components(separatedBy: from).count - 1
            updated = updated.replacingOccurrences(of: from, with: to)
            changed = true
            matchedCurrent = true
            notes.append("name×\(count)")
        }

        var sources: [Data] = [current]
        if let shipped, shipped != current {
            sources.append(shipped)
        }
        for source in sources {
            for pair in digestPairs(old: source, new: patched) {
                for spelling in pair.spellings {
                    if updated.contains(spelling.value.new) {
                        notes.append("\(pair.name)/\(spelling.label) current")
                        matchedCurrent = true
                        continue
                    }
                    guard updated.contains(spelling.value.old) else { continue }
                    let count = updated.components(separatedBy: spelling.value.old).count - 1
                    updated = updated.replacingOccurrences(of: spelling.value.old, with: spelling.value.new)
                    changed = true
                    matchedCurrent = true
                    notes.append("\(pair.name)/\(spelling.label)×\(count)")
                }
            }
        }

        // The row carries two digest/size pairs: the bytes stored on disk (the
        // file name is their digest) and the other representation of the same
        // asset — the bundle the gzip expands to for `cache_res`, the gzip the
        // raw avatar bundle was downloaded as for `assetindexer`. Their column
        // order is not fixed between builds. Assuming column 4 was the gzip
        // wrote the gzip digest into the raw column on a build that stores the
        // pairs the other way round, so the row described a file that does not
        // exist and the game re-downloaded the hotfix even though the patched
        // bytes were on disk. Calibrate the pair from the current file instead:
        // the byte count survives a recompression that changes the digest.
        if let stored = patchedStored {
            let newStored = PatchPath.sha1Base64(stored)
            let currentStored = PatchPath.sha1Base64(current)
            let logical = (fileName(asset) as NSString).deletingPathExtension
                .components(separatedBy: "~").first ?? fileName(asset)
            var lines = updated.components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() where line.contains(logical) {
                var fields = line.components(separatedBy: ",")
                guard fields.count > 4 else { continue }
                func value(_ at: Int) -> String {
                    at < fields.count ? fields[at].trimmingCharacters(in: .whitespaces) : ""
                }
                // Which pair describes the stored bytes? Prefer the size, then
                // the digest, of both the stored bytes and the bundle they
                // expand to; if the manifest records another compression of
                // the same bundle, fall back to "the larger pair is the other".
                let expanded = GzipData.decompress(current)
                let expandedStored = expanded.map { PatchPath.sha1Base64($0) }
                let storedIsFirst: Bool
                if let size = Int(value(2)), size == current.count {
                    storedIsFirst = true
                } else if let size = Int(value(5)), size == current.count {
                    storedIsFirst = false
                } else if let expanded, let size = Int(value(2)), size == expanded.count {
                    storedIsFirst = false
                } else if let expanded, let size = Int(value(5)), size == expanded.count {
                    storedIsFirst = true
                } else if value(1) == currentStored {
                    storedIsFirst = true
                } else if value(4) == currentStored {
                    storedIsFirst = false
                } else if let expandedStored, value(1) == expandedStored {
                    storedIsFirst = false
                } else if let expandedStored, value(4) == expandedStored {
                    storedIsFirst = true
                } else {
                    storedIsFirst = (Int(value(5)) ?? 0) >= (Int(value(2)) ?? 0)
                }
                let storedDigest = storedIsFirst ? 1 : 4
                let storedSize = storedDigest + 1
                let otherDigest = storedIsFirst ? 4 : 1
                let otherSize = otherDigest + 1
                var rowChanged = false
                func set(_ at: Int, _ text: String, _ note: String) {
                    guard at < fields.count else { return }
                    guard fields[at].trimmingCharacters(in: .whitespaces) != text else { return }
                    fields[at] = text
                    notes.append(note)
                    rowChanged = true
                }
                set(storedDigest, newStored, "stored/base64")
                set(storedSize, String(stored.count), "stored/size")
                if let other = patchedCounterpart {
                    set(otherDigest, PatchPath.sha1Base64(other), "other/base64")
                    set(otherSize, String(other.count), "other/size")
                }
                guard rowChanged else { continue }
                lines[index] = fields.joined(separator: ",")
                changed = true
                matchedCurrent = true
            }
            updated = lines.joined(separator: "\n")
        }

        guard matchedCurrent else {
            log(
                "patch: \(manifest) (\(raw.count) B) does not record a digest of \(fileName(asset)) — refusing to patch",
                level: .error
            )
            for line in diagnosticLines(in: text, for: asset).prefix(4) {
                log("patch: manifest row: \(line)", level: .error)
            }
            let currentDigests = digestPairs(old: current, new: patched)
                .map { "\($0.name)=\($0.spellings[0].value.old)" }
                .joined(separator: ", ")
            log("patch: looked for \(currentDigests)", level: .error)
            throw PatchServiceError.invalidPackage(
                "\(manifest) does not record a digest of \(fileName(asset)); the log lists the manifest row"
            )
        }

        guard changed else {
            log("patch: \(manifest) already records the patched digest", level: .info)
            return nil
        }

        let summary = notes.joined(separator: ", ")
        let rows = changedRows(before: text, after: updated)
        log("patch: \(manifest) — updated \(summary)", level: .info)
        return Replacement(
            path: manifest,
            data: Data(updated.utf8),
            summary: summary,
            rows: rows
        )
    }

    // MARK: - Row tracking

    /// The row identity is its first column: `avatar/assetindexer`, `cache_res`
    /// or whatever the manifest uses. Digests are only replaced inside rows, so
    /// the line count is unchanged and rows can be compared by position.
    private static func rowKey(_ line: String) -> String {
        line.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    private static func changedRows(before: String, after: String) -> [RowChange] {
        let oldLines = before.components(separatedBy: "\n")
        let newLines = after.components(separatedBy: "\n")
        guard oldLines.count == newLines.count else { return [] }
        var rows: [RowChange] = []
        for index in oldLines.indices where oldLines[index] != newLines[index] {
            let key = rowKey(oldLines[index])
            guard !key.isEmpty else { continue }
            rows.append(
                RowChange(key: key, original: oldLines[index], patched: newLines[index])
            )
        }
        return rows
    }

    /// True while the manifest still records the patched values this app wrote.
    /// Free Fire rewrites `fileinfo` on launch; a row that no longer matches is
    /// the only reliable sign that the patch is gone.
    static func rowsIntact(
        _ rows: [RowChange],
        in manifest: String,
        fileSystem: PatchFileSystem
    ) -> Bool {
        guard let raw = try? fileSystem.read(manifest),
              let text = String(data: raw, encoding: .utf8)
                ?? String(data: raw, encoding: .isoLatin1) else {
            return false
        }
        let lines = text.components(separatedBy: "\n")
        for row in rows {
            let present = lines.contains { line in
                line == row.patched && rowKey(line) == row.key
            }
            if !present { return false }
        }
        return true
    }

    /// Puts back only this patch's rows, leaving every other row (and another
    /// patch's values) untouched. Returns false when nothing had to change.
    @discardableResult
    static func restoreRows(
        _ rows: [RowChange],
        in manifest: String,
        fileSystem: PatchFileSystem
    ) throws -> Bool {
        guard try fileSystem.exists(manifest) else { return false }
        let raw = try fileSystem.read(manifest)
        guard let text = String(data: raw, encoding: .utf8)
                ?? String(data: raw, encoding: .isoLatin1) else {
            return false
        }
        var lines = text.components(separatedBy: "\n")
        var changed = false
        for row in rows {
            guard let index = lines.firstIndex(where: {
                $0 == row.patched && rowKey($0) == row.key
            }) else { continue }
            lines[index] = row.original
            changed = true
        }
        guard changed else { return false }
        try fileSystem.write(Data(lines.joined(separator: "\n").utf8), to: manifest)
        return true
    }

    // MARK: - Digests

    private struct Digests {
        let name: String
        let spellings: [(value: (old: String, new: String), label: String)]
    }

    private static func digestPairs(old: Data, new: Data) -> [Digests] {
        [
            Digests(
                name: "md5",
                spellings: [
                    ((md5Hex(old), md5Hex(new)), "hex"),
                    ((md5Hex(old).uppercased(), md5Hex(new).uppercased()), "HEX")
                ]
            ),
            Digests(
                name: "sha1",
                spellings: [
                    ((sha1Hex(old), sha1Hex(new)), "hex"),
                    ((sha1Hex(old).uppercased(), sha1Hex(new).uppercased()), "HEX"),
                    ((PatchPath.sha1Base64(old), PatchPath.sha1Base64(new)), "base64")
                ]
            ),
            Digests(
                name: "sha256",
                spellings: [
                    ((PatchPath.sha256Hex(old), PatchPath.sha256Hex(new)), "hex"),
                    ((PatchPath.sha256Hex(old).uppercased(), PatchPath.sha256Hex(new).uppercased()), "HEX")
                ]
            )
        ]
    }

    static func md5Hex(_ data: Data) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_MD5(buffer.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func sha1Hex(_ data: Data) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA1(buffer.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Diagnostics

    private static func fileName(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    /// The manifest rows that could describe this asset. Rows are matched on
    /// the physical file name, its `<logical>.<token>` stem and the logical
    /// name before the extension, because the manifest may use any of them.
    private static func diagnosticLines(in text: String, for asset: String) -> [String] {
        let name = fileName(asset)
        let logical = name.components(separatedBy: "~").first ?? name
        var needles = [name, logical]
        let stem = (logical as NSString).deletingPathExtension
        if stem != logical, !stem.isEmpty {
            needles.append(stem)
        }
        return text
            .components(separatedBy: .newlines)
            .filter { line in
                needles.contains { !$0.isEmpty && line.contains($0) }
            }
    }
}
