import Foundation
import UIKit
import Darwin

enum AppInfo {
    static var bundleID: String {
        Bundle.main.bundleIdentifier ?? "com.apple.mobile.MobileHouseArrest"
    }

    static var displayName: String {
        (Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (Bundle.main.infoDictionary?["CFBundleName"] as? String)
            ?? "Discord"
    }

    static var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0"
    }

    static var buildString: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "2"
    }

    static var fullVersion: String {
        "\(versionString) (\(buildString))"
    }

    static var osVersion: String {
        UIDevice.current.systemVersion
    }

    static var machine: String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    /// Alias kept for callers that read the hardware identifier by the older name.
    static var machineName: String { machine }

    /// The user-visible device name used as the RPPairing host name.
    static var displayMachineName: String {
        let name = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Discord" : name
    }

    static var osBuild: String {
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        return String(cString: buffer)
    }

    static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    static var versionTuple: (major: Int, minor: Int, patch: Int) {
        let parts = osVersion.split(separator: ".").compactMap { Int($0) }
        return (
            parts.count > 0 ? parts[0] : 0,
            parts.count > 1 ? parts[1] : 0,
            parts.count > 2 ? parts[2] : 0
        )
    }
}
