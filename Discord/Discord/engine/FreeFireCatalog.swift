import Foundation

enum FreeFireGame: String, CaseIterable, Identifiable, Codable {
    case freeFire = "com.dts.freefireth"
    case freeFireMax = "com.dts.freefiremax"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .freeFire: return "Free Fire"
        case .freeFireMax: return "Free Fire MAX"
        }
    }

    var shortName: String {
        switch self {
        case .freeFire: return "Free Fire"
        case .freeFireMax: return "FF MAX"
        }
    }

    var urlScheme: String {
        switch self {
        case .freeFire: return "freefire"
        case .freeFireMax: return "freefiremax"
        }
    }
}

enum PatchCategory: String, CaseIterable, Identifiable {
    case aimbot
    case hologram
    case skin
    case texture
    case fps

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .aimbot: return "game.category.aimbot"
        case .hologram: return "game.category.hologram"
        case .skin: return "game.category.skin"
        case .texture: return "game.category.texture"
        case .fps: return "game.category.fps"
        }
    }

    /// Only the aimbot family is split into the cache/avatar tabs.
    var hasTabs: Bool { self == .aimbot }
}

enum AimbotTab: String, CaseIterable, Identifiable {
    case cache
    case avatar

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .cache: return "game.tab.cache"
        case .avatar: return "game.tab.avatar"
        }
    }
}

enum PatchSlot: String {
    case avatar
    case cache
    case texture
    case fps
}

struct PatchProduct: Identifiable, Equatable {
    let id: String
    let titleKey: String
    let subtitleKey: String
    let category: PatchCategory
    /// Unused outside `.aimbot`; optional so texture/fps rows are not forced
    /// into an Aimbot Cache / Aimbot Avatar segment they do not belong to.
    let tab: AimbotTab?
    let slot: PatchSlot
    let packageNames: [String]
    let badge: String?
    let noteKey: String?

    static func == (lhs: PatchProduct, rhs: PatchProduct) -> Bool {
        lhs.id == rhs.id
    }
}

enum FreeFireCatalog {
    static let products: [PatchProduct] = [
        // Cosmetic-only: no hitbox, aim or gameplay files are modified.
        PatchProduct(id: "texture_sielzada", titleKey: "dope.tex.sielzada", subtitleKey: "dope.sub.santino",
                     category: .texture, tab: nil, slot: .texture,
                     packageNames: ["texture_sielzada"], badge: nil, noteKey: nil),
        PatchProduct(id: "texture_mordecai", titleKey: "dope.tex.mordecai", subtitleKey: "dope.sub.alok",
                     category: .texture, tab: nil, slot: .texture,
                     packageNames: ["texture_mordecai"], badge: nil, noteKey: nil),
        PatchProduct(id: "texture_aranha", titleKey: "dope.tex.aranha", subtitleKey: "dope.sub.alok",
                     category: .texture, tab: nil, slot: .texture,
                     packageNames: ["texture_aranha"], badge: nil, noteKey: nil),
        PatchProduct(id: "texture_alienx", titleKey: "dope.tex.alienx", subtitleKey: "dope.sub.alok",
                     category: .texture, tab: nil, slot: .texture,
                     packageNames: ["texture_alienx"], badge: nil, noteKey: nil)
    ]

    private static let legacyProducts: [PatchProduct] = [
        PatchProduct(
            id: "aimbot_drag",
            titleKey: "product.aimbotDrag",
            subtitleKey: "product.aimbotDrag.subtitle",
            category: .aimbot,
            tab: .avatar,
            slot: .avatar,
            packageNames: ["aimbot_drag"],
            badge: "SAFE",
            noteKey: nil
        ),
        PatchProduct(
            id: "aimdrag_neck",
            titleKey: "product.aimNeck",
            subtitleKey: "product.aimNeck.subtitle",
            category: .aimbot,
            tab: .avatar,
            slot: .avatar,
            packageNames: ["aimdrag_neck"],
            badge: "SAFE",
            noteKey: "product.aimNeck.note"
        ),
        PatchProduct(
            id: "aimneck_90",
            titleKey: "product.aimDragNeck",
            subtitleKey: "product.aimDragNeck.subtitle",
            category: .aimbot,
            tab: .avatar,
            slot: .avatar,
            packageNames: ["aimneck_90"],
            badge: "SAFE",
            noteKey: nil
        ),
        PatchProduct(
            id: "aimneck_hs",
            titleKey: "product.hsNeck",
            subtitleKey: "product.hsNeck.subtitle",
            category: .aimbot,
            tab: .avatar,
            slot: .avatar,
            packageNames: ["aimneck_hs"],
            badge: "HS",
            noteKey: "product.hsNeck.note"
        ),
        PatchProduct(
            id: "aimneck_neck_asset",
            titleKey: "product.neckAsset",
            subtitleKey: "product.neckAsset.subtitle",
            category: .aimbot,
            tab: .avatar,
            slot: .avatar,
            packageNames: ["aimneck_neck_asset"],
            badge: "HS",
            noteKey: nil
        ),
        PatchProduct(
            id: "proxy_hs1",
            titleKey: "product.proxyHs1",
            subtitleKey: "product.proxyHs1.subtitle",
            category: .aimbot,
            tab: .avatar,
            slot: .avatar,
            packageNames: ["proxy_hs1"],
            badge: "HS",
            noteKey: nil
        ),
        PatchProduct(
            id: "proxy_hs2",
            titleKey: "product.proxyHs2",
            subtitleKey: "product.proxyHs2.subtitle",
            category: .aimbot,
            tab: .avatar,
            slot: .avatar,
            packageNames: ["proxy_hs2"],
            badge: "HS",
            noteKey: nil
        ),
        PatchProduct(
            id: "proxy_hs3",
            titleKey: "product.proxyHs3",
            subtitleKey: "product.proxyHs3.subtitle",
            category: .aimbot,
            tab: .avatar,
            slot: .avatar,
            packageNames: ["proxy_hs3"],
            badge: "HS",
            noteKey: nil
        ),
        PatchProduct(
            id: "aimneck_torso_cache",
            titleKey: "product.aimPecho",
            subtitleKey: "product.aimPecho.subtitle",
            category: .aimbot,
            tab: .cache,
            slot: .cache,
            packageNames: ["aimneck_torso_cache", "aimtorso_cache"],
            badge: "SAFE",
            noteKey: "product.aimPecho.note"
        ),
        PatchProduct(
            id: "aimneck_cache",
            titleKey: "product.aimNeckCache",
            subtitleKey: "product.aimNeckCache.subtitle",
            category: .aimbot,
            tab: .cache,
            slot: .cache,
            packageNames: ["aimneck_neck", "aimneck_cache"],
            badge: "SAFE",
            noteKey: nil
        ),
        PatchProduct(
            id: "aimtorso_cache",
            titleKey: "product.aimTorso",
            subtitleKey: "product.aimTorso.subtitle",
            category: .aimbot,
            tab: .cache,
            slot: .cache,
            packageNames: ["aimtorso_cache"],
            badge: "SAFE",
            noteKey: nil
        ),

        // TEXTURAS — one occupied texture slot, same restore-ledger rules.
        PatchProduct(
            id: "texture_sielzada",
            titleKey: "product.texSielzada",
            subtitleKey: "product.texture.subtitle",
            category: .texture,
            tab: nil,
            slot: .texture,
            packageNames: ["texture_sielzada"],
            badge: "TEX",
            noteKey: "product.texture.note"
        ),
        PatchProduct(
            id: "texture_mordecai",
            titleKey: "product.texMordecai",
            subtitleKey: "product.texture.subtitle",
            category: .texture,
            tab: nil,
            slot: .texture,
            packageNames: ["texture_mordecai"],
            badge: "TEX",
            noteKey: "product.texture.note"
        ),
        PatchProduct(
            id: "texture_aranha",
            titleKey: "product.texAranha",
            subtitleKey: "product.texture.subtitle",
            category: .texture,
            tab: nil,
            slot: .texture,
            packageNames: ["texture_aranha"],
            badge: "TEX",
            noteKey: "product.texture.note"
        ),
        PatchProduct(
            id: "texture_alienx",
            titleKey: "product.texAlienX",
            subtitleKey: "product.texture.subtitle",
            category: .texture,
            tab: nil,
            slot: .texture,
            packageNames: ["texture_alienx"],
            badge: "TEX",
            noteKey: "product.texture.note"
        ),

        // FPS — writes the game preference plist, so it owns its own slot.
        PatchProduct(
            id: "fps_120",
            titleKey: "product.fps120",
            subtitleKey: "product.fps.subtitle",
            category: .fps,
            tab: nil,
            slot: .fps,
            packageNames: ["fps_120"],
            badge: "FPS",
            noteKey: "product.fps.note"
        ),
        PatchProduct(
            id: "fps_144",
            titleKey: "product.fps144",
            subtitleKey: "product.fps.subtitle",
            category: .fps,
            tab: nil,
            slot: .fps,
            packageNames: ["fps_144"],
            badge: "FPS",
            noteKey: "product.fps.note"
        )
    ]

    static var patchesDirectory: URL {
        AppInfo.documentsURL.appendingPathComponent("Patches", isDirectory: true)
    }

    static func product(id: String) -> PatchProduct? {
        products.first { $0.id == id }
    }

    static func products(for category: PatchCategory, tab: AimbotTab? = nil) -> [PatchProduct] {
        products.filter {
            $0.category == category && (tab == nil || $0.tab == tab)
        }
    }

    static func packageName(for product: PatchProduct) -> String? {
        product.packageNames.first { packageURL(name: $0) != nil }
    }

    static func packageURL(name: String) -> URL? {
        let clean = name.hasSuffix(".3105") ? String(name.dropLast(5)) : name
        let fileManager = FileManager.default
        let candidates = [
            patchesDirectory.appendingPathComponent("\(clean).3105"),
            AppInfo.documentsURL.appendingPathComponent("\(clean).3105")
        ]
        for candidate in candidates where fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }
        if let bundled = Bundle.main.url(forResource: clean, withExtension: "3105") {
            return bundled
        }
        if let bundled = Bundle.main.url(
            forResource: clean,
            withExtension: "3105",
            subdirectory: "Patches"
        ) {
            return bundled
        }
        return nil
    }

    static func packageURL(for product: PatchProduct) -> URL? {
        for name in product.packageNames {
            if let url = packageURL(name: name) {
                return url
            }
        }
        return nil
    }

    static func hasPackage(for product: PatchProduct) -> Bool {
        packageURL(for: product) != nil
    }

    /// True when the package exists only in `Documents/Patches`, i.e. it was
    /// pulled from the remote library rather than imported by the user.
    static func isRemotePackage(for product: PatchProduct) -> Bool {
        guard let url = packageURL(for: product) else { return false }
        return url.path.hasPrefix(patchesDirectory.path)
    }

    static func installedProductCount() -> Int {
        products.filter { hasPackage(for: $0) }.count
    }

    @discardableResult
    static func importPackage(from url: URL) throws -> (URL, PatchPackage) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        try FileManager.default.createDirectory(
            at: patchesDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        var fileName = url.lastPathComponent
        if !fileName.lowercased().hasSuffix(".3105") {
            fileName += ".3105"
        }
        let destination = patchesDirectory.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: url, to: destination)

        do {
            let package = try PatchPackage.load(from: destination)
            log("package: imported \(fileName) — \(package.displayName), \(package.rules.count) rules", level: .success)
            return (destination, package)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
}
