import Foundation

enum PatchRuntime {
    /// Runs `body` with the first usable container backend. Order:
    /// 1. MCM / sandbox-escaped filesystem (iOS 17–18, 26 with kernel r/w)
    /// 2. On-demand kernel exploit, then MCM again
    /// 3. On-device pairing tunnel + House Arrest + AFC
    static func withFileSystem<T>(
        game: FreeFireGame,
        allowKernel: Bool,
        _ body: (PatchFileSystem) throws -> T
    ) throws -> T {
        if let root = accessibleLocalRoot(bundleID: game.rawValue) {
            log("patch: backend = local container \(root)", level: .info)
            return try body(LocalPatchFileSystem(rootPath: root))
        }

        if allowKernel, shouldTryKernel {
            log("patch: local container is not readable — running kernel exploit", level: .warning)
            let started = KernelExploit.run()
            if started, let root = accessibleLocalRoot(bundleID: game.rawValue) {
                log("patch: backend = kernel/MCM after exploit", level: .success)
                return try body(LocalPatchFileSystem(rootPath: root))
            }
            log("patch: kernel route did not expose the container", level: .warning)
        }

        guard let pairingPath = PairingController.pairingFilePath() else {
            throw PatchServiceError.noAccess(
                "MCM did not resolve \(game.rawValue) and no pairing file is installed"
            )
        }

        let tunnel = try AirliftTunnel()
        defer { tunnel.close() }

        log("patch: connecting pairing tunnel for \(game.rawValue)", level: .info)
        try tunnel.connect(pairingPath: pairingPath)
        log("patch: tunnel connected — vending \(game.rawValue)", level: .success)
        try tunnel.vendContainer(bundleID: game.rawValue)

        let fileSystem = AirliftPatchFileSystem(tunnel: tunnel)
        return try body(fileSystem)
    }

    static func accessibleLocalRoot(bundleID: String) -> String? {
        guard let root = ContainerStore.resolveAppContainerPath(bundleID: bundleID) else {
            return nil
        }
        let fileManager = FileManager.default
        let documents = (root as NSString).appendingPathComponent("Documents")
        if (try? fileManager.contentsOfDirectory(atPath: documents)) != nil {
            return root
        }
        if (try? fileManager.contentsOfDirectory(atPath: root)) != nil {
            return root
        }
        return nil
    }

    private static var shouldTryKernel: Bool {
        let version = AppInfo.versionTuple
        return KernelExploit.isApplicable(
            major: version.major,
            minor: version.minor,
            patch: version.patch,
            build: AppInfo.osBuild
        )
    }

    static func backendDescription(game: FreeFireGame) -> String {
        if accessibleLocalRoot(bundleID: game.rawValue) != nil {
            return "kernel/MCM"
        }
        if PairingController.pairingFilePath() != nil {
            return "pairing/AFC"
        }
        return "not available"
    }
}
