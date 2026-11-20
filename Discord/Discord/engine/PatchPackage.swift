import Foundation
import CryptoKit
import CommonCrypto

struct PatchRule: Equatable {
    let source: String
    let destination: String
}

struct PatchPackage {
    let metaName: String
    let rawLength: Int?
    let compressed: Bool
    let files: [String: Data]
    let digests: [String: String]
    let rules: [PatchRule]
    let sourceURL: URL

    static let sharedPassword = "shared-server-secret"
    static let headerSize = 128

    var displayName: String {
        metaName.isEmpty ? sourceURL.deletingPathExtension().lastPathComponent : metaName
    }

    var totalPayloadBytes: Int {
        files.values.reduce(0) { $0 + $1.count }
    }

    var needsCacheToken: Bool {
        rules.contains { $0.destination.contains("{gz}") }
    }

    static func load(from url: URL, password: String = sharedPassword) throws -> PatchPackage {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count >= headerSize else {
            throw PatchServiceError.invalidPackage("file is shorter than the 128-byte header")
        }

        let magic = String(data: data.subdata(in: 0..<4), encoding: .ascii) ?? ""
        guard magic == "3105" else {
            throw PatchServiceError.invalidPackage("bad magic '\(magic)'")
        }

        let version = readU32(data, 4)
        guard version == 1 else {
            throw PatchServiceError.unsupportedVersion(Int(version))
        }

        let salt = data.subdata(in: 8..<24)
        let iterations = readU32(data, 24)
        guard iterations > 0, iterations <= 1_000_000 else {
            throw PatchServiceError.invalidPackage("unreasonable PBKDF2 iteration count \(iterations)")
        }

        let wrappedKeyLength = readU32(data, 28)
        guard wrappedKeyLength == 32 else {
            throw PatchServiceError.invalidPackage("wrapped key length is \(wrappedKeyLength), expected 32")
        }

        let wrappedKey = data.subdata(in: 32..<64)
        let wrapNonce = data.subdata(in: 64..<76)
        let wrapTag = data.subdata(in: 76..<92)
        let payloadNonce = data.subdata(in: 92..<104)
        let payloadTag = data.subdata(in: 104..<120)
        let cipherLength = readU64(data, 120)

        let expectedSize = UInt64(headerSize) + cipherLength
        guard UInt64(data.count) == expectedSize else {
            throw PatchServiceError.invalidPackage(
                "size \(data.count) does not match header length \(expectedSize)"
            )
        }

        let kek = try deriveKey(
            password: password,
            salt: salt,
            iterations: UInt32(iterations)
        )

        let contentKey: Data
        do {
            let box = try AES.GCM.SealedBox(
                nonce: try AES.GCM.Nonce(data: wrapNonce),
                ciphertext: wrappedKey,
                tag: wrapTag
            )
            contentKey = try AES.GCM.open(box, using: SymmetricKey(data: kek))
        } catch {
            throw PatchServiceError.decryptionFailed("content key unwrap failed")
        }

        guard contentKey.count == 32 else {
            throw PatchServiceError.decryptionFailed("content key has wrong length")
        }

        let ciphertext = data.subdata(in: headerSize..<(headerSize + Int(cipherLength)))
        let plaintext: Data
        do {
            let box = try AES.GCM.SealedBox(
                nonce: try AES.GCM.Nonce(data: payloadNonce),
                ciphertext: ciphertext,
                tag: payloadTag
            )
            plaintext = try AES.GCM.open(box, using: SymmetricKey(data: contentKey))
        } catch {
            throw PatchServiceError.decryptionFailed("payload authentication failed")
        }

        return try parse(plaintext: plaintext, sourceURL: url)
    }

    private static func parse(plaintext: Data, sourceURL: URL) throws -> PatchPackage {
        guard let root = try JSONSerialization.jsonObject(with: plaintext) as? [String: Any] else {
            throw PatchServiceError.invalidPackage("payload is not a JSON object")
        }

        guard let fileMap = root["files"] as? [String: String], !fileMap.isEmpty else {
            throw PatchServiceError.invalidPackage("payload has no files")
        }

        var files: [String: Data] = [:]
        for (name, base64) in fileMap {
            guard let bytes = Data(base64Encoded: base64, options: []) else {
                throw PatchServiceError.invalidPackage("file '\(name)' is not valid Base64")
            }
            files[name] = bytes
        }

        let digestMap = (root["digests"] as? [String: String]) ?? [:]
        var digests: [String: String] = [:]
        for (name, value) in digestMap {
            digests[name] = value.lowercased()
        }

        guard let rawRules = root["rules"] as? [[String: Any]], !rawRules.isEmpty else {
            throw PatchServiceError.invalidPackage("payload has no rules")
        }

        var rules: [PatchRule] = []
        for entry in rawRules {
            guard let source = entry["src"] as? String,
                  let destination = entry["dst"] as? String,
                  !source.isEmpty, !destination.isEmpty else {
                throw PatchServiceError.invalidPackage("a rule is missing src/dst")
            }
            _ = try PatchPath.safeRelative(destination)
            guard files[source] != nil else {
                throw PatchServiceError.invalidPackage("rule source '\(source)' is not in files")
            }
            guard let digest = digests[source], digest.count == 64 else {
                throw PatchServiceError.invalidPackage("rule source '\(source)' has no SHA-256 digest")
            }
            let actual = PatchPath.sha256Hex(files[source]!)
            guard actual == digest else {
                throw PatchServiceError.digestMismatch(expected: digest, actual: actual, file: source)
            }
            rules.append(PatchRule(source: source, destination: destination))
        }

        let destinations = Set(rules.map { $0.destination })
        guard destinations.count == rules.count else {
            throw PatchServiceError.invalidPackage("two rules target the same path")
        }

        let meta = (root["meta"] as? [String: Any]) ?? [:]
        let metaName = (meta["name"] as? String)
            ?? sourceURL.deletingPathExtension().lastPathComponent

        var rawLength: Int?
        if let value = meta["rawLength"] as? Int {
            rawLength = value
        } else if let value = meta["rawLength"] as? NSNumber {
            rawLength = value.intValue
        }

        var compressed = false
        if let value = meta["compressed"] as? Bool {
            compressed = value
        } else if let value = meta["compressed"] as? NSNumber {
            compressed = value.boolValue
        }

        return PatchPackage(
            metaName: metaName,
            rawLength: rawLength,
            compressed: compressed,
            files: files,
            digests: digests,
            rules: rules,
            sourceURL: sourceURL
        )
    }

    private static func deriveKey(password: String, salt: Data, iterations: UInt32) throws -> Data {
        var derived = [UInt8](repeating: 0, count: 32)
        let passwordBytes = Array(password.utf8CString)
        let status = passwordBytes.withUnsafeBufferPointer { passwordBuffer -> Int32 in
            salt.withUnsafeBytes { saltBuffer -> Int32 in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBuffer.baseAddress,
                    passwordBytes.count - 1,
                    saltBuffer.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    iterations,
                    &derived,
                    derived.count
                )
            }
        }
        guard status == kCCSuccess else {
            throw PatchServiceError.decryptionFailed("PBKDF2 failed with status \(status)")
        }
        return Data(derived)
    }

    private static func readU32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private static func readU64(_ data: Data, _ offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 {
            value |= UInt64(data[offset + index]) << (8 * UInt64(index))
        }
        return value
    }
}
