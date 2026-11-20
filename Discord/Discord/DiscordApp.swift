import SwiftUI

@main
struct DiscordApp: App {
    @StateObject private var state = AppState()
    @State private var phase: LaunchPhase = .splash

    init() {
        setupLogCapture()
        log("app: Discord launching — iOS \(AppInfo.osVersion) (\(AppInfo.osBuild)) \(AppInfo.machine)")
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Theme.background.ignoresSafeArea()

                switch phase {
                case .splash:
                    SplashView {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            phase = state.hasCompletedOnboarding ? .main : .onboarding
                        }
                    }
                    .transition(.opacity)

                case .onboarding:
                    OnboardingView {
                        state.hasCompletedOnboarding = true
                        state.refreshPatches()
                        withAnimation(.easeInOut(duration: 0.3)) {
                            phase = .main
                        }
                    }
                    .transition(.opacity)

                case .main:
                    MainTabView()
                        .transition(.opacity)
                }
            }
            .environmentObject(state)
            .environmentObject(state.patches)
            .environmentObject(state.activation)
            .environmentObject(state.pairing)
            .environmentObject(state.log)
            .environment(\.t, Localizer(language: state.language))
            .environment(\.locale, state.language.locale)
            .preferredColorScheme(state.appearance.colorScheme)
            .onAppear {
                state.pairing.refresh()
            }
        }
    }
}

private enum LaunchPhase {
    case splash
    case onboarding
    case main
}
