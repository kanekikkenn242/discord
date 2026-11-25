import Foundation
import Combine

enum ActivationState: Equatable {
    case inactive
    case activating
    case active
    case failed(String)

    var isActive: Bool { self == .active }
}

@MainActor
final class ActivationStore: ObservableObject {
    @Published private(set) var state: ActivationState = .inactive
    @Published var key: String = ""
    @Published var errorMessage: String?
    @Published private(set) var activatedKeyMasked: String = ""
    @Published private(set) var activatedAt: Date?
    @Published private(set) var licenseReason: LicenseReason?
    @Published private(set) var expiresAt: Date?
    @Published private(set) var deviceID: String = ""
    @Published private(set) var isLegacyKey: Bool = false

    private let keyStore = "discord.activation.key"
    private let dateStore = "discord.activation.date"

    init() {
        if let stored = UserDefaults.standard.string(forKey: keyStore), !stored.isEmpty {
            apply(decision: LicenseGate.check(stored), key: stored, persist: false)
        } else {
            deviceID = LicenseGate.deviceID()
        }
    }

    var isActivated: Bool {
        guard state.isActive else { return false }
        if let expiry = expiresAt, expiry <= Date() { return false }
        return true
    }

    var isBusy: Bool {
        state == .activating
    }

    var statusText: String {
        switch state {
        case .active:
            if let expiry = expiresAt {
                return "Active · \(activatedKeyMasked) · until \(expiry.formatted(date: .abbreviated, time: .omitted))"
            }
            return "Active · \(activatedKeyMasked)"
        case .activating:
            return "Activating…"
        case .failed(let message):
            return message
        case .inactive:
            return "No membership"
        }
    }

    func activate() async {
        let candidate = key
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard !candidate.isEmpty else {
            errorMessage = LicenseReason.keyMissing.message
            state = .failed(LicenseReason.keyMissing.message)
            return
        }

        errorMessage = nil
        state = .activating
        try? await Task.sleep(nanoseconds: 450_000_000)

        let decision = LicenseGate.check(candidate)
        apply(decision: decision, key: candidate, persist: decision.active)

        if decision.active {
            key = ""
            log(
                "activation: \(isLegacyKey ? "legacy" : "X-style") key accepted (\(activatedKeyMasked)), expires \(expiresAt?.formatted(date: .abbreviated, time: .omitted) ?? "never")",
                level: .success
            )
        } else {
            log("activation: refused — \(decision.reason?.rawValue ?? "unknown")", level: .warning)
        }
    }

    /// Re-checks a stored key (expiry, revocation, device binding). Called when
    /// the app becomes active so an expired key cannot keep patches unlocked.
    func revalidate() {
        guard let stored = UserDefaults.standard.string(forKey: keyStore), !stored.isEmpty else { return }
        apply(decision: LicenseGate.check(stored), key: stored, persist: false)
    }

    private func apply(decision: LicenseDecision, key stored: String, persist: Bool) {
        licenseReason = decision.reason
        expiresAt = decision.expiresAt
        deviceID = decision.deviceID
        isLegacyKey = decision.legacy
        activatedKeyMasked = Self.mask(stored)

        if decision.active {
            if persist {
                UserDefaults.standard.set(stored, forKey: keyStore)
                UserDefaults.standard.set(Date(), forKey: dateStore)
                activatedAt = Date()
            } else {
                activatedAt = UserDefaults.standard.object(forKey: dateStore) as? Date
            }
            state = .active
            errorMessage = nil
        } else {
            state = .failed(decision.reason?.message ?? LicenseReason.rejected.message)
            errorMessage = decision.reason?.message
        }
    }

    func deactivate() {
        UserDefaults.standard.removeObject(forKey: keyStore)
        UserDefaults.standard.removeObject(forKey: dateStore)
        LicenseGate.forgetDevice()
        activatedKeyMasked = ""
        activatedAt = nil
        licenseReason = nil
        expiresAt = nil
        deviceID = LicenseGate.deviceID()
        isLegacyKey = false
        state = .inactive
        errorMessage = nil
        log("activation: membership removed", level: .warning)
    }

    private static func mask(_ key: String) -> String {
        guard key.count > 8 else { return key }
        let prefix = key.prefix(4)
        let suffix = key.suffix(4)
        return "\(prefix)…\(suffix)"
    }
}
