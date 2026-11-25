import SwiftUI

struct SplashView: View {
    let onFinished: () -> Void

    @EnvironmentObject private var state: AppState
    @Environment(\.t) private var t

    @State private var progress: CGFloat = 0
    @State private var showMusicPrompt = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 4)
                        .frame(width: 120, height: 120)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            Theme.orange,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 120, height: 120)

                    AppTile(size: 84, letter: "D")
                }

                Text("dope")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.top, 18)

                Text(AppInfo.machine)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .padding(.top, 4)

                Text("iOS \(AppInfo.osVersion)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .padding(.top, 2)

                Spacer(minLength: 24)

                VStack(spacing: 12) {
                    if showMusicPrompt {
                        musicCard
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    Button {
                        state.openURL(AppLinks.installProfile)
                    } label: {
                        HStack(spacing: 12) {
                            IconBadge(systemName: "square.and.arrow.down", size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t("splash.profile.title"))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text(t("splash.profile.subtitle"))
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.white.opacity(0.45))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.35))
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(Color.white.opacity(0.7))
                            .scaleEffect(0.8)
                        Text(t("common.loading"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.45))
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, Theme.pageInset)
                .padding(.bottom, 28)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 2.0)) {
                progress = 0.8
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                onFinished()
            }
        }
    }

    private var musicCard: some View {
        VStack(spacing: 12) {
            Text(t("splash.music.title"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            HStack(spacing: 10) {
                Button {
                    state.musicEnabled = false
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showMusicPrompt = false
                    }
                } label: {
                    Text(t("common.no"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.10))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    state.musicEnabled = true
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showMusicPrompt = false
                    }
                } label: {
                    Text(t("common.yes"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Theme.orange)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }
}
