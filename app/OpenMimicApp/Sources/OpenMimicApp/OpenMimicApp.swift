import SwiftUI

@main
struct OpenMimicApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Label {
                Text("OpenMimic")
            } icon: {
                Image(systemName: appState.menuBarIcon)
                    .symbolRenderingMode(.palette)
            }
        }
        .menuBarExtraStyle(.window)

        // Onboarding window (shown on first launch or when permissions missing)
        Window("OpenMimic Setup", id: "onboarding") {
            OnboardingView()
                .environmentObject(appState)
                .frame(width: 520, height: 480)
        }
        .windowResizability(.contentSize)
    }
}
