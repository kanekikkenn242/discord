import Foundation

/// The avatar asset Free Fire loads is not the build the packages were made
/// from: the hot-update copy in the container is a newer serialization
/// (46,096 B against the shipped 46,640 B). Replacing that file with a packaged
/// blob would hand the game someone else's build, so the packaged blob is
/// diffed against the shipped base and only the bytes the patch changed are
/// carried over, at the place the device build keeps them.
///
/// The two builds differ by more than one contiguous edit, so the slot is not
/// derived from a length delta: each changed run is anchored by a unique window
/// of untouched bytes that ends exactly where the run begins (or starts where
/// it ends), and the run is written only after the device bytes there are
/// proven to equal the base. When no anchor is unique nothing is written.
enum AssetShift {
    static let baseResource = "asset_avatar_base"
    static let baseExtension = "raw"

    /// Longest run that is still treated as a field edit. A float vector is a
    /// dozen bytes; a larger run means the package is not this kind of patch.
    private static let maxRun = 4_096
    /// Anchor lengths, tried shortest first so a nearby edit still leaves one
    /// usable window.
    private static let anchorLengths = [32, 64, 128]

    static func baseData() -> Data? {
        guard let url = Bundle.main.url(
            forResource: baseResource,
            withExtension: baseExtension
        ) else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    /// Returns the device asset with only the bytes the patch changed.
    static func apply(patched: Data, to device: Data, base: Data) -> Data? {
        guard patched.count == base.count, !device.isEmpty else { return nil }

        let baseBytes = [UInt8](base)
        let patchedBytes = [UInt8](patched)
        var deviceBytes = [UInt8](device)

        // The hit classifier reads the serialized field name. A package may
        // carry that rename itself (`aimneck_hs` writes `bone_Head` as
        // `bone_Neck`), so nothing is relabelled here: doing it at apply time
        // would rewrite the package's own names back and cancel the patch.

        let runs = changedRuns(patchedBytes, against: baseBytes)
        guard !runs.isEmpty else { return nil }
        guard runs.allSatisfy({ $0.count <= maxRun }) else {
            log(
                "patch: the package changes \(runs.map(\.count).max() ?? 0) contiguous byte(s) — that is not a field edit, refusing to patch",
                level: .warning
            )
            return nil
        }

        log(
            "patch: device asset vs base — \(deviceBytes.count) B vs \(baseBytes.count) B, common prefix \(commonPrefix(baseBytes, deviceBytes)), common suffix \(commonSuffix(baseBytes, deviceBytes)); package edits \(runs.map { "\($0.lowerBound)+\($0.count)" }.joined(separator: ", "))",
            level: .info
        )

        var placements: [String] = []
        var written = 0
        var alreadyApplied = 0

        for run in runs {
            guard let placement = locate(run, in: deviceBytes, base: baseBytes) else {
                log(
                    "patch: base offset \(run.lowerBound) is not anchored in the device asset — refusing to patch",
                    level: .warning
                )
                return nil
            }
            let start = placement.start
            guard start >= 0, start + run.count <= deviceBytes.count else {
                log(
                    "patch: device asset cannot hold base offset \(run.lowerBound) — refusing to patch",
                    level: .warning
                )
                return nil
            }
            // The device can already carry the patched value — an earlier
            // attempt, or this game build's own default. Treat that slot as
            // satisfied only when every byte matches the package exactly; any
            // other divergence is still an incompatible-build failure.
            if deviceBytes[start..<start + run.count].elementsEqual(patchedBytes[run]) {
                alreadyApplied += run.count
                placements.append("\(run.lowerBound)->\(start) [\(placement.detail), already applied]")
                continue
            }
            if !placement.semantic {
                for offset in 0..<run.count {
                    let target = start + offset
                    guard deviceBytes[target] == baseBytes[run.lowerBound + offset] else {
                        log(
                            "patch: device asset differs at \(target) (base \(run.lowerBound + offset)) — device "
                                + hex(deviceBytes[start..<start + run.count])
                                + ", base " + hex(baseBytes[run]) ,
                            level: .warning
                        )
                        return nil
                    }
                }
            }
            for offset in 0..<run.count {
                deviceBytes[start + offset] = patchedBytes[run.lowerBound + offset]
                written += 1
            }
            placements.append("\(run.lowerBound)->\(start) [\(placement.detail)]")
        }

        guard written > 0 || alreadyApplied > 0 else { return nil }
        log(
            "patch: shifted \(written) byte(s), already present \(alreadyApplied) byte(s)"
                + " (\(placements.count) slot(s): \(placements.joined(separator: ", ")))",
            level: .info
        )
        return Data(deviceBytes)
    }

    private static func commonPrefix(_ a: [UInt8], _ b: [UInt8]) -> Int {
        let length = min(a.count, b.count)
        var index = 0
        while index < length, a[index] == b[index] { index += 1 }
        return index
    }

    private static func commonSuffix(_ a: [UInt8], _ b: [UInt8]) -> Int {
        let length = min(a.count, b.count)
        var count = 0
        while count < length, a[a.count - 1 - count] == b[b.count - 1 - count] { count += 1 }
        return count
    }

    private static func hex<C: Collection>(_ bytes: C) -> String where C.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Contiguous runs of bytes that differ between the packaged blob and the
    /// shipped base. These are exactly the fields the package edits.
    private static func changedRuns(_ patched: [UInt8], against base: [UInt8]) -> [Range<Int>] {
        var runs: [Range<Int>] = []
        var index = 0
        while index < base.count {
            guard patched[index] != base[index] else {
                index += 1
                continue
            }
            let start = index
            while index < base.count, patched[index] != base[index] {
                index += 1
            }
            runs.append(start..<index)
        }
        return runs
    }

    private struct Placement {
        let start: Int
        let detail: String
        /// A bone marker is a strong anchor: the device can already carry a
        /// different float value (a previous profile or this build's own
        /// default), so the base-byte equality check does not apply.
        let semantic: Bool
    }

    /// Finds where `run` lives in the device build.
    ///
    /// A byte window next to the run is tried first, but serialized float
    /// tables repeat the same `00 00 80 3f` patterns, so a 32–128 byte window
    /// is usually *not* unique — which is exactly why the first apply failed.
    /// The reliable anchor is the length-prefixed `bone_*` name that follows
    /// each float triple: it is a stable field name across game builds. The
    /// distance from the run to that name is fixed, so the same name (paired by
    /// occurrence order when a rig appears twice) gives the device offset.
    private static func locate(
        _ run: Range<Int>,
        in device: [UInt8],
        base: [UInt8]
    ) -> Placement? {
        if let semantic = semanticPlacement(run, in: device, base: base) {
            return semantic
        }
        for length in anchorLengths {
            // Anchor ending exactly where the run starts.
            if run.lowerBound >= length {
                let anchor = run.lowerBound - length..<run.lowerBound
                if let match = uniqueMatch(of: base, in: device, at: anchor) {
                    let start = match + length
                    if start + run.count <= device.count {
                        return Placement(start: start, detail: "byte window \(length) before", semantic: false)
                    }
                }
            }
            // Anchor starting exactly where the run ends.
            if run.upperBound + length <= base.count {
                let anchor = run.upperBound..<run.upperBound + length
                if let match = uniqueMatch(of: base, in: device, at: anchor),
                   match >= run.count {
                    let start = match - run.count
                    if start + run.count <= device.count {
                        return Placement(start: start, detail: "byte window \(length) after", semantic: false)
                    }
                }
            }
        }
        return nil
    }

    /// Replaces the nine-byte field name `bone_Neck` with `bone_Head` in
    /// place. Returns how many fields were relabelled.
    private static func relabelNeckAsHead(in asset: inout [UInt8]) -> Int {
        let neck: [UInt8] = Array("bone_Neck".utf8)
        let head: [UInt8] = Array("bone_Head".utf8)
        guard neck.count == head.count else { return 0 }
        var count = 0
        var i = 0
        while i + neck.count <= asset.count {
            if Array(asset[i..<i + neck.count]) == neck {
                for j in 0..<head.count { asset[i + j] = head[j] }
                count += 1
                i += neck.count
            } else {
                i += 1
            }
        }
        return count
    }

    /// All `bone_<Name>` field markers in a serialized asset: the u32 length
    /// prefix plus the name itself. Digits matter — `bone_Spine1` is one of
    /// the edited slots and must not be skipped.
    private static func boneMarkers(in asset: [UInt8]) -> [(range: Range<Int>, bytes: [UInt8])] {
        var result: [(range: Range<Int>, bytes: [UInt8])] = []
        let n = asset.count
        var i = 0
        while i + 5 <= n {
            if asset[i] == 0x62, asset[i + 1] == 0x6f, asset[i + 2] == 0x6e,
               asset[i + 3] == 0x65, asset[i + 4] == 0x5f { // "bone_"
                var j = i + 5
                while j < n {
                    let c = asset[j]
                    let fieldChar = (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5a) ||
                                    (c >= 0x61 && c <= 0x7a) || c == 0x5f
                    if !fieldChar { break }
                    j += 1
                }
                if j > i + 5, i >= 4 {
                    let declared = Int(asset[i - 4]) | (Int(asset[i - 3]) << 8) |
                                   (Int(asset[i - 2]) << 16) | (Int(asset[i - 1]) << 24)
                    if declared == j - i {
                        result.append((range: (i - 4)..<j, bytes: Array(asset[(i - 4)..<j])))
                    }
                }
                i = j
            } else {
                i += 1
            }
        }
        return result
    }

    private static func semanticPlacement(
        _ run: Range<Int>,
        in device: [UInt8],
        base: [UInt8]
    ) -> Placement? {
        let markers = boneMarkers(in: base)
        for marker in markers {
            let triple = marker.range.lowerBound - 12 // three float32 values
            guard triple >= 0 else { continue }
            guard run.lowerBound >= triple, run.upperBound <= marker.range.lowerBound else { continue }

            // A bone name can occur twice (male/female rigs). Pair occurrences
            // by their order so each rig is patched at its own location.
            let rank = markers.filter {
                $0.bytes == marker.bytes && $0.range.lowerBound < marker.range.lowerBound
            }.count
            let matches = allMatches(of: marker.bytes, in: device)
            let name = Array(marker.bytes.dropFirst(4))
            let deviceMarker: Int
            if name == Array("bone_Head".utf8), matches.count == 4 {
                // A relabelled device holds four head fields: the two real
                // heads at even indices, the two former necks at odd ones.
                let index = rank * 2
                guard index < matches.count else { continue }
                deviceMarker = matches[index]
            } else if rank < matches.count {
                deviceMarker = matches[rank]
            } else if name == Array("bone_Neck".utf8) {
                // Already relabelled: the two neck fields are now head fields
                // at odd positions in offset order (head, neck, head, neck).
                let heads = allMatches(of: Array("bone_Head".utf8), in: device)
                let index = rank * 2 + 1
                guard index < heads.count else { continue }
                deviceMarker = heads[index] - 4 // back up over the u32 length prefix
            } else {
                continue
            }
            let start = deviceMarker - 12 + (run.lowerBound - triple)
            guard start >= 0, start + run.count <= device.count else { continue }
            return Placement(start: start, detail: "bone anchor \(rank)", semantic: true)
        }
        return nil
    }

    private static func allMatches(
        of needle: [UInt8],
        in haystack: [UInt8]
    ) -> [Int] {
        guard !needle.isEmpty, needle.count <= haystack.count else { return [] }
        var result: [Int] = []
        var start = 0
        while start <= haystack.count - needle.count {
            if haystack[start] == needle[0],
               haystack[start..<start + needle.count].elementsEqual(needle) {
                result.append(start)
            }
            start += 1
        }
        return result
    }

    /// Offset of the single occurrence of `base[anchor]` inside `device`, or
    /// nil when it is absent or appears more than once.
    private static func uniqueMatch(
        of base: [UInt8],
        in device: [UInt8],
        at anchor: Range<Int>
    ) -> Int? {
        let needle = Array(base[anchor])
        guard !needle.isEmpty, needle.count <= device.count else { return nil }
        guard let first = needle.first else { return nil }

        let lastStart = device.count - needle.count
        var found: Int?
        var start = 0
        while start <= lastStart {
            if device[start] == first,
               device[start..<start + needle.count].elementsEqual(needle) {
                if found != nil { return nil }
                found = start
            }
            start += 1
        }
        return found
    }
}
