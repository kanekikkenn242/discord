import Foundation

/// Free Fire classifies a hit as HEAD or TORSO from `HitDetectColliderHelper`
/// objects stored in the `cache_res` bundle. The avatar index only carries the
/// bone scales, so relabelling `bone_Neck` there cannot change the damage type.
///
/// Every helper has the same serialized prefix: a PPtr-shaped field, the
/// script GUID, a zero word and then the `ColliderType` int32. That prefix is
/// stable across game builds even when the bundle itself is a different
/// serialization, so the helpers can be matched by occurrence order and
/// rewritten to HEAD without trusting absolute offsets.
enum ColliderShift {
    private static let marker: [UInt8] = [
        0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0xcd, 0xbe, 0x69, 0x85, 0x73, 0x79, 0x1f, 0x4b,
        0x00, 0x00, 0x00, 0x00
    ]

    private static func fields(in data: Data) -> [Int] {
        let bytes = [UInt8](data)
        var found: [Int] = []
        var i = 0
        while i + marker.count + 4 <= bytes.count {
            if Array(bytes[i..<i + marker.count]) == marker {
                found.append(i + marker.count)
                i += marker.count + 4
            } else {
                i += 1
            }
        }
        return found
    }

    /// Rewrites every recognized collider helper to HEAD (type 1). Returns the
    /// patched bytes and how many fields changed, or nil when the device and
    /// the package do not expose the same helper layout.
    static func makeAllHead(in device: Data, reference: Data) -> (Data, Int)? {
        let deviceFields = fields(in: device)
        let referenceFields = fields(in: reference)
        guard !deviceFields.isEmpty, deviceFields.count == referenceFields.count else {
            return nil
        }

        var out = [UInt8](device)
        var changed = 0
        for typeOffset in deviceFields {
            guard typeOffset + 4 <= out.count else { continue }
            let bytes = Array(out[typeOffset..<typeOffset + 4])
            if bytes != [1, 0, 0, 0] {
                out[typeOffset..<typeOffset + 4] = [1, 0, 0, 0]
                changed += 1
            }
        }
        guard changed > 0 else { return nil }
        return (Data(out), changed)
    }
}
