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

    private let keyStore = "discord.activation.key"
    private let dateStore = "discord.activation.date"

    init() {
        if let stored = UserDefaults.standard.string(forKey: keyStore), !stored.isEmpty {
            activatedKeyMasked = Self.mask(stored)
            activatedAt = UserDefaults.standard.object(forKey: dateStore) as? Date
            state = .active
        }
    }

    var isActivated: Bool {
        state.isActive
    }

    var isBusy: Bool {
        state == .activating
    }

    var statusText: String {
        switch state {
        case .active:
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

        guard candidate.range(of: #"^[A-Z0-9][A-Z0-9\-]{7,63}$"#, options: .regularExpression) != nil else {
            errorMessage = "Enter a valid access key (letters, numbers and dashes)."
            state = .failed("Invalid key")
            return
        }

        errorMessage = nil
        state = .activating
        try? await Task.sleep(nanoseconds: 900_000_000)

        // The public rebuild keeps activation local: no key is sent to a
        // third-party licence server. The X backend is intentionally not
        // reimplemented here.
        UserDefaults.standard.set(candidate, forKey: keyStore)
        UserDefaults.standard.set(Date(), forKey: dateStore)
        activatedKeyMasked = Self.mask(candidate)
        activatedAt = Date()
        key = ""
        state = .active
        log("activation: key accepted locally (\(activatedKeyMasked))", level: .success)
    }

    func deactivate() {
        UserDefaults.standard.removeObject(forKey: keyStore)
        UserDefaults.standard.removeObject(forKey: dateStore)
        activatedKeyMasked = ""
        activatedAt = nil
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
