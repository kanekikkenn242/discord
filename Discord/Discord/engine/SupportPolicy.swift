import Foundation

enum ExploitSupportPolicy {
    static let verifiedIOS17Range = "17.0 – 17.7.x"
    static let verifiedIOS18Range = "18.0 – 18.7.1"
    static let verifiedIOS26Range = "26.0 – 26.6.1"

    /// Beta/ public beta builds whose kernel offsets are present in the
    /// kexploit bundle. These are exact build IDs; a matching version number
    /// alone is not enough.
    static let verifiedIOS27Builds: [(beta: Int, publicBeta: Int?, build: String)] = [
        (1, nil, "24A5355q"),
        (2, nil, "24A5370h"),
        (3, 1, "24A5380h"),
        (4, 2, "24A5390f")
    ]

    static let verifiedIOS17BuildCount = 38
    static let verifiedIOS18BuildCount = 22
    static let verifiedIOS26BuildCount = 11

    static func iOS27BetaNumber(for build: String) -> Int? {
        verifiedIOS27Builds.first { $0.build == build }?.beta
    }

    static func iOS27PublicBetaNumber(for build: String) -> Int? {
        verifiedIOS27Builds.first { $0.build == build }?.publicBeta
    }

    static func supportsKernelExploit(major: Int, minor: Int, patch: Int) -> Bool {
        guard minor >= 0, patch >= 0 else { return false }
        if major == 17 { return minor <= 7 }
        if major == 18 { return minor < 7 || (minor == 7 && patch <= 1) }
        if major == 26 {
            return minor < 6 || (minor == 6 && patch <= 1)
        }
        return false
    }

    static func isKernelSupported(major: Int, minor: Int, patch: Int, build: String) -> Bool {
        if supportsKernelExploit(major: major, minor: minor, patch: patch) {
            return true
        }
        guard major == 27, minor == 0, patch == 0 else { return false }
        return iOS27BetaNumber(for: build) != nil
    }

    /// The pairing route works from iOS 17 through iOS 27 on verified
    /// Developer Mode builds. The UI treats it as the fallback when the
    /// kernel route is unavailable.
    static func supportsPairing(major: Int) -> Bool {
        major >= 17
    }

    static func isSupported(major: Int, minor: Int, patch: Int, build: String) -> Bool {
        if isKernelSupported(major: major, minor: minor, patch: patch, build: build) {
            return true
        }
        return supportsPairing(major: major)
    }

    static func buildCountText(for major: Int) -> String {
        switch major {
        case 17: return "\(verifiedIOS17BuildCount) exact builds"
        case 18: return "\(verifiedIOS18BuildCount) exact builds"
        case 26: return "\(verifiedIOS26BuildCount) exact builds"
        case 27: return "\(verifiedIOS27Builds.count) beta builds"
        default: return "0 exact builds"
        }
    }
}
