import Foundation

final class AirliftTunnel {
    private var handle: OpaquePointer?
    private(set) var connected = false

    init() throws {
        guard let handle = air_tunnel_create() else {
            throw PatchServiceError.noAccess("could not allocate the pairing tunnel")
        }
        self.handle = handle
    }

    deinit {
        close()
    }

    func close() {
        if let handle {
            air_tunnel_destroy(handle)
            self.handle = nil
        }
        connected = false
    }

    var lastError: String {
        guard let handle, let pointer = air_tunnel_last_error(handle) else {
            return "unknown tunnel error"
        }
        return String(cString: pointer)
    }

    func connect(
        pairingPath: String,
        host: String = "10.7.0.1",
        port: UInt16 = 49152,
        extraHosts: [String] = ["10.7.0.2", "10.7.0.3", "10.0.0.1"]
    ) throws {
        guard let handle else {
            throw PatchServiceError.noAccess("tunnel was closed")
        }

        _ = al_set_target_host(host)
        let extras = extraHosts.joined(separator: ",")
        let result = pairingPath.withCString { pairingC in
            host.withCString { hostC in
                extras.withCString { extrasC in
                    air_tunnel_connect(handle, pairingC, hostC, port, extrasC)
                }
            }
        }
        guard result == 0 else {
            throw PatchServiceError.noAccess(lastError)
        }
        connected = true
    }

    func vendContainer(bundleID: String) throws {
        guard let handle, connected else {
            throw PatchServiceError.noAccess("tunnel is not connected")
        }
        let result = bundleID.withCString { bundleC in
            air_tunnel_vend_container(handle, bundleC)
        }
        guard result == 0 else {
            throw PatchServiceError.noAccess(lastError)
        }
    }

    func readFile(path: String) throws -> Data {
        guard let handle, connected else {
            throw PatchServiceError.noAccess("tunnel is not connected")
        }

        var buffer: UnsafeMutablePointer<UInt8>?
        var length = 0
        let result = path.withCString { pathC in
            air_tunnel_read_file(handle, pathC, &buffer, &length)
        }
        guard result == 0 else {
            throw PatchServiceError.noAccess(lastError)
        }
        guard let buffer else {
            return Data()
        }
        defer { air_tunnel_free_data(buffer, length) }
        if length == 0 {
            return Data()
        }
        return Data(bytes: buffer, count: length)
    }

    func writeFile(path: String, data: Data) throws {
        guard let handle, connected else {
            throw PatchServiceError.noAccess("tunnel is not connected")
        }

        let result = path.withCString { pathC in
            data.withUnsafeBytes { bytes in
                air_tunnel_write_file(
                    handle,
                    pathC,
                    bytes.bindMemory(to: UInt8.self).baseAddress,
                    data.count
                )
            }
        }
        guard result == 0 else {
            throw PatchServiceError.noAccess(lastError)
        }
    }

    func fileExists(path: String) -> Bool {
        guard let handle, connected else { return false }
        return path.withCString { pathC in
            air_tunnel_file_exists(handle, pathC) == 1
        }
    }

    func removeFile(path: String) throws {
        guard let handle, connected else {
            throw PatchServiceError.noAccess("tunnel is not connected")
        }
        let result = path.withCString { pathC in
            air_tunnel_remove_file(handle, pathC)
        }
        guard result == 0 else {
            throw PatchServiceError.noAccess(lastError)
        }
    }
}
