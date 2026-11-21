import Foundation

/// A hot-update asset is content addressed: `assetindexer.U6Zffc4YIR3DslNj3cXvYGAqz58~3D`
/// is `<stem>.<URL-escaped Base64 of the file's SHA-1>`. The engine proves a
/// cached file by that name, so bytes that no longer hash to it are thrown away
/// and downloaded again — which is exactly what happened to the shifted avatar:
/// the write verified, the manifest digest matched, and the file was still
/// replaced on the next launch.
///
/// A patched asset therefore has to be stored under the name of its new bytes.
/// The rule is only used after the current name has been proven to carry the
/// digest of the current bytes, so an asset from a different naming scheme is
/// left alone instead of being renamed on a guess.
enum HotAssetName {
    /// The token a hot-update file with these bytes is named after.
    static func token(for data: Data) -> String {
        PatchPath.escapeBase64Token(PatchPath.sha1Base64(data))
    }

    /// `assetindexer.U6Zffc4…~3D` -> `assetindexer`
    static func stem(of fileName: String) -> String? {
        guard let dot = fileName.firstIndex(of: "."), dot != fileName.startIndex else {
            return nil
        }
        return String(fileName[fileName.startIndex..<dot])
    }

    /// `assetindexer.U6Zffc4…~3D` -> `U6Zffc4…~3D`
    static func tokenPart(of fileName: String) -> String? {
        guard let dot = fileName.firstIndex(of: "."), dot < fileName.index(before: fileName.endIndex) else {
            return nil
        }
        return String(fileName[fileName.index(after: dot)...])
    }

    /// True when the name's token is the digest of `data`, i.e. the naming rule
    /// holds for this file.
    static func carries(_ fileName: String, data: Data) -> Bool {
        guard let part = tokenPart(of: fileName) else { return false }
        return part == token(for: data)
    }

    /// The name `patched` has to be stored under, or nil when the current name
    /// does not follow the digest rule.
    static func name(for patched: Data, replacing fileName: String, current: Data) -> String? {
        guard carries(fileName, data: current), let stem = stem(of: fileName) else {
            return nil
        }
        return stem + "." + token(for: patched)
    }
}
