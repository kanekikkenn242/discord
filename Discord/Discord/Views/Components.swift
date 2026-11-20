import SwiftUI
import UIKit

// MARK: - Patch card

struct PatchCard: View {
    let product: PatchProduct
    let status: PatchProductStatus
    let busy: Bool
    let onToggle: (Bool) -> Void

    @Environment(\.t) private var t

    private var enabled: Bool { status.isLoaded }

    private var statusColor: Color {
        switch status {
        case .loaded: return Theme.green
        case .notLoaded: return Theme.textSecondary
        case .partial: return Theme.orange
        case .packageMissing, .unavailable: return Theme.red
        }
    }

    private var statusText: String {
        switch status {
        case .loaded: return t("status.loaded")
        case .notLoaded: return t("status.notLoaded")
        case .partial: return t("status.partial")
        case .packageMissing: return t("status.packageMissing")
        case .unavailable(let detail): return detail
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(t(product.titleKey))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        if let badge = product.badge {
                            StatusPill(text: badge, color: Theme.green)
                        }
                    }

                    Text(t(product.subtitleKey))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 6)

                if busy {
                    ProgressView()
                        .tint(Theme.orange)
                        .scaleEffect(0.8)
                        .frame(width: 44, height: 30)
                } else {
                    Toggle("", isOn: Binding(
                        get: { enabled },
                        set: { onToggle($0) }
                    ))
                    .labelsHidden()
                    .tint(Theme.orange)
                    .disabled(status == .packageMissing || status.isUnavailable)
                }
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }

            if let noteKey = product.noteKey {
                Text(t(noteKey))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .appCard(padding: 14)
    }
}

// MARK: - Log console

struct LogConsole: View {
    @EnvironmentObject private var log: AppLog
    @Environment(\.t) private var t

    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.orange)
                Text(t("game.log.title"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                // The console is not selectable text; these two buttons are
                // the only way to get a failure report off the device.
                Button {
                    UIPasteboard.general.string = log.transcript
                    copied = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_600_000_000)
                        copied = false
                    }
                } label: {
                    Text(t(copied ? "common.copied" : "common.copy"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(copied ? Theme.green : Theme.orange)
                }
                .buttonStyle(.plain)
                .disabled(log.entries.isEmpty)

                if !log.entries.isEmpty {
                    ShareLink(item: log.transcript) {
                        Text(t("common.share"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.orange)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    log.clear()
                } label: {
                    Text(t("common.clear"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Rectangle()
                .fill(Theme.border)
                .frame(height: 0.5)

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if log.entries.isEmpty {
                            Text(t("game.log.empty"))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.textSecondary.opacity(0.7))
                                .padding(.vertical, 6)
                        }

                        ForEach(log.entries) { entry in
                            HStack(alignment: .top, spacing: 6) {
                                Text(entry.timestamp)
                                    .foregroundStyle(Theme.textSecondary.opacity(0.6))
                                Text(entry.level.symbol)
                                    .foregroundStyle(color(for: entry.level))
                                Text(entry.message)
                                    .foregroundStyle(color(for: entry.level).opacity(0.92))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .font(.system(size: 10, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(entry.id)
                        }
                    }
                    .padding(10)
                }
                .frame(height: 190)
                .onChange(of: log.revision) { _ in
                    guard let last = log.entries.last else { return }
                    withAnimation(.linear(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 0.5)
        )
    }

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .info: return .primary
        case .success: return Theme.green
        case .warning: return Theme.orange
        case .error: return Theme.red
        case .trace: return Theme.textSecondary
        }
    }
}

// MARK: - Tabs

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case game
    case profile
    case support

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .game: return "flame.fill"
        case .profile: return "person.fill"
        case .support: return "headphones"
        }
    }

    var titleKey: String {
        switch self {
        case .home: return "home.title"
        case .game: return "game.title"
        case .profile: return "profile.title"
        case .support: return "support.title"
        }
    }
}

struct AppTabBar: View {
    @Binding var selection: AppTab
    @Environment(\.t) private var t

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            if tab == .game {
                                Circle()
                                    .fill(selection == tab ? Theme.orange : Theme.secondary)
                                    .frame(width: 30, height: 30)
                                Image(systemName: tab.icon)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(selection == tab ? .white : Theme.textSecondary)
                            } else {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(selection == tab ? Theme.orange : Theme.textSecondary)
                                    .frame(width: 30, height: 30)
                            }
                        }

                        Text(t(tab.titleKey))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(selection == tab ? Theme.orange : Theme.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(selection == tab ? Theme.orange.opacity(0.10) : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.card)
                .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 0.5)
        )
        .padding(.horizontal, Theme.pageInset)
        .padding(.bottom, 6)
    }
}

// MARK: - Empty state

struct EmptyStateCard: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.textSecondary.opacity(0.6))
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .appCard()
    }
}

// MARK: - Ledger

enum LedgerStore {
    static func entries() -> [LedgerEntry] {
        guard let data = try? Data(contentsOf: BackupStore.ledgerURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let lines = String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .compactMap { line in
                try? decoder.decode(LedgerEntry.self, from: Data(line.utf8))
            }
        return Array(lines.reversed())
    }
}

struct NoticesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.t) private var t

    private let entries = LedgerStore.entries()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    if entries.isEmpty {
                        EmptyStateCard(
                            icon: "bell.slash",
                            title: t("notices.title"),
                            subtitle: t("notices.empty")
                        )
                    } else {
                        ForEach(entries.indices, id: \.self) { index in
                            noticeCard(entries[index])
                        }
                    }
                }
                .padding(Theme.pageInset)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(t("notices.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(t("common.close")) { dismiss() }
                        .foregroundStyle(Theme.orange)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func noticeCard(_ entry: LedgerEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(actionLabel(entry.action))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(entry.result == "success" ? Theme.green : Theme.red)
                Spacer()
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
            }

            Text(entry.packageName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)

            Text("\(entry.backend) · \(entry.paths.count) file(s)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)

            Text(entry.message)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .appCard(padding: 12)
    }

    private func actionLabel(_ action: String) -> String {
        switch action {
        case "apply": return t("notices.applied")
        case "restore": return t("notices.restored")
        default: return t("notices.failed")
        }
    }
}
