import Foundation
import Combine

/// Remote patch library — no patch payload ships inside the .ipa.
///
/// The build carries zero `.3105` bytes. The app only fetches the products the
/// user asks for into `Documents/Patches`, where the existing package loader
/// resolves them. Anyone who unpacks the IPA gets UI code and an empty
/// `Patches` folder.
///
/// Manifest at `libraryURL`, UTF-8 JSON:
///
/// ```json
/// {
///   "version": 1,
///   "products": [
///     {
///       "id": "aimbot_drag",
///       "file": "aimbot_drag.3105",
///       "url": "https://host/aimbot_drag.3105",
///       "sha256": "64 lowercase hex chars",
///       "size": 81920
///     }
///   ]
/// }
/// ```
///
/// `file` is the name the loader resolves; `sha256` is mandatory — a download
/// that does not match is deleted and never written into `Patches`.
@MainActor
final class RemotePatches: ObservableObject {
    static let shared = RemotePatches()
    static let libraryURLKey = "discord.patches.libraryURL"

    @Published var libraryURL: String {
        didSet { UserDefaults.standard.set(libraryURL, forKey: Self.libraryURLKey) }
    }

    @Published private(set) var isSyncing = false
    @Published private(set) var lastReport: String?
    @Published private(set) var progressText: String?

    private init() {
        libraryURL = UserDefaults.standard.string(forKey: Self.libraryURLKey) ?? ""
    }

    // MARK: - Manifest

    private struct Manifest: Decodable {
        let version: Int?
        let products: [Entry]
    }

    private struct Entry: Decodable {
        let id: String?
        let file: String
        let url: String
        let sha256: String
        let size: Int?
    }

    // MARK: - Sync

    /// Fetches the manifest and downloads every package that is missing or does
    /// not match its digest. Safe to run repeatedly: matching files are skipped.
    func sync() async {
        guard !isSyncing else { return }
        let trimmed = libraryURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let manifestURL = URL(string: trimmed), manifestURL.scheme?.hasPrefix("http") == true else {
            lastReport = "Set a library URL first (https)."
            log("remote: no library URL configured", level: .warning)
            return
        }

        isSyncing = true
        lastReport = nil
        progressText = "Fetching manifest…"
        log("remote: fetching manifest \(manifestURL.absoluteString)", level: .info)

        do {
            let (data, response) = try await URLSession.shared.data(from: manifestURL)
            try Self.check(response)
            let manifest = try JSONDecoder().decode(Manifest.self, from: data)
            guard !manifest.products.isEmpty else {
                throw PatchServiceError.unknown("manifest lists no products")
            }

            try FileManager.default.createDirectory(
                at: FreeFireCatalog.patchesDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )

            var downloaded = 0
            var skipped = 0
            var failures: [String] = []

            for (index, entry) in manifest.products.enumerated() {
                progressText = "\(index + 1)/\(manifest.products.count) · \(entry.file)"
                let name = entry.file.hasSuffix(".3105") ? entry.file : entry.file + ".3105"
                let destination = FreeFireCatalog.patchesDirectory.appendingPathComponent(name)

                if let existing = try? Data(contentsOf: destination),
                   PatchPath.sha256Hex(existing) == entry.sha256.lowercased() {
                    skipped += 1
                    continue
                }

                do {
                    try await download(entry, to: destination)
                    downloaded += 1
                    log("remote: \(name) downloaded and verified", level: .success)
                } catch {
                    let detail = (error as? PatchServiceError)?.errorDescription
                        ?? error.localizedDescription
                    failures.append("\(name): \(detail)")
                    log("remote: \(name) failed — \(detail)", level: .error)
                }
            }

            var report = "\(downloaded) downloaded · \(skipped) already current"
            if !failures.isEmpty {
                report += " · \(failures.count) failed"
            }
            lastReport = report
            log("remote: \(report)", level: failures.isEmpty ? .success : .warning)
        } catch {
            let detail = (error as? PatchServiceError)?.errorDescription
                ?? error.localizedDescription
            lastReport = detail
            log("remote: sync failed — \(detail)", level: .error)
        }

        isSyncing = false
        progressText = nil
    }

    private func download(_ entry: Entry, to destination: URL) async throws {
        guard let url = URL(string: entry.url) else {
            throw PatchServiceError.invalidPackage("bad URL for \(entry.file)")
        }

        let (tempURL, response) = try await URLSession.shared.download(from: url)
        try Self.check(response)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let data = try Data(contentsOf: tempURL, options: .mappedIfSafe)
        let digest = PatchPath.sha256Hex(data)
        guard digest == entry.sha256.lowercased() else {
            throw PatchServiceError.digestMismatch(
                expected: entry.sha256.lowercased(),
                actual: digest,
                file: entry.file
            )
        }
        if let size = entry.size, size != data.count {
            throw PatchServiceError.invalidPackage(
                "\(entry.file) is \(data.count) bytes, manifest says \(size)"
            )
        }

        // Prove the bytes actually decrypt and every rule digest is intact
        // before the package is allowed into Patches.
        let staging = destination.appendingPathExtension("tmp")
        try data.write(to: staging, options: .atomic)
        do {
            _ = try PatchPackage.load(from: staging)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: staging, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw PatchServiceError.unknown("server returned HTTP \(code)")
        }
    }
}
