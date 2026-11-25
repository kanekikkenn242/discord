import Foundation
import UIKit
import CommonCrypto

/// License gate modeled on the X.app binary (com.apple.mobile.MobileHouseArrest,
/// version 5.2.0). X.app validates a license on launch, shows one of eleven
/// rejection reasons, binds the key to the device and records an expiry date.
/// This implementation keeps that exact vocabulary but validates locally: no
/// key is ever sent to a third-party server.
enum LicenseReason: String, CaseIterable {
    case keyMissing = "key_missing"
    case gateUnavailable = "gate_unavailable"
    case rejected = "rejected"
    case expired = "expired"
    case revoked = "revoked"
    case signedOut = "signed_out"
    case endpoint = "endpoint"
    case noResponse = "no_response"
    case unreadableResponse = "unreadable_response"
    case http = "http"
    case rejectedByServer = "rejected_by_server"

    var message: String {
        switch self {
        case .keyMissing: return "No key entered"
        case .gateUnavailable: return "License gate unavailable"
        case .rejected: return "Key rejected — check the code and try again"
        case .expired: return "Key expired"
        case .revoked: return "Key revoked"
        case .signedOut: return "Account signed out"
        case .endpoint: return "License endpoint unavailable"
        case .noResponse: return "No response from license gate"
        case .unreadableResponse: return "Unreadable license response"
        case .http: return "License request failed"
        case .rejectedByServer: return "Key rejected by server"
        }
    }
}

enum ActivationStatus: String {
    case granted = "granted"
    case account = "account"
    case password = "password"
    case expiresAt = "expires_at"
}

enum PairingState: String {
    case failed, cancelled, ready, enterPin = "enter_pin"
    case developerMode = "developer_mode", waiting, starting, idle
    case needsSession = "needs_session"
}

struct LicenseDecision: Equatable {
    let active: Bool
    let reason: LicenseReason?
    let status: ActivationStatus?
    let expiresAt: Date?
    let deviceID: String
    let legacy: Bool

    static let inactive = LicenseDecision(
        active: false, reason: .keyMissing, status: nil,
        expiresAt: nil, deviceID: "", legacy: false
    )
}

enum LicenseGate {
    private static let salt = "zada-license-v1"
    private static let deviceStore = "discord.license.device"
    private static let revokedStore = "discord.license.revoked"

    /// Keys issued by the website look like `X-20261231-AB12CD34-9F2A`.
    private static let modernPattern = #"^X-([0-9]{8})-([A-Z0-9]{8})-([A-F0-9]{4})$"#
    private static let legacyPattern = #"^[A-Z0-9][A-Z0-9\-]{7,63}$"#

    // MARK: - Decision

    static func check(_ raw: String) -> LicenseDecision {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let device = deviceID()

        guard !key.isEmpty else {
            return decision(false, .keyMissing, nil, nil, device, false)
        }

        if let revoked = UserDefaults.standard.stringArray(forKey: revokedStore),
           revoked.contains(key) {
            return decision(false, .revoked, nil, nil, device, false)
        }

        if key.hasPrefix("X-") {
            return checkModern(key, device: device)
        }
        return checkLegacy(key, device: device)
    }

    private static func checkModern(_ key: String, device: String) -> LicenseDecision {
        guard let match = regexMatch(modernPattern, in: key),
              match.count >= 4 else {
            return decision(false, .rejected, nil, nil, device, false)
        }
        let dateText = match[1]
        let payload = match[2]
        let provided = match[3]

        guard expectedChecksum(date: dateText, payload: payload) == provided else {
            return decision(false, .rejected, nil, nil, device, false)
        }
        guard let expiry = dateFormatter.date(from: dateText) else {
            return decision(false, .unreadableResponse, nil, nil, device, false)
        }
        guard expiry > Date() else {
            return decision(false, .expired, .expiresAt, expiry, device, false)
        }
        guard deviceMatches(device) else {
            return decision(false, .revoked, nil, expiry, device, false)
        }
        return decision(true, nil, .granted, expiry, device, false)
    }

    private static func checkLegacy(_ key: String, device: String) -> LicenseDecision {
        guard regexMatch(legacyPattern, in: key) != nil else {
            return decision(false, .rejected, nil, nil, device, false)
        }
        guard deviceMatches(device) else {
            return decision(false, .revoked, nil, nil, device, false)
        }
        // Keys issued before the X-style gate have no embedded expiry. Use the
        // recorded activation date plus one year so existing users keep access.
        let start = UserDefaults.standard.object(forKey: "discord.activation.date") as? Date ?? Date()
        let expiry = Calendar.current.date(byAdding: .year, value: 1, to: start)
        return decision(true, nil, .granted, expiry, device, true)
    }

    private static func decision(
        _ active: Bool,
        _ reason: LicenseReason?,
        _ status: ActivationStatus?,
        _ expiry: Date?,
        _ device: String,
        _ legacy: Bool
    ) -> LicenseDecision {
        LicenseDecision(
            active: active, reason: reason, status: status,
            expiresAt: expiry, deviceID: device, legacy: legacy
        )
    }

    // MARK: - Device binding

    static func deviceID() -> String {
        let uuid = UIDevice.current.identifierForVendor?.uuidString ?? "no-vendor-id"
        return sha256Hex(salt + "|device|" + uuid).prefix(16).uppercased()
    }

    private static func deviceMatches(_ device: String) -> Bool {
        let defaults = UserDefaults.standard
        guard let stored = defaults.string(forKey: deviceStore), !stored.isEmpty else {
            defaults.set(device, forKey: deviceStore)
            return true
        }
        return stored == device
    }

    static func forgetDevice() {
        UserDefaults.standard.removeObject(forKey: deviceStore)
    }

    // MARK: - Crypto / parsing

    static func expectedChecksum(date: String, payload: String) -> String {
        String(sha256Hex("\(salt)|\(date)|\(payload)").prefix(4).uppercased())
    }

    private static func regexMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        var parts: [String] = []
        for index in 0..<match.numberOfRanges {
            guard let r = Range(match.range(at: index), in: text) else { continue }
            parts.append(String(text[r]))
        }
        return parts
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    static func sha256Hex(_ text: String) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        text.data(using: .utf8)?.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
