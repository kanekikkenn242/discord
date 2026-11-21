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
            guard let start = locate(run, in: deviceBytes, base: baseBytes) else {
                log(
                    "patch: base offset \(run.lowerBound) is not anchored in the device asset — refusing to patch",
                    level: .warning
                )
                return nil
            }
            guard start >= 0, start + run.count <= deviceBytes.count else {
                log(
                    "patch: device asset cannot hold base offset \(run.lowerBound) — refusing to patch",
                    level: .warning
                )
                return nil
            }
            // A newer game asset can already contain a value from the patch.
            // Accept that run only when every byte exactly matches the package;
            // any other divergence remains an incompatible-build failure.
            if deviceBytes[start..<start + run.count].elementsEqual(patchedBytes[run]) {
                alreadyApplied += run.count
                placements.append("\(run.lowerBound)->\(start) (already applied)")
                continue
            }
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
            for offset in 0..<run.count {
                deviceBytes[start + offset] = patchedBytes[run.lowerBound + offset]
                written += 1
            }
            placements.append("\(run.lowerBound)->\(start)")
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

    /// Finds where `run` lives in the device build: the window of untouched
    /// bytes that touches the run must occur exactly once there, and the run
    /// itself follows that window. A unique 32–128 byte anchor makes a wrong
    /// placement implausible, and the caller still proves every device byte.
    private static func locate(
        _ run: Range<Int>,
        in device: [UInt8],
        base: [UInt8]
    ) -> Int? {
        for length in anchorLengths {
            // Anchor ending exactly where the run starts.
            if run.lowerBound >= length {
                let anchor = run.lowerBound - length..<run.lowerBound
                if let match = uniqueMatch(of: base, in: device, at: anchor) {
                    let start = match + length
                    if start + run.count <= device.count {
                        return start
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
                        return start
                    }
                }
            }
        }
        return nil
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
