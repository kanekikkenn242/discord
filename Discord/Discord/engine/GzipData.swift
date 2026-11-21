import Foundation

/// gzip round-trip for hot-update bundles. The device keeps `cache_res` as a
/// gzip stream; fixing its collider fields therefore requires decompressing
/// first and recompressing afterwards.
enum GzipData {
    static func decompress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        var output: UnsafeMutablePointer<UInt8>?
        var length: Int = 0
        let status = data.withUnsafeBytes { raw -> Int32 in
            guard let base = raw.baseAddress else { return -1 }
            return zdma_gunzip(base.assumingMemoryBound(to: UInt8.self), data.count,
                               &output, &length)
        }
        guard status == 0, let buffer = output, length > 0 else { return nil }
        defer { zdma_buffer_free(buffer) }
        return Data(bytes: buffer, count: length)
    }

    static func compress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        var output: UnsafeMutablePointer<UInt8>?
        var length: Int = 0
        let status = data.withUnsafeBytes { raw -> Int32 in
            guard let base = raw.baseAddress else { return -1 }
            return zdma_gzip(base.assumingMemoryBound(to: UInt8.self), data.count,
                             &output, &length)
        }
        guard status == 0, let buffer = output, length > 0 else { return nil }
        defer { zdma_buffer_free(buffer) }
        return Data(bytes: buffer, count: length)
    }
}
