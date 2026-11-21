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
        patchedGzip: Data? = nil,
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

        // The row also carries the SHA-1 of the gzip representation (column 5).
        // Leaving it at the original value makes the game consider the tree
        // corrupt and re-download it, which is why the patch appeared to apply
        // and then vanished. Replace it with the digest of the patched bytes.
        if let gz = patchedGzip {
            let newGz = PatchPath.sha1Base64(gz)
            let logical = (fileName(asset) as NSString).deletingPathExtension
                .components(separatedBy: "~").first ?? fileName(asset)
            var lines = updated.components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() where line.contains(logical) {
                var fields = line.components(separatedBy: ",")
                guard fields.count > 4 else { continue }
                let old = fields[4].trimmingCharacters(in: .whitespaces)
                var rowChanged = false
                if old != newGz {
                    fields[4] = newGz
                    notes.append("gz/base64")
                    rowChanged = true
                }
                // Column 5 is the gzip byte count. A recompressed asset rarely
                // keeps the exact size, so leaving the shipped value makes the
                // row inconsistent with the digest above it.
                if fields.count > 5 {
                    let oldSize = fields[5].trimmingCharacters(in: .whitespaces)
                    let newSize = String(gz.count)
                    if oldSize != newSize {
                        fields[5] = newSize
                        notes.append("gz/size")
                        rowChanged = true
                    }
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
        log("patch: \(manifest) — updated \(summary)", level: .info)
        return Replacement(path: manifest, data: Data(updated.utf8), summary: summary)
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
