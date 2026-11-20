import Foundation
import Combine

/// Owns the on-device pairing session that unlocks the `pairing/AFC` backend.
///
/// The kernel/MCM route does not need any of this. It exists for the builds
/// where the kernel exploit is not applicable (iOS 27 Developer Mode) and the
/// container has to be reached through Remote Pairing instead:
///
///   1. this controller runs the RPPairing host and publishes the service over
///      Bonjour so the device can see it,
///   2. the device shows a PIN, the user confirms it, the host writes a
///      `pairing.plist` next to the app's documents,
///   3. `AirliftTunnel` connects over LocalDevVPN with that file and vends the
///      game container through AFC.
///
/// Everything here is optional: when no pairing file exists the runtime simply
/// stays on the MCM route and reports `pairingRequired`.
final class PairingController: ObservableObject {
    static let shared = PairingController()

    enum Status: Equatable {
        case idle
        case starting
        case waitingForPin
        case waitingForDevice
        case paired
        case connected
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .starting, .waitingForPin, .waitingForDevice: return true
            default: return false
            }
        }

        var isConnected: Bool { self == .connected }
    }

    // MARK: - Published state

    @Published private(set) var status: Status = .idle
    @Published private(set) var hasPairingFile: Bool = false
    @Published private(set) var currentPin: String?
    @Published private(set) var pairedDeviceName: String?
    @Published private(set) var pairedDeviceModel: String?
    @Published private(set) var pairedDeviceUDID: String?
    @Published private(set) var bonjourServiceName: String?
    @Published private(set) var pairingFilePathOnDevice: String?
    @Published var errorMessage: String?

    /// Kept across launches: the RPPairing host returns a per-host identity
    /// (`host_alt_irk_hex`) that must be replayed on the next run, otherwise
    /// the device treats the host as a new machine and drops the pairing.
    private let altIRKStore = "discord.pairing.hostAltIRK"

    private var service: NetService?
    private var runGeneration = 0
    private let queue = DispatchQueue(label: "discord.pairing.host", qos: .userInitiated)
    private var isRunning = false

    private init() {
        refresh()
        restorePairedDevice()
    }

    // MARK: - Paths

    static var documentsURL: URL {
        AppInfo.documentsURL
    }

    static var pairingFileURL: URL {
        documentsURL.appendingPathComponent("pairing.plist", isDirectory: false)
    }

    /// `nil` unless a *usable* pairing file is installed.
    ///
    /// A zero-byte or truncated `pairing.plist` is not a pairing file: the
    /// tunnel would fail deep inside the TLS-PSK handshake with a confusing
    /// message. Treat it as absent so the caller falls back cleanly and the
    /// UI can say "not configured".
    static func pairingFilePath() -> String? {
        let url = pairingFileURL
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue > 0 else {
            return nil
        }
        return url.path
    }

    // MARK: - Refresh

    func refresh() {
        let installed = Self.pairingFilePath()
        hasPairingFile = installed != nil
        pairingFilePathOnDevice = installed
        if installed == nil, status == .paired || status == .connected {
            status = .idle
        }
    }

    var statusText: String {
        if let errorMessage, !errorMessage.isEmpty {
            return errorMessage
        }
        switch status {
        case .idle:
            return hasPairingFile ? "Pairing file ready" : "Not connected"
        case .starting:
            return "Starting pairing host…"
        case .waitingForPin:
            return "Confirm the PIN on your iPhone"
        case .waitingForDevice:
            return "Waiting for the iPhone to pair…"
        case .paired:
            return "Paired"
        case .connected:
            return "Connected"
        case .failed(let detail):
            return detail
        }
    }

    var detailText: String {
        if let name = pairedDeviceName, let model = pairedDeviceModel {
            return "\(name) · \(model)"
        }
        return hasPairingFile ? "pairing.plist imported" : "No pairing file"
    }

    var currentPinCode: String? { currentPin }

    // MARK: - Import

    /// Copies a `pairing.plist` produced elsewhere (macOS `idevicepair`, a
    /// previous install of this app, or an X export) into the app documents
    /// directory and validates it before it is trusted.
    @discardableResult
    func importPairingFile(from url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        log("pairing: scoped access = \(scoped) for \(url.lastPathComponent)", level: .info)
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        // fileImporter URLs are security-scoped on iOS; read through a
        // coordinated accessor so we do not depend on the scoped flag.
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?
        var data: Data?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { readURL in
            data = try? Data(contentsOf: readURL)
        }
        if let coordinatorError {
            throw PatchServiceError.noAccess("could not read \(url.lastPathComponent): \(coordinatorError.localizedDescription)")
        }
        guard let data, !data.isEmpty else {
            throw PatchServiceError.pairingRequired
        }

        // A real pairing file is a plist with a UDID and host identity keys.
        // Accept the common key spellings used by idevicepair / X exports.
        guard let plist = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any] else {
            throw PatchServiceError.noAccess(
                "\(url.lastPathComponent) is not a valid plist"
            )
        }
        let udidKey = plist.keys.first { $0.lowercased() == "udid" || $0.lowercased() == "uniquedeviceid" }
        guard let udidKey, let udidValue = plist[udidKey] as? String, !udidValue.isEmpty else {
            throw PatchServiceError.noAccess(
                "\(url.lastPathComponent) is not a pairing file (no UDID key)"
            )
        }

        try FileManager.default.createDirectory(
            at: Self.documentsURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let destination = Self.pairingFileURL
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try data.write(to: destination, options: .atomic)

        hasPairingFile = true
        pairingFilePathOnDevice = destination.path

        let nameKey = plist.keys.first { $0.lowercased() == "devicename" || $0.lowercased() == "device_name" || $0.lowercased() == "name" }
        if let nameKey, let name = plist[nameKey] as? String {
            pairedDeviceName = name
            UserDefaults.standard.set(name, forKey: "discord.pairing.deviceName")
        }
        if let udid = plist[udidKey] as? String {
            pairedDeviceUDID = udid
            UserDefaults.standard.set(udid, forKey: "discord.pairing.deviceUDID")
        }
        let irkKey = plist.keys.first { $0.lowercased() == "hostaltirk" || $0.lowercased() == "host_alt_irk" || $0.lowercased() == "altirk" }
        if let irkKey, let irk = plist[irkKey] as? String, !irk.isEmpty {
            UserDefaults.standard.set(irk, forKey: altIRKStore)
        }

        status = .paired
        errorMessage = nil
        log("pairing: imported \(url.lastPathComponent) (\(data.count) bytes)", level: .success)
        return destination.path
    }

    // MARK: - Pairing host

    /// Starts the RPPairing host. The Rust call blocks until the device pairs
    /// or the run errors out, so it is dispatched off the main thread; the PIN
    /// and the service identity arrive through callbacks.
    ///
    /// `generatePin()` is the same operation under the name the UI uses: the
    /// PIN is not generated by us, it is chosen by the device and surfaced by
    /// the `ALPairPinCb` callback.
    func generatePin() {
        startPairing()
    }

    func startPairing() {
        guard !isRunning else {
            log("pairing: host already running", level: .warning)
            return
        }
        refresh()
        if hasPairingFile {
            log("pairing: a pairing file already exists — re-pairing will replace it", level: .warning)
        }

        isRunning = true
        runGeneration += 1
        let generation = runGeneration
        currentPin = nil
        errorMessage = nil
        status = .starting
        log("pairing: starting RPPairing host", level: .info)

        let name = AppInfo.displayMachineName
        let model = "iPhone"
        let outPath = Self.pairingFileURL.path
        let altIRK = UserDefaults.standard.string(forKey: altIRKStore) ?? ""

        queue.async { [weak self] in
            var result = ALPairResult()
            let context = self.map { Unmanaged.passUnretained($0).toOpaque() }
            let code = airlift_pairing_run_host(
                bindAddress: "0.0.0.0",
                port: 0,
                name: name,
                model: model,
                outPath: outPath,
                hostAltIRKHex: altIRK,
                context: context,
                &result
            )

            let failure = result.error.map { String(cString: $0) } ?? ""
            let deviceName = result.device_name.map { String(cString: $0) } ?? ""
            let deviceModel = result.device_model.map { String(cString: $0) } ?? ""
            let deviceUDID = result.device_udid.map { String(cString: $0) } ?? ""
            let producedPath = result.pairing_file_path.map { String(cString: $0) } ?? ""
            let returnedIRK = result.host_alt_irk_hex.map { String(cString: $0) } ?? ""
            al_pairing_result_free(&result)

            DispatchQueue.main.async {
                guard let self, self.runGeneration == generation else { return }
                self.isRunning = false
                self.currentPin = nil

                if code == 0 {
                    if !returnedIRK.isEmpty {
                        UserDefaults.standard.set(returnedIRK, forKey: self.altIRKStore)
                    }
                    if !deviceName.isEmpty {
                        self.pairedDeviceName = deviceName
                        UserDefaults.standard.set(deviceName, forKey: "discord.pairing.deviceName")
                    }
                    if !deviceModel.isEmpty {
                        self.pairedDeviceModel = deviceModel
                        UserDefaults.standard.set(deviceModel, forKey: "discord.pairing.deviceModel")
                    }
                    if !deviceUDID.isEmpty {
                        self.pairedDeviceUDID = deviceUDID
                        UserDefaults.standard.set(deviceUDID, forKey: "discord.pairing.deviceUDID")
                    }
                    if !producedPath.isEmpty {
                        self.pairingFilePathOnDevice = producedPath
                    }
                    self.refresh()
                    self.status = .paired
                    self.errorMessage = nil
                    log("pairing: device paired — pairing.plist written", level: .success)
                } else {
                    let detail = failure.isEmpty
                        ? "pairing host failed with code \(code)"
                        : failure
                    self.status = .failed(detail)
                    self.errorMessage = detail
                    log("pairing: \(detail)", level: .error)
                }
            }
        }
    }

    /// Best-effort cancellation. The Rust host call is blocking and has no
    /// abort entry point, so the run is orphaned rather than killed: its
    /// result is discarded through the generation token and the Bonjour
    /// advertisement is withdrawn so the device can no longer find us.
    func cancelPairing() {
        guard isRunning else { return }
        runGeneration += 1
        isRunning = false
        currentPin = nil
        stopBonjour()
        status = .idle
        errorMessage = nil
        log("pairing: host cancelled by the user", level: .warning)
    }

    // MARK: - Tunnel connect

    /// Verifies that the installed pairing file actually works by walking the
    /// full path the patch engine uses: tunnel → pair-verify → AFC → vend a
    /// known container. Success here means `patch: backend = pairing/AFC` will
    /// not fail later.
    func connect() {
        guard let path = Self.pairingFilePath() else {
            status = .failed("No pairing file installed")
            errorMessage = "Import a pairing file or pair this iPhone first."
            return
        }
        guard status != .connected else { return }

        status = .starting
        errorMessage = nil
        log("pairing: verifying tunnel with \(path)", level: .info)

        queue.async { [weak self] in
            do {
                let tunnel = try AirliftTunnel()
                defer { tunnel.close() }
                try tunnel.connect(pairingPath: path)
                log("pairing: TLS-PSK handshake ok", level: .success)

                // Proven end-to-end only when a container can be vended.
                if let container = airlift_find_container(pairingPath: path) {
                    log("pairing: AFC container \(container)", level: .success)
                }

                DispatchQueue.main.async {
                    guard let self else { return }
                    self.status = .connected
                    self.errorMessage = nil
                    log("pairing: connected", level: .success)
                }
            } catch {
                let detail = (error as? PatchServiceError)?.errorDescription
                    ?? error.localizedDescription
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.status = .failed(detail)
                    self.errorMessage = detail
                    log("pairing: \(detail)", level: .error)
                }
            }
        }
    }

    func disconnect() {
        stopBonjour()
        runGeneration += 1
        isRunning = false
        currentPin = nil
        status = hasPairingFile ? .paired : .idle
        errorMessage = nil
    }

    /// Removes the pairing file and the cached device identity. The game
    /// container is untouched — this only forgets how we reach it.
    func forgetPairing() {
        disconnect()
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: Self.pairingFileURL.path) {
            try? fileManager.removeItem(at: Self.pairingFileURL)
        }
        UserDefaults.standard.removeObject(forKey: altIRKStore)
        UserDefaults.standard.removeObject(forKey: "discord.pairing.deviceName")
        UserDefaults.standard.removeObject(forKey: "discord.pairing.deviceModel")
        UserDefaults.standard.removeObject(forKey: "discord.pairing.deviceUDID")
        pairedDeviceName = nil
        pairedDeviceModel = nil
        pairedDeviceUDID = nil
        pairingFilePathOnDevice = nil
        hasPairingFile = false
        status = .idle
        log("pairing: pairing file removed", level: .warning)
    }

    // MARK: - Bonjour

    /// Called from the host thread when the RPPairing listener is bound.
    fileprivate func handleReady(serviceID: String, port: Int, txt: [String: String]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.status = .waitingForPin
            self.advertise(serviceID: serviceID, port: port, txt: txt)
        }
    }

    fileprivate func handlePin(_ pin: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.currentPin = pin
            self.status = .waitingForPin
            log("pairing: PIN \(pin) — confirm it on the iPhone", level: .info)
        }
    }

    private func advertise(serviceID: String, port: Int, txt: [String: String]) {
        stopBonjour()
        guard port > 0, port <= 65_535 else {
            log("pairing: host reported an invalid port \(port)", level: .warning)
            return
        }

        // The Rust side hands us either a bare service id ("rppairing") or a
        // full Bonjour type ("_rppairing._tcp"). NetService needs the latter.
        let type: String
        if serviceID.hasPrefix("_") && serviceID.contains("._tcp") {
            type = serviceID.hasSuffix(".") ? serviceID : serviceID + "."
        } else {
            let bare = serviceID.hasPrefix("_") ? String(serviceID.dropFirst()) : serviceID
            type = "_\(bare)._tcp."
        }

        let name = "\(AppInfo.displayName) \(String(UUID().uuidString.prefix(4)))"
        let service = NetService(
            domain: "local.",
            type: type,
            name: name,
            port: Int32(port)
        )

        if !txt.isEmpty {
            var record = Data()
            for (key, value) in txt.sorted(by: { $0.key < $1.key }) {
                guard let keyData = key.data(using: .utf8),
                      let valueData = value.data(using: .utf8),
                      keyData.count < 255,
                      valueData.count < 255 else { continue }
                record.append(UInt8(keyData.count))
                record.append(keyData)
                record.append(UInt8(valueData.count))
                record.append(valueData)
            }
            service.setTXTRecord(record.isEmpty ? nil : record)
        }

        service.publish()
        self.service = service
        bonjourServiceName = name
        log("pairing: advertising \(type) on port \(port)", level: .info)
    }

    private func stopBonjour() {
        service?.stop()
        service = nil
        bonjourServiceName = nil
    }

    // MARK: - Restore

    private func restorePairedDevice() {
        let defaults = UserDefaults.standard
        pairedDeviceName = defaults.string(forKey: "discord.pairing.deviceName")
        pairedDeviceModel = defaults.string(forKey: "discord.pairing.deviceModel")
        pairedDeviceUDID = defaults.string(forKey: "discord.pairing.deviceUDID")
        if hasPairingFile, status == .idle {
            status = .paired
        }
    }
}

// MARK: - C bridge

/// Thin Swift wrappers around `al_pairing_run_host` that keep the C callback
/// signatures in one place. The callbacks cannot capture, so the controller is
/// round-tripped through the opaque `ctx` pointer.
private func airlift_pairing_run_host(
    bindAddress: String,
    port: UInt16,
    name: String,
    model: String,
    outPath: String,
    hostAltIRKHex: String,
    context: UnsafeMutableRawPointer?,
    _ result: UnsafeMutablePointer<ALPairResult>
) -> Int32 {
    let ready: ALPairReadyCb = { ctx, serviceID, port, keys, values, count in
        guard let ctx else { return }
        let controller = Unmanaged<PairingController>.fromOpaque(ctx).takeUnretainedValue()
        let service = serviceID.map { String(cString: $0) } ?? ""
        var txt: [String: String] = [:]
        if let keys, let values {
            for index in 0..<Int(count) {
                guard let key = keys[index], let value = values[index] else { continue }
                txt[String(cString: key)] = String(cString: value)
            }
        }
        controller.handleReady(serviceID: service, port: Int(port), txt: txt)
    }

    let pin: ALPairPinCb = { pin, ctx in
        guard let ctx, let pin else { return }
        let controller = Unmanaged<PairingController>.fromOpaque(ctx).takeUnretainedValue()
        controller.handlePin(String(cString: pin))
    }

    let irkArgument: String? = hostAltIRKHex.isEmpty ? nil : hostAltIRKHex

    return bindAddress.withCString { bind in
        name.withCString { nameC in
            model.withCString { modelC in
                outPath.withCString { outC in
                    let body: (UnsafePointer<CChar>?) -> Int32 = { irkC in
                        al_pairing_run_host(
                            bind, port, nameC, modelC, outC, irkC,
                            ready, pin, context, result
                        )
                    }
                    if let irkArgument {
                        return irkArgument.withCString(body)
                    }
                    return body(nil)
                }
            }
        }
    }
}

/// Best-effort container lookup used only as a connectivity probe.
private func airlift_find_container(pairingPath: String) -> String? {
    var container: UnsafeMutablePointer<CChar>?
    var error: UnsafeMutablePointer<CChar>?

    let code = pairingPath.withCString { path in
        al_find_app_container(
            path,
            FreeFireGame.freeFire.rawValue,
            nil,
            nil,
            &container,
            &error
        )
    }

    defer {
        if let error { al_string_free(error) }
        if let container { al_string_free(container) }
    }

    guard code == 0, let container else { return nil }
    return String(cString: container)
}
