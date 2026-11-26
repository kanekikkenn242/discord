import SwiftUI

/// A SwiftUI replica of the `dope` injector shell found in Payload-2: three
/// draggable-looking glass tabs (Funções / Partidas / Info), a remote-style
/// animated banner, liquid mode selector, glass switches and a key/licence
/// card. Every switch still drives the existing patch engine.
struct DopeMainView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var patches: PatchController
    @Environment(\.t) private var t
    @AppStorage("dope.selectedBanner") private var banner = "dope1black.gif"
    @State private var tab: DopeTab = .functions
    @State private var showBannerPicker = false
    @State private var showGate = false

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [Color(hex: 0x17171F), Color(hex: 0x07070B)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Group {
                switch tab {
                case .functions: DopeFunctionsView(banner: $banner)
                case .matches: DopeMatchesView()
                case .info: DopeInfoView(banner: $banner, showBannerPicker: $showBannerPicker)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 72)

            DopeTabBar(selection: $tab)
        }
        .sheet(isPresented: $state.showSettings) { SettingsView() }
        .sheet(isPresented: $state.showActivation) { ActivationSheet() }
        .sheet(isPresented: $showBannerPicker) {
            DopeBannerPicker(selection: $banner)
                .presentationDetents([.medium])
        }
        .overlay {
            if showGate {
                DopeLoginGate(isPresented: $showGate)
            }
        }
        .overlay {
            if let busy = patches.busyProductID {
                DopeProcessDialog(
                    name: displayName(for: busy),
                    removing: patches.busyAction == "restore"
                )
            }
        }
        .onAppear {
            state.refreshPatches()
            showGate = !state.activation.isActivated
        }
    }

    private func displayName(for id: String) -> String {
        guard let product = FreeFireCatalog.product(id: id) else { return id }
        return t(product.titleKey)
    }
}

// MARK: - Exact dope literals

private enum DS {
    static let functions = "FUNÇÕES"
    static let matches = "PARTIDAS"
    static let info = "Info"
    static let mode = "HS + ANTENA"
    static let modeSubtitle = "Alternar entre HS e HS + Antena"
    static let overlay = "Overlay"
    static let textures = "TEXTURAS"
    static let selected = "Selecionada"
    static let config = "CONFIG"
    static let statusCard = "Status da conta"
    static let active = "Ativo"
    static let key = "Key"
    static let keyMask = "KEY-XXXX-XXXX"
    static let copyKey = "   Copiar key"
    static let copied = "Key copiada"
    static let store = "    Loja oficial"
    static let validity = "Validade"
    static let remaining = "Tempo restante"
    static let device = "DISPOSITIVO"
    static let model = "Modelo"
    static let compatibility = "Compatibilidade"
    static let bannerTitle = "Banner da tela principal"
    static let chooseBanner = "Escolher banner da tela principal"
    static let injected = "Injetado com sucesso"
    static let removed = "Desinjetado com sucesso"
    static let loginTitle = "Entre para continuar"
    static let loginHelp = "Precisa de uma key? Clique aqui"
    static let enter = "Entrar"
    static let cancel = "Cancelar"
    static let themes = ["Preto", "Branco", "Vermelho", "Azul", "Aurora", "Fluorite"]
    static let functionNames = ["painel", "aimbot e esp", "120/144 fps", "assembly", "aimbot & esp"]
    static let textureNames = [
        "textura sielzada", "textura mordecai", "textura homem-aranha",
        "textura alien-x", "personagem santino", "personagem alok despertado"
    ]
}

// MARK: - Functions page

private struct DopeFunctionsView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var patches: PatchController
    @Environment(\.t) private var t
    @Binding var banner: String

    @State private var mode = 0
    @State private var overlay = true
    @State private var result: (title: String, body: String, ok: Bool)?
    @AppStorage("dope.accentHex") private var accentHex: Int = 0xFF9500

    private var accent: Color { Color(hex: UInt32(accentHex)) }

    private var headshotProducts: [PatchProduct] {
        let hsIDs = ["dope_hs_pescoco", "dope_hs_alto", "dope_hs_peito"]
        let antennaIDs = [
            "dope_hs_alto_antena", "dope_hs_pescoco_antena",
            "dope_hs_barriga_antena", "dope_antena_mao"
        ]
        let ids = mode == 0 ? hsIDs : antennaIDs
        return ids.compactMap { FreeFireCatalog.product(id: $0) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                AnimatedGIFView(resource: banner, aspect: 2.05)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(DS.functions)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                    Spacer()
                    Button {
                        withAnimation { mode = (mode + 1) % 2 }
                    } label: {
                        Text(mode == 0 ? "hs" : "hs + antena")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                VStack(spacing: 9) {
                    ForEach(headshotProducts) { product in
                        DopeFunctionRow(
                            product: product,
                            status: patches.status(for: product),
                            busy: patches.busyProductID == product.id,
                            tint: accent
                        ) { enabled in
                            state.setPatch(product, enabled: enabled)
                            let label = t(product.titleKey)
                            result = enabled
                                ? (DS.injected, "\(label) foi injetada.", true)
                                : (DS.removed, "\(label) foi removida.", false)
                        }
                    }
                }

                Text(t("home.footer"))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
        }
        .overlay {
            if let result {
                ZStack {
                    Color.black.opacity(0.72).ignoresSafeArea()
                    VStack(spacing: 14) {
                        Image(systemName: result.ok ? "checkmark" : "xmark")
                            .font(.system(size: 26, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 58, height: 58)
                            .background(
                                Circle().fill(result.ok ? Color.black : Color.red)
                            )
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.12)))
                        Text(result.title)
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        Text(result.body)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                        Divider().background(Color.white.opacity(0.12))
                        Button {
                            self.result = nil
                        } label: {
                            Text("OK")
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(22)
                    .frame(maxWidth: 320)
                    .background(Color(hex: 0x24242B), in: RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.white.opacity(0.12)))
                    .padding(.horizontal, 34)
                }
            }
        }
    }
}

private struct DopeFunctionRow: View {
    let product: PatchProduct
    let status: PatchProductStatus
    let busy: Bool
    var tint: Color = .orange
    let onToggle: (Bool) -> Void

    @Environment(\.t) private var t

    private var enabled: Bool { status.isLoaded }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(t(product.titleKey))
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
                Text(t(product.subtitleKey))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            if busy {
                ProgressView().scaleEffect(0.75)
            } else {
                GlassSwitch(isOn: Binding(get: { enabled }, set: onToggle), tint: tint)
            }
        }
        .padding(12)
        .dopeGlass(radius: 16)
    }
}

/// Reset guest is an action, not a state: it must rewrite
/// {"resetGuest":true} on every tap so a banned guest can be replaced.
private struct DopeResetGuestRow: View {
    let product: PatchProduct
    let busy: Bool
    let onReset: () -> Void

    @Environment(\.t) private var t

    var body: some View {
        Button { onReset() } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(t(product.titleKey))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    Text(t(product.subtitleKey))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 4)
                if busy {
                    ProgressView().scaleEffect(0.75)
                } else {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.orange)
                }
            }
            .padding(12)
            .dopeGlass(radius: 16)
        }
        .buttonStyle(.plain)
    }
}

private struct DopeTextureRow: View {
    let name: String
    let product: PatchProduct?
    let status: PatchProductStatus?
    var tint: Color = .orange
    let onToggle: (Bool) -> Void

    private var enabled: Bool { status?.isLoaded ?? false }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(tint.opacity(enabled ? 0.26 : 0.08))
                Image(systemName: "photo")
                    .font(.system(size: 14))
                    .foregroundStyle(enabled ? tint : .secondary)
            }
            .frame(width: 36, height: 36)
            Text(name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(product == nil ? .secondary : .primary)
            Spacer()
            if enabled {
                Text(DS.selected)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(tint)
            }
            if let product {
                GlassSwitch(
                    isOn: Binding(get: { enabled }, set: onToggle),
                    tint: tint
                )
                .disabled(product.packageNames.isEmpty)
            } else {
                GlassSwitch(isOn: .constant(false), tint: .gray).disabled(true)
            }
        }
        .padding(11)
        .dopeGlass(radius: 15)
    }
}

// MARK: - Matches page (player functions)

private struct DopeMatchesView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var patches: PatchController

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                Text(DS.matches)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 9) {
                    ForEach(FreeFireCatalog.products(for: .partidas)
                        .filter { $0.id != "ever_asso" }) { product in
                        if product.id == "ever_reset_guest" {
                            DopeResetGuestRow(
                                product: product,
                                busy: patches.busyProductID == product.id
                            ) {
                                // Always write {"resetGuest":true} again, even
                                // if it was applied before — a banned guest
                                // account needs a fresh reset every time.
                                state.setPatch(product, enabled: true)
                            }
                        } else {
                            DopeFunctionRow(
                                product: product,
                                status: patches.status(for: product),
                                busy: patches.busyProductID == product.id
                            ) { enabled in
                                state.setPatch(product, enabled: enabled)
                            }
                        }
                    }
                }

                Text(DS.textures)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)

                VStack(spacing: 9) {
                    ForEach(FreeFireCatalog.products(for: .texture)) { product in
                        DopeFunctionRow(
                            product: product,
                            status: patches.status(for: product),
                            busy: patches.busyProductID == product.id
                        ) { enabled in
                            state.setPatch(product, enabled: enabled)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
        }
    }
}

// MARK: - Info page

private struct DopeInfoView: View {
    @EnvironmentObject private var state: AppState
    @Binding var banner: String
    @Binding var showBannerPicker: Bool

    @State private var revealKey = false
    @State private var showAccentPicker = false
    @State private var tick = Date()
    @AppStorage("dope.themeIndex") private var themeIndex = 0
    @AppStorage("dope.accentHex") private var accentHex: Int = 0xFF9500

    private var accent: Color { Color(hex: UInt32(accentHex)) }

    private var keyText: String {
        guard state.activation.isActivated else { return DS.keyMask }
        let stored = UserDefaults.standard.string(forKey: "discord.activation.key") ?? ""
        if revealKey { return stored }
        return state.activation.statusText
    }

    private var licenseExpiry: Date? {
        state.activation.expiresAt
            ?? state.activation.activatedAt?.addingTimeInterval(365 * 24 * 3600)
    }

    private var expiryText: String {
        guard let date = licenseExpiry else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy HH:mm:ss"
        return formatter.string(from: date)
    }

    private var remainingText: String {
        guard let date = licenseExpiry else { return "—" }
        let seconds = Int(date.timeIntervalSince(tick))
        guard seconds > 0 else { return "0d 00:00:00" }
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        return String(format: "%ldd %02ld:%02ld:%02ld", days, hours, minutes, secs)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 15) {
                HStack(spacing: 13) {
                    DopeAvatar(accent: accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("evergarden")
                            .font(.system(size: 25, weight: .heavy, design: .rounded))
                        Text("config.avatar")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { state.showSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18))
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        themeIndex = (themeIndex + 1) % DS.themes.count
                        accentHex = [0x000000, 0xFFFFFF, 0xFF3B30, 0x0A84FF,
                                     0x7CE7B5, 0x9B8CFF][themeIndex]
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: ["moon.fill", "sun.max.fill", "drop.fill",
                                               "drop.triangle.fill", "sparkles", "waveform.path.ecg"][themeIndex])
                                .font(.system(size: 17))
                            Text(DS.themes[themeIndex])
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 62)
                        .dopeGlass(radius: 16)
                    }
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.6).onEnded { _ in showAccentPicker = true }
                    )
                    Button { showBannerPicker = true } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 17))
                            Text("Banner")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 62)
                        .dopeGlass(radius: 16)
                    }
                }

                VStack(spacing: 0) {
                    InfoRow(icon: "checkmark.circle.fill", title: DS.statusCard, value: state.activation.isActivated ? DS.active : "—", valueColor: .green)
                    Divider().background(Color.white.opacity(0.08))
                    HStack(spacing: 10) {
                        Image(systemName: "key.fill").foregroundStyle(.orange).frame(width: 20)
                        Text(DS.key).font(.system(size: 12))
                        Spacer()
                        Text(keyText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Button { revealKey.toggle() } label: {
                            Image(systemName: revealKey ? "eye.slash.fill" : "eye.fill").foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 44)
                    Divider().background(Color.white.opacity(0.08))
                    Button {
                        UIPasteboard.general.string = UserDefaults.standard.string(forKey: "discord.activation.key")
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.on.doc").foregroundStyle(.orange).frame(width: 20)
                            Text(DS.copyKey).font(.system(size: 12))
                            Spacer()
                        }
                    }
                    .frame(height: 44)
                    Divider().background(Color.white.opacity(0.08))
                    Link(destination: URL(string: "https://discord.gg/ZAUR8CXVCJ")!) {
                        HStack(spacing: 10) {
                            Image(systemName: "cart.fill").foregroundStyle(.orange).frame(width: 20)
                            Text(DS.store).font(.system(size: 12))
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 44)
                    Divider().background(Color.white.opacity(0.08))
                    Button {
                        if let product = FreeFireCatalog.product(id: "ever_reset_guest") {
                            state.setPatch(product, enabled: true)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.counterclockwise").foregroundStyle(.orange).frame(width: 20)
                            Text("Reset guest").font(.system(size: 12))
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 44)
                }
                .padding(.horizontal, 14)
                .dopeGlass(radius: 18)

                VStack(spacing: 0) {
                    InfoRow(icon: "calendar", title: DS.validity, value: expiryText)
                    Divider().background(Color.white.opacity(0.08))
                    InfoRow(icon: "clock.fill", title: DS.remaining, value: remainingText)
                }
                .padding(.horizontal, 14)
                .dopeGlass(radius: 18)

                VStack(spacing: 0) {
                    Text(DS.device)
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)
                    InfoRow(icon: "iphone", title: DS.model, value: state.deviceModel)
                    Divider().background(Color.white.opacity(0.08))
                    InfoRow(icon: "gearshape.fill", title: "iOS", value: state.deviceOS)
                    Divider().background(Color.white.opacity(0.08))
                    InfoRow(
                        icon: "checkmark.shield.fill",
                        title: DS.compatibility,
                        value: state.exploitStatus == .unsupported ? "Não" : "Sim",
                        valueColor: state.exploitStatus == .unsupported ? .red : .green
                    )
                }
                .padding(.horizontal, 14)
                .dopeGlass(radius: 18)

                AnimatedGIFView(resource: "bkebe.gif", aspect: 2.1)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 10)
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now in
            tick = now
        }
        .sheet(isPresented: $showAccentPicker) {
            ColorPicker("Accent", selection: Binding(
                get: { Color(hex: UInt32(accentHex)) },
                set: { color in accentHex = color.dopeHex }
            ))
            .padding()
            .presentationDetents([.height(180)])
        }
    }
}

private struct InfoRow: View {
    let icon: String
    let title: String
    let value: String
    var valueColor: Color = .secondary

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(.orange).frame(width: 20)
            Text(title).font(.system(size: 12))
            Spacer()
            Text(value).font(.system(size: 11, weight: .medium)).foregroundStyle(valueColor).lineLimit(1)
        }
        .frame(height: 42)
    }
}

private struct DopeAvatar: View {
    let accent: Color
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [accent, accent.opacity(0.35)], startPoint: .top, endPoint: .bottom))
            Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5)
            Image(systemName: "person.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 56, height: 56)
    }
}

// MARK: - Banner picker

private struct DopeBannerPicker: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss

    private let options = [
        ("dope1black.gif", "Evergarden - Black"),
        ("dope2white.gif", "Evergarden - White"),
        ("eyesbanner.gif", "Eyes Banner"),
        ("evergarden2.gif", "Evergarden 8.0"),
        ("bkebe.gif", "Banner animado")
    ]

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(DS.bannerTitle)
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                }
            }
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(options, id: \.0) { resource, title in
                        Button {
                            selection = resource
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "film.fill").foregroundStyle(.orange)
                                Text(title).font(.system(size: 13, weight: .medium))
                                Spacer()
                                if selection == resource {
                                    Image(systemName: "checkmark").foregroundStyle(.green)
                                }
                            }
                            .padding(12)
                            .dopeGlass(radius: 14)
                        }
                    }
                }
            }
        }
        .padding(16)
    }
}

// MARK: - Login gate

private struct DopeLoginGate: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var state: AppState
    @State private var key = ""
    @State private var error: String?
    @State private var showHelp = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("evergarden")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                Text(DS.loginTitle)
                    .font(.system(size: 13))

                TextField(DS.keyMask, text: $key)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .padding(.horizontal)

                if let error {
                    Text(error).font(.system(size: 11)).foregroundStyle(.red)
                }

                Button {
                    state.activation.key = key
                    Task {
                        await state.activation.activate()
                        if state.activation.isActivated { isPresented = false }
                        else { error = state.activation.errorMessage ?? "invalid key" }
                    }
                } label: {
                    Text(DS.enter)
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .dopeGlass(radius: 14)
                }
                .padding(.horizontal)

                Button { showHelp.toggle() } label: {
                    Text(DS.loginHelp).font(.system(size: 11)).foregroundStyle(.orange)
                }
                if showHelp {
                    Link("Discord", destination: URL(string: "https://discord.gg/ZAUR8CXVCJ")!)
                        .font(.system(size: 11))
                }

                Button(DS.cancel) {
                    isPresented = false
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
            .padding(24)
            .dopeGlass(radius: 22)
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - Process dialog (the exact log lines the injector shows)

private struct DopeProcessDialog: View {
    let name: String
    var removing: Bool = false
    @State private var step = 0

    private var steps: [String] {
        removing
            ? ["Preparando a restauração de \(name)...",
               "Localizando o backup original...",
               "Restaurando o arquivo anterior...",
               "Verificando o resultado da remoção..."]
            : ["Preparando \(name)...",
               "Verificando os componentes necessários..."]
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.9)
                    Text("\(removing ? "Removendo" : "Injetando") \(name)")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                }
                Text(removing
                     ? "Não feche o app enquanto a remoção está em andamento."
                     : "Não feche o app enquanto a injeção está em andamento.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(0..<min(step + 1, steps.count), id: \.self) { index in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(index + 1).")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.45))
                            Text(steps[index])
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                }
                .padding(.top, 4)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0x24242B), in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
            )
            .padding(.horizontal, 34)
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
                DispatchQueue.main.async {
                    if step < steps.count - 1 { step += 1 }
                    else { timer.invalidate() }
                }
            }
        }
    }
}
