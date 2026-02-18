import SwiftUI

/// Step-by-step onboarding for first-run permission setup.
struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentStep = 0

    private let steps = [
        OnboardingStep(
            title: "Welcome to OpenMimic",
            description: "OpenMimic silently observes your workflows and generates semantic SOPs that AI agents can execute.",
            icon: "eye.circle.fill",
            action: .none
        ),
        OnboardingStep(
            title: "Accessibility Permission",
            description: "OpenMimic needs Accessibility access to observe window titles and UI elements. This is read-only — it never takes actions.",
            icon: "hand.raised.circle.fill",
            action: .accessibility
        ),
        OnboardingStep(
            title: "Screen Recording Permission",
            description: "Screen Recording access allows OpenMimic to capture screenshots for visual context. Images are stored locally and encrypted.",
            icon: "rectangle.dashed.badge.record",
            action: .screenRecording
        ),
        OnboardingStep(
            title: "Chrome Extension",
            description: "Install the OpenMimic Chrome extension for rich browser observation. Load it as an unpacked extension from the installation directory.",
            icon: "globe.badge.chevron.backward",
            action: .chromeExtension
        ),
        OnboardingStep(
            title: "Ready to Go!",
            description: "OpenMimic will now observe your workflows in the background. Check the menu bar icon for status. SOPs appear once enough patterns are detected.",
            icon: "checkmark.circle.fill",
            action: .none
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicators
            HStack(spacing: 8) {
                ForEach(0..<steps.count, id: \.self) { index in
                    Circle()
                        .fill(index <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 20)

            Spacer()

            // Current step content
            let step = steps[currentStep]
            VStack(spacing: 16) {
                Image(systemName: step.icon)
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)

                Text(step.title)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(step.description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)

                // Permission status / action button
                stepActionView(for: step)
            }
            .padding(.horizontal, 40)

            Spacer()

            // Navigation
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                }

                Spacer()

                if currentStep < steps.count - 1 {
                    Button("Next") {
                        withAnimation { currentStep += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Start Observing") {
                        ServiceController.startAll()
                        NSApplication.shared.keyWindow?.close()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private func stepActionView(for step: OnboardingStep) -> some View {
        switch step.action {
        case .accessibility:
            VStack(spacing: 8) {
                PermissionStatusBadge(
                    granted: appState.accessibilityGranted,
                    grantedLabel: "Accessibility Granted",
                    deniedLabel: "Accessibility Not Granted"
                )
                if !appState.accessibilityGranted {
                    Button("Grant Accessibility Access") {
                        PermissionChecker.requestAccessibility()
                    }
                    .buttonStyle(.bordered)
                }
            }

        case .screenRecording:
            VStack(spacing: 8) {
                PermissionStatusBadge(
                    granted: appState.screenRecordingGranted,
                    grantedLabel: "Screen Recording Granted",
                    deniedLabel: "Screen Recording Not Granted"
                )
                if !appState.screenRecordingGranted {
                    Button("Open Screen Recording Settings") {
                        PermissionChecker.openScreenRecordingSettings()
                    }
                    .buttonStyle(.bordered)
                }
            }

        case .chromeExtension:
            VStack(spacing: 8) {
                Text("Extension location:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("/usr/local/lib/openmimic/extension/")
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .textSelection(.enabled)
                Button("Open Chrome Extensions Page") {
                    if let url = URL(string: "chrome://extensions") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }

        case .none:
            EmptyView()
        }
    }
}

// MARK: - Models

struct OnboardingStep {
    let title: String
    let description: String
    let icon: String
    let action: OnboardingAction
}

enum OnboardingAction {
    case none
    case accessibility
    case screenRecording
    case chromeExtension
}

// MARK: - Subviews

struct PermissionStatusBadge: View {
    let granted: Bool
    let grantedLabel: String
    let deniedLabel: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(granted ? .green : .orange)
            Text(granted ? grantedLabel : deniedLabel)
                .font(.caption)
                .foregroundColor(granted ? .green : .orange)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill((granted ? Color.green : Color.orange).opacity(0.1))
        )
    }
}
