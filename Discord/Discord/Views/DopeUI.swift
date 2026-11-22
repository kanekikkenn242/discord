import SwiftUI
import UIKit
import ImageIO
import Combine

extension Color {
    /// RGB hex used by the dope accent picker and persisted in AppStorage.
    var dopeHex: Int {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Int(r * 255) << 16) | (Int(g * 255) << 8) | Int(b * 255)
    }
}

// MARK: - Glass primitives used by the dope 7.0 style

private struct GlassSurface: ViewModifier {
    var radius: CGFloat = 18
    var opacity: Double = 0.14
    var stroke: Double = 0.22

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Color.white.opacity(opacity))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(stroke), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.22), radius: 14, y: 6)
    }
}

extension View {
    func dopeGlass(radius: CGFloat = 18, opacity: Double = 0.14) -> some View {
        modifier(GlassSurface(radius: radius, opacity: opacity))
    }
}

// MARK: - Animated banner (the injector ships animated GIF banners)

struct AnimatedGIFView: View {
    let resource: String
    var aspect: CGFloat = 16 / 9

    @State private var images: [UIImage] = []
    @State private var duration: Double = 0
    @State private var frame = 0

    var body: some View {
        Group {
            if images.isEmpty {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.06))
            } else {
                Image(uiImage: images[frame % images.count])
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(aspect, contentMode: .fill)
        .clipped()
        .onAppear { load() }
        .onChange(of: resource) { load($0) }
        .onReceive(
            Timer.publish(
                every: images.isEmpty ? 0.1 : max(0.03, duration / Double(images.count)),
                on: .main, in: .common
            ).autoconnect()
        ) { _ in
            guard !images.isEmpty else { return }
            frame = (frame + 1) % images.count
        }
    }

    private func load() {
        load(resource)
    }

    private func load(_ name: String) {
        guard let url = Bundle.main.url(
            forResource: (name as NSString).deletingPathExtension,
            withExtension: (name as NSString).pathExtension.isEmpty
                ? "gif" : (name as NSString).pathExtension
        ),
        let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return }

        let count = CGImageSourceGetCount(source)
        var frames: [UIImage] = []
        var total: Double = 0
        for index in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(UIImage(cgImage: cg))
            let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any]
            let gif = props?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
            let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double)
                ?? (gif?[kCGImagePropertyGIFDelayTime as String] as? Double) ?? 0.1
            total += max(0.02, delay)
        }
        guard !frames.isEmpty else { return }
        images = frames
        duration = total
        frame = 0
    }
}

// MARK: - Liquid segmented control

struct LiquidSegment<Value: Hashable>: View {
    let values: [Value]
    let title: (Value) -> String
    @Binding var selection: Value

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width / CGFloat(max(1, values.count))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.6)
                    )
                    .frame(width: width - 4)
                    .offset(x: CGFloat(index) * width + 2)
                    .animation(.spring(response: 0.32, dampingFraction: 0.82), value: selection)

                HStack(spacing: 0) {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                        Button {
                            selection = value
                        } label: {
                            Text(title(value))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(value == selection ? .primary : .secondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 36)
            .padding(2)
        }
        .frame(height: 40)
    }

    private var index: Int {
        values.firstIndex(of: selection) ?? 0
    }
}

// MARK: - Glass switch

struct GlassSwitch: View {
    @Binding var isOn: Bool
    var tint: Color = .orange

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? tint.opacity(0.85) : Color.white.opacity(0.14))
                Circle()
                    .fill(.white)
                    .frame(width: 24, height: 24)
                    .padding(3)
                    .shadow(radius: 2)
            }
            .frame(width: 50, height: 30)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "On" : "Off")
    }
}

// MARK: - Bottom tab bar

enum DopeTab: Int, CaseIterable {
    case functions, matches, info

    var systemImage: String {
        switch self {
        case .functions: return "square.grid.2x2.fill"
        case .matches: return "gamecontroller.fill"
        case .info: return "person.crop.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .functions: return "functions"
        case .matches: return "matches"
        case .info: return "info"
        }
    }
}

struct DopeTabBar: View {
    @Binding var selection: DopeTab
    @Environment(\.t) private var t

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width / CGFloat(DopeTab.allCases.count)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.7)
                    )
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.14))
                    .frame(width: width - 8, height: 46)
                    .offset(x: CGFloat(selection.rawValue) * width + 4)
                    .animation(.spring(response: 0.3, dampingFraction: 0.84), value: selection)

                HStack(spacing: 0) {
                    ForEach(DopeTab.allCases, id: \.rawValue) { tab in
                        Button { selection = tab } label: {
                            VStack(spacing: 3) {
                                Image(systemName: tab.systemImage)
                                    .font(.system(size: 18, weight: .semibold))
                                Text(t("dope.tab.\(tab.label)"))
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(tab == selection ? .primary : .secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(height: 56)
        .padding(.horizontal, 14)
    }
}

// MARK: - Small status indicator (dope's floating status badge)

struct DopeStatusHUD: View {
    let text: String
    var color: Color = .green

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .dopeGlass(radius: 14)
    }
}
