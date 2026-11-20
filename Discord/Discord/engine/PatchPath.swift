import Foundation
import CryptoKit
import CommonCrypto

enum PatchPath {
    /// Normalises a container-relative path. Rejects anything that could
    /// escape the container after normalisation.
    static func safeRelative(_ raw: String) throws -> String {
        var path = raw.replacingOccurrences(of: "\\", with: "/")
        path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, !path.hasPrefix("/") else {
            throw PatchServiceError.unsafePath(raw)
        }
        var components: [String] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".", "":
                continue
            case "..":
                guard !components.isEmpty else {
                    throw PatchServiceError.unsafePath(raw)
                }
                components.removeLast()
            default:
                components.append(String(component))
            }
        }
        guard !components.isEmpty else {
            throw PatchServiceError.unsafePath(raw)
        }
        return components.joined(separator: "/")
    }

    static func canonicalContainerPath(_ path: String) -> String {
        guard !path.isEmpty else { return path }
        if path.hasPrefix("/private/var/") {
            return "/var/" + path.dropFirst("/private/var/".count)
        }
        return path
    }

    static func canonicalBundleID(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let pattern = #"^[A-Za-z0-9][A-Za-z0-9\-\.]*[A-Za-z0-9]$"#
        guard value.range(of: pattern, options: .regularExpression) != nil else {
            return nil
        }
        return value
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func sha256Hex(_ string: String) -> String {
        sha256Hex(Data(string.utf8))
    }

    static func sha1Base64(_ data: Data) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA1(buffer.baseAddress, CC_LONG(data.count), &digest)
        }
        return Data(digest).base64EncodedString()
    }

    /// The `{gz}` token is the URL-escaped Base64 of the gzip file's SHA-1.
    static func escapeBase64Token(_ base64: String) -> String {
        base64
            .replacingOccurrences(of: "+", with: "~2B")
            .replacingOccurrences(of: "/", with: "~2F")
            .replacingOccurrences(of: "=", with: "~3D")
    }

    static func decodeBase64SHA1(_ base64: String) -> String? {
        guard let data = Data(base64Encoded: base64), data.count == 20 else {
            return nil
        }
        return escapeBase64Token(base64)
    }

    /// Both `cache_res.<hash>.gz` and its `.raw.tmp` sibling belong to one
    /// capture group, so a second package never captures a modded file as the
    /// "original".
    static func groupStem(for relativePath: String) -> String {
        if relativePath.hasSuffix(".raw.tmp") {
            return String(relativePath.dropLast(".raw.tmp".count))
        }
        return relativePath
    }

    static func backupKey(bundleID: String, relativePath: String) -> String {
        sha256Hex("\(bundleID)|\(relativePath)")
    }

    static func prettyBytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}
