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
            let bundle = ContainerStore.resolveApplicationBundlePath(bundleID: game.rawValue)
            ContainerStore.logDataContainerLayout(root)
            ContainerStore.logAssetTreeSearch(root)
            log(
                "patch: backend = local container \(root)"
                    + (bundle.map { " + bundle \($0)" } ?? ""),
                level: .info
            )
            return try body(LocalPatchFileSystem(
                rootPath: root,
                bundleRoot: bundle,
                hotRoot: hotUpdateRoot(root: root, game: game)
            ))
        }

        if allowKernel, shouldTryKernel {
            log("patch: local container is not readable — running kernel exploit", level: .warning)
            let started = KernelExploit.run()
            if started, let root = accessibleLocalRoot(bundleID: game.rawValue) {
                let bundle = ContainerStore.resolveApplicationBundlePath(bundleID: game.rawValue)
                log("patch: backend = kernel/MCM after exploit", level: .success)
                return try body(LocalPatchFileSystem(
                    rootPath: root,
                    bundleRoot: bundle,
                    hotRoot: hotUpdateRoot(root: root, game: game)
                ))
            }
            log("patch: kernel route did not expose the container", level: .warning)
        }

        guard let pairingPath = PairingController.pairingFilePath() else {
            throw PatchServiceError.noAccess(
                "MCM did not resolve \(game.rawValue) and no pairing file is installed. "
                + "Import a pairing file, or start pairing and allow Developer Mode on this iPhone."
                + ContainerStore.diagnosticSuffix
            )
        }

        let tunnel = try AirliftTunnel()
        defer { tunnel.close() }

        log("patch: connecting pairing tunnel for \(game.rawValue)", level: .info)
        try tunnel.connect(pairingPath: pairingPath)
        log("patch: tunnel connected — vending \(game.rawValue)", level: .success)

        do {
            try tunnel.vendContainer(bundleID: game.rawValue)
        } catch {
            // House Arrest answers with a bare device string such as
            // `InstallationLookupFailed`; on its own it reads like a bug in
            // this app, so probe InstallationProxy before reporting it.
            let detail = tunnel.lastError
            log("patch: vend container refused — \(detail)", level: .error)

            // House Arrest only refused to *open* the container; the probe
            // still reports where it lives, and that path is all the free
            // worse_query escape needs. Try it before giving up.
            if PairingRouteDiagnosis.containerPath(
                pairingPath: pairingPath,
                bundleID: game.rawValue
            ) != nil,
               let root = ContainerStore.resolveAppContainerPath(bundleID: game.rawValue) {
                let bundle = ContainerStore.resolveApplicationBundlePath(bundleID: game.rawValue)
                log(
                    "patch: backend = worse_query at \(root) after the pairing probe",
                    level: .success
                )
                return try body(LocalPatchFileSystem(
                    rootPath: root,
                    bundleRoot: bundle,
                    hotRoot: hotUpdateRoot(root: root, game: game)
                ))
            }

            throw PatchServiceError.noAccess(
                PairingRouteDiagnosis.explain(
                    detail: detail,
                    game: game,
                    pairingPath: pairingPath
                )
                + ContainerStore.diagnosticSuffix
            )
        }

        let fileSystem = AirliftPatchFileSystem(tunnel: tunnel)
        return try body(fileSystem)
    }

    /// Free Fire unpacks the shipped assets into `Library/Caches/<bundle id>`
    /// in its own container, so asset rules resolve there when the signed
    /// bundle itself cannot be reached.
    private static func hotUpdateRoot(root: String, game: FreeFireGame) -> String? {
        let path = URL(fileURLWithPath: root)
            .appendingPathComponent("Library/Caches")
            .appendingPathComponent(game.rawValue)
            .path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return path
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

/// Turns a bare House Arrest refusal into something the user can act on.
///
/// `InstallationLookupFailed` is the device's own answer, not an app error:
/// iOS vends the container of a development/enterprise-signed app over the
/// pairing tunnel, and refuses App Store apps even though their container
/// exists. Probing InstallationProxy separates "the game is not installed"
/// from "iOS will not hand this container out through House Arrest".
enum PairingRouteDiagnosis {
    static func explain(detail: String, game: FreeFireGame, pairingPath: String) -> String {
        let lowered = detail.lowercased()
        let lookupFailure = lowered.contains("installationlookup")
            || lowered.contains("applicationlookup")
        let permissionFailure = lowered.contains("perm_denied")
            || lowered.contains("permission")

        guard lookupFailure || permissionFailure else {
            return "House Arrest rejected the \(game.rawValue) container: \(detail)"
        }

        let container = containerPath(pairingPath: pairingPath, bundleID: game.rawValue)

        if let container {
            log(
                "patch: \(game.rawValue) is installed at \(container) — House Arrest still refused the vending",
                level: .warning
            )
            return "iOS refused to open the \(game.displayName) container (\(detail)). "
                + "The app is installed (\(container)), but the pairing tunnel only vends containers of "
                + "development/enterprise-signed apps — App Store apps are refused on this iOS version. "
                + "Use the MCM/kernel route, or sign and install the game with a development profile."
        }

        let other = FreeFireGame.allCases.first { $0 != game }
        let otherInstalled = other.flatMap {
            containerPath(pairingPath: pairingPath, bundleID: $0.rawValue)
        }

        if let other, let otherInstalled {
            log("patch: \(other.rawValue) is installed at \(otherInstalled)", level: .warning)
            return "\(game.displayName) (\(game.rawValue)) is not installed on this iPhone. "
                + "\(other.displayName) is — switch the game in Profile › Game and try again."
        }

        return "No installed app with bundle id \(game.rawValue) answered InstallationProxy "
            + "(\(detail)). Install \(game.displayName) on this iPhone, or pick the other game in "
            + "Profile › Game. Also check that the imported pairing file belongs to this device."
    }

    /// Absolute data-container path from InstallationProxy. Unlike House
    /// Arrest this works for every installed app, so it is a reliable probe.
    static func containerPath(pairingPath: String, bundleID: String) -> String? {
        var container: UnsafeMutablePointer<CChar>?
        var error: UnsafeMutablePointer<CChar>?

        let code = pairingPath.withCString { path in
            bundleID.withCString { bundle in
                al_find_app_container(path, bundle, nil, nil, &container, &error)
            }
        }

        defer {
            if let error { al_string_free(error) }
            if let container { al_string_free(container) }
        }

        guard code == 0, let container else { return nil }
        let text = String(cString: container)
        guard !text.isEmpty else { return nil }
        // Hand the path to the escape: House Arrest refuses App Store apps,
        // but worse_query only needs to know which container to target.
        ContainerStore.noteContainerPath(text, bundleID: bundleID)
        return text
    }
}
