import Foundation

/// The avatar asset Free Fire loads is not the build the packages were made
/// from: the hot-update copy in the container is a newer serialization
/// (46,096 B against the shipped 46,640 B). Replacing that file with a packaged
/// blob would hand the game someone else's build, so the blob is diffed against
/// the shipped base and only the changed bytes are shifted into the device's own
/// file. Every byte is proven against the base before it is written; when the
/// two builds do not differ by one contiguous edit nothing is touched.
enum AssetShift {
    static let baseResource = "asset_avatar_base"
    static let baseExtension = "raw"

    static func baseData() -> Data? {
        guard let url = Bundle.main.url(
            forResource: baseResource,
            withExtension: baseExtension
        ) else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    struct Mapping {
        /// Offset where the two builds stop being byte-identical.
        let editAt: Int
        /// Device length minus base length, so a shorter device build is negative.
        let delta: Int

        func deviceOffset(for baseOffset: Int) -> Int? {
            if baseOffset < editAt {
                return baseOffset
            }
            let mapped = baseOffset + delta
            return mapped >= editAt ? mapped : nil
        }
    }

    /// The offset map is only trusted when the two files share a prefix and a
    /// suffix around exactly one insertion or deletion.
    static func mapping(base: Data, device: Data) -> Mapping? {
        let a = [UInt8](base)
        let b = [UInt8](device)
        let length = min(a.count, b.count)
        guard length > 0 else { return nil }

        var prefix = 0
        while prefix < length, a[prefix] == b[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < length - prefix, a[a.count - 1 - suffix] == b[b.count - 1 - suffix] {
            suffix += 1
        }
        guard prefix + suffix + abs(a.count - b.count) == max(a.count, b.count) else {
            return nil
        }
        return Mapping(editAt: prefix, delta: b.count - a.count)
    }

    /// Returns the device asset with only the bytes the patch changed.
    static func apply(patched: Data, to device: Data, base: Data) -> Data? {
        guard patched.count == base.count,
              let mapping = mapping(base: base, device: device) else {
            return nil
        }
        let baseBytes = [UInt8](base)
        let patchedBytes = [UInt8](patched)
        var deviceBytes = [UInt8](device)

        var written = 0
        var index = 0
        while index < baseBytes.count {
            guard patchedBytes[index] != baseBytes[index] else {
                index += 1
                continue
            }
            let start = index
            while index < baseBytes.count, patchedBytes[index] != baseBytes[index] {
                index += 1
            }
            for offset in start..<index {
                guard let target = mapping.deviceOffset(for: offset),
                      target >= 0,
                      target < deviceBytes.count else {
                    log(
                        "patch: device asset cannot hold byte \(offset) — refusing to patch",
                        level: .warning
                    )
                    return nil
                }
                guard deviceBytes[target] == baseBytes[offset] else {
                    log(
                        "patch: device asset differs at \(target) — the shipped offsets do not apply",
                        level: .warning
                    )
                    return nil
                }
                deviceBytes[target] = patchedBytes[offset]
                written += 1
            }
        }

        guard written > 0 else { return nil }
        log(
            "patch: shifted \(written) byte(s) into the device asset"
                + " (edit at \(mapping.editAt), delta \(mapping.delta))",
            level: .info
        )
        return Data(deviceBytes)
    }
}
