import SwiftUI

/// Premium onboarding experience — 8 screens with progressive disclosure.
///
/// Screens: Welcome → Teach by Doing → What You'll Get → Review Cycle →
///          Permissions → AI Model → Browser Extension → Ready (First Recording)
struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentStep = 0
    @State private var extensionPath: String = ""
    @State private var chromeOpenError: String? = nil
    @State private var vlmPullInProgress = false
    @State private var vlmPullOutput = ""
    @State private var serviceStartFailed = false

    // Cloud VLM state
    enum VLMMode: String, CaseIterable {
        case local = "Local"
        case cloud = "Cloud"
    }

    enum RemoteProvider: String, CaseIterable, Identifiable {
        case openai = "openai"
        case anthropic = "anthropic"
        case google = "google"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .openai: return "OpenAI"
            case .anthropic: return "Anthropic (Claude)"
            case .google: return "Google (Gemini)"
            }
        }

        var defaultModel: String {
            switch self {
            case .openai: return "gpt-4.1-mini"
            case .anthropic: return "claude-sonnet-4-6-20260320"
            case .google: return "gemini-2.5-flash"
            }
        }

        var envVar: String {
            switch self {
            case .openai: return "OPENAI_API_KEY"
            case .anthropic: return "ANTHROPIC_API_KEY"
            case .google: return "GOOGLE_API_KEY"
            }
        }
    }

    @State private var vlmMode: VLMMode = .local
    @State private var selectedProvider: RemoteProvider = .openai
    @State private var apiKeyInput: String = ""
    @State private var customModelName: String = ""
    @State private var apiKeyValidating = false
    @State private var apiKeyValid: Bool? = nil
    @State private var remoteConsentGiven = false

    // Focus recording from onboarding
    @State private var firstRecordingTitle: String = ""

    // Clipboard copy feedback
    @State private var pathCopied = false

    // Record button pulse
    @State private var recordPulse = false

    /// Called when onboarding completes (sets hasCompletedOnboarding).
    var onComplete: (() -> Void)?

    private let totalSteps = 8

    // MARK: - Design Tokens

    private let brandGradient = LinearGradient(
        colors: [.orange, Color(red: 0.95, green: 0.4, blue: 0.2)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private let cardBg = Color(nsColor: .controlBackgroundColor)
    private let cardBorder = Color.primary.opacity(0.08)
    private let cardRadius: CGFloat = 14
    private let cardShadow = Color.black.opacity(0.04)
    private let sectionSpacing: CGFloat = 24
    private let cardPadding: CGFloat = 16

    private let heroFont = Font.system(size: 28, weight: .bold, design: .rounded)
    private let sectionFont = Font.system(size: 15, weight: .semibold).leading(.tight)
    private let bodyFont = Font.system(size: 13)
    private let captionFont = Font.system(size: 11)
    private let monoFont = Font.system(size: 12, design: .monospaced)

    private let captionColor = Color.secondary.opacity(0.8)
    private let subtleBg = Color.primary.opacity(0.03)

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            progressBar
                .padding(.top, 20)
                .padding(.horizontal, 40)

            Spacer()

            // Current step content
            stepContent(for: currentStep)
                .padding(.horizontal, 40)

            Spacer()

            // Navigation
            navigationBar
                .padding(.horizontal, 40)
                .padding(.bottom, 28)
        }
        .onAppear {
            resolveExtensionPath()
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(brandGradient)
                        .frame(
                            width: geometry.size.width * CGFloat(currentStep + 1) / CGFloat(totalSteps),
                            height: 4
                        )
                        .animation(.easeOut(duration: 0.4), value: currentStep)
                }
            }
            .frame(height: 4)

            Text("Step \(currentStep + 1) of \(totalSteps)")
                .font(captionFont)
                .foregroundColor(captionColor)
        }
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack {
            if currentStep > 0 {
                Button("Back") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { currentStep -= 1 }
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .font(.system(size: 13))
            }

            Spacer()

            switch currentStep {
            case 0:
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { currentStep += 1 }
                } label: {
                    HStack(spacing: 6) {
                        Text("Get Started")
                            .font(.system(size: 14, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(brandGradient)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)

            case 1, 2, 3:
                Button("Next") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { currentStep += 1 }
                }
                .buttonStyle(.borderedProminent)

            case 4:
                // Permissions — blocked until both granted, with skip option
                VStack(spacing: 4) {
                    Button("Next") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { currentStep += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!appState.accessibilityGranted || !appState.screenRecordingGranted)

                    if !appState.accessibilityGranted || !appState.screenRecordingGranted {
                        Button("Skip for now") {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { currentStep += 1 }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .buttonStyle(.plain)
                    }
                }

            case 5:
                // VLM Setup — blocked until model ready
                VStack(spacing: 2) {
                    Button("Next") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { currentStep += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!appState.vlmAvailable)

                    if !appState.vlmAvailable {
                        Text("Set up an AI model above to continue")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }

            case 6:
                // Browser extension — optional
                HStack(spacing: 12) {
                    if !appState.extensionConnected {
                        Button("Skip") {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { currentStep += 1 }
                        }
                        .foregroundColor(.secondary)
                        .buttonStyle(.plain)
                        .font(.system(size: 13))
                    }

                    Button("Next") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { currentStep += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                }

            case 7:
                // Ready — final step, no Next button
                EmptyView()

            default:
                EmptyView()
            }
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private func stepContent(for step: Int) -> some View {
        switch step {
        case 0: welcomeStep
        case 1: teachByDoingStep
        case 2: whatYoullGetStep
        case 3: reviewCycleStep
        case 4: permissionsStep
        case 5: vlmSetupStep
        case 6: chromeExtensionStep
        case 7: readyStep
        default: EmptyView()
        }
    }

    // MARK: - Screen 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: sectionSpacing) {
            // Hero icon with gradient circle background
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.orange.opacity(0.2), Color(red: 0.95, green: 0.4, blue: 0.2).opacity(0.06)],
                            center: .center,
                            startRadius: 5,
                            endRadius: 50
                        )
                    )
                    .frame(width: 96, height: 96)
                    .shadow(color: Color.orange.opacity(0.15), radius: 20, y: 4)

                Image(systemName: "binoculars.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(brandGradient)
            }

            VStack(spacing: 10) {
                Text("AgentHandover")
                    .font(heroFont)

                Text("Turns your everyday work into step-by-step procedures\nthat AI agents can follow.")
                    .font(bodyFont)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 400)
            }

            // Three feature cards with borders and shadows
            HStack(spacing: 12) {
                featureCard(icon: "eye.fill", iconColor: .blue, label: "Watches silently")
                featureCard(icon: "brain.head.profile.fill", iconColor: .purple, label: "Learns patterns")
                featureCard(icon: "doc.text.fill", iconColor: .orange, label: "Writes procedures")
            }
            .padding(.top, 4)

            // Privacy note
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 12))
                Text("100% local \u{00B7} Nothing leaves your Mac")
                    .font(captionFont)
                    .foregroundColor(captionColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.green.opacity(0.04))
            )
        }
    }

    private func featureCard(icon: String, iconColor: Color, label: String) -> some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(iconColor.opacity(0.08))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(iconColor)
            }
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: cardRadius)
                .fill(cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cardRadius)
                .stroke(cardBorder, lineWidth: 1)
        )
        .shadow(color: cardShadow, radius: 8, y: 2)
    }

    // MARK: - Screen 2: Teach by Doing

    private var teachByDoingStep: some View {
        VStack(spacing: sectionSpacing) {
            Text("Two ways to teach your agent")
                .font(heroFont)

            HStack(spacing: 14) {
                // Focus Recording — highlighted
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.1))
                                .frame(width: 40, height: 40)
                            Image(systemName: "record.circle")
                                .font(.system(size: 20))
                                .foregroundColor(.red)
                        }
                        Spacer()
                        Text("Start here")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.orange.opacity(0.1))
                            )
                            .foregroundColor(.orange)
                    }

                    Text("Record a specific task")
                        .font(sectionFont)
                        .tracking(0.3)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "1.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("Click Record")
                                .font(bodyFont)
                                .foregroundColor(.secondary)
                        }
                        HStack(spacing: 6) {
                            Image(systemName: "2.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("Do the task as usual")
                                .font(bodyFont)
                                .foregroundColor(.secondary)
                        }
                        HStack(spacing: 6) {
                            Image(systemName: "3.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("Stop \u{2014} procedure in ~60s")
                                .font(bodyFont)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: cardRadius)
                        .fill(cardBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cardRadius)
                        .stroke(Color.orange.opacity(0.4), lineWidth: 1.5)
                )
                .shadow(color: Color.orange.opacity(0.06), radius: 12, y: 3)

                // Passive Learning — subtle
                VStack(alignment: .leading, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 40, height: 40)
                        Image(systemName: "eye")
                            .font(.system(size: 20))
                            .foregroundColor(.blue)
                    }

                    Text("Learns automatically")
                        .font(sectionFont)
                        .tracking(0.3)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Watches for repeated patterns")
                            .font(bodyFont)
                            .foregroundColor(.secondary)
                        Text("Gets smarter over days")
                            .font(bodyFont)
                            .foregroundColor(.secondary)
                        Text("No effort required")
                            .font(bodyFont)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: cardRadius)
                        .fill(cardBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cardRadius)
                        .stroke(cardBorder, lineWidth: 1)
                )
                .shadow(color: cardShadow, radius: 8, y: 2)
            }

            Text("We recommend starting with Focus Recording \u{2014} you'll see your first procedure in under a minute.")
                .font(captionFont)
                .foregroundColor(captionColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
    }

    // MARK: - Screen 3: What You'll Get

    private var whatYoullGetStep: some View {
        VStack(spacing: sectionSpacing) {
            Text("Here's what a learned procedure looks like")
                .font(heroFont)
                .multilineTextAlignment(.center)

            // Mock procedure card — premium document style
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor.opacity(0.1))
                            .frame(width: 32, height: 32)
                        Image(systemName: "list.clipboard")
                            .font(.system(size: 15))
                            .foregroundColor(.accentColor)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("File Expense Report")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Expensify workflow \u{00B7} 5 steps")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.bottom, 14)

                // Thin divider
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 1)
                    .padding(.bottom, 14)

                // Strategy section
                procedureSectionLabel("Strategy", icon: "lightbulb.fill", color: .yellow)
                Text("Open Expensify, upload receipt, categorize, submit for approval")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineSpacing(3)
                    .padding(.bottom, 14)

                // Steps section
                procedureSectionLabel("Steps", icon: "list.number", color: .blue)
                VStack(alignment: .leading, spacing: 6) {
                    procedureStep(1, "Open Expensify in Chrome")
                    procedureStep(2, "Click \"New Expense\"")
                    procedureStep(3, "Upload receipt photo")
                    procedureStep(4, "Select category: Travel")
                    procedureStep(5, "Submit for manager approval")
                }
                .padding(.bottom, 14)

                // Verification & Guardrails side by side
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.green)
                            Text("Verification")
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(0.3)
                        }
                        Text("\"Expense submitted\" confirmation")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 5) {
                            Image(systemName: "shield.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.orange)
                            Text("Guardrails")
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(0.3)
                        }
                        Text("Never submit without receipt")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("Max $500 without pre-approval")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.bottom, 12)

                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 1)
                    .padding(.bottom, 10)

                // Footer
                HStack(spacing: 14) {
                    HStack(spacing: 5) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text("~5 min")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 5) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                        Text("Confidence: 92%")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: cardRadius)
                    .fill(cardBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cardRadius)
                    .stroke(cardBorder, lineWidth: 1)
            )
            .shadow(color: cardShadow, radius: 12, y: 3)

            Text("Exported as a SKILL.md that Claude Code, OpenClaw, and other agents can execute.")
                .font(captionFont)
                .foregroundColor(captionColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
    }

    private func procedureSectionLabel(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(color)
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primary.opacity(0.6))
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .padding(.bottom, 6)
    }

    private func procedureStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.accentColor)
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(Color.accentColor.opacity(0.08))
                )
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Screen 4: The Review Cycle

    private var reviewCycleStep: some View {
        VStack(spacing: sectionSpacing) {
            Text("You stay in control")
                .font(heroFont)

            // Visual pipeline with styled circles and connecting line
            ZStack {
                // Connecting line behind the nodes
                GeometryReader { geometry in
                    let nodeWidth: CGFloat = 60
                    let totalNodes: CGFloat = 4
                    let spacing = (geometry.size.width - nodeWidth * totalNodes) / (totalNodes - 1)
                    let centerY: CGFloat = 24

                    Path { path in
                        for i in 0..<3 {
                            let startX = nodeWidth * CGFloat(i + 1) + spacing * CGFloat(i)
                            let endX = nodeWidth * CGFloat(i + 1) + spacing * CGFloat(i + 1)
                            path.move(to: CGPoint(x: startX, y: centerY))
                            path.addLine(to: CGPoint(x: endX, y: centerY))
                        }
                    }
                    .stroke(Color.secondary.opacity(0.15), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                }
                .frame(height: 48)

                HStack(spacing: 0) {
                    pipelineNode(icon: "camera.fill", label: "Record /\nObserve", color: .blue)
                    Spacer()
                    pipelineNode(icon: "brain.head.profile", label: "AI\nAnalyzes", color: .purple)
                    Spacer()
                    pipelineNode(icon: "person.fill", label: "You\nReview", color: .orange, highlighted: true)
                    Spacer()
                    pipelineNode(icon: "cpu", label: "Agent\nReady", color: .green)
                }
            }
            .padding(.vertical, 8)

            Text("Every procedure goes through your review before any agent can use it.\nNothing reaches agents without your approval.")
                .font(bodyFont)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 440)

            // Highlight card
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.orange.opacity(0.1))
                        .frame(width: 40, height: 40)
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.orange)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Review from your menu bar")
                        .font(.system(size: 13, weight: .medium))
                    Text("Approve with one tap, or edit to refine.")
                        .font(bodyFont)
                        .foregroundColor(.secondary)
                }
            }
            .padding(cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cardRadius)
                    .fill(cardBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cardRadius)
                    .stroke(Color.orange.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: Color.orange.opacity(0.05), radius: 10, y: 2)
        }
    }

    private func pipelineNode(icon: String, label: String, color: Color, highlighted: Bool = false) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(
                        highlighted
                            ? color.opacity(0.15)
                            : color.opacity(0.08)
                    )
                    .frame(width: 48, height: 48)
                    .shadow(color: highlighted ? color.opacity(0.2) : .clear, radius: 8, y: 2)

                if highlighted {
                    Circle()
                        .stroke(color.opacity(0.4), lineWidth: 2)
                        .frame(width: 48, height: 48)
                }

                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(color)
            }

            Text(label)
                .font(captionFont)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 60)
        }
    }

    // MARK: - Screen 5: Permissions

    private var permissionsStep: some View {
        VStack(spacing: sectionSpacing) {
            Text("Two permissions to enable")
                .font(heroFont)

            VStack(spacing: 12) {
                // Accessibility card
                permissionCard(
                    icon: "hand.raised.circle.fill",
                    title: "Accessibility",
                    description: "Read window titles and UI elements",
                    granted: appState.accessibilityGranted,
                    action: {
                        PermissionChecker.requestAccessibility()
                    },
                    actionLabel: "Grant Access"
                )

                // Screen Recording card
                permissionCard(
                    icon: "rectangle.dashed.badge.record",
                    title: "Screen Recording",
                    description: "Capture screenshots for AI analysis",
                    granted: appState.screenRecordingGranted,
                    action: {
                        PermissionChecker.openScreenRecordingSettings()
                    },
                    actionLabel: "Open Settings"
                )
            }

            HStack(spacing: 8) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.blue)
                Text("AgentHandover reads your screen. It never types, clicks, or takes actions.")
                    .font(captionFont)
                    .foregroundColor(captionColor)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 440)
        }
    }

    private func permissionCard(
        icon: String,
        title: String,
        description: String,
        granted: Bool,
        action: @escaping () -> Void,
        actionLabel: String
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(granted ? Color.green.opacity(0.08) : Color.accentColor.opacity(0.08))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(granted ? .green : .accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(sectionFont)
                    .tracking(0.3)
                Text(description)
                    .font(bodyFont)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if granted {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Granted")
                        .foregroundColor(.green)
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.green.opacity(0.08))
                )
            } else {
                Button(actionLabel) {
                    action()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(cardPadding)
        .background(
            RoundedRectangle(cornerRadius: cardRadius)
                .fill(cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cardRadius)
                .stroke(
                    granted ? Color.green.opacity(0.25) : cardBorder,
                    lineWidth: 1
                )
        )
        .shadow(color: cardShadow, radius: 8, y: 2)
    }

    // MARK: - Screen 6: VLM Setup (Required)

    private var vlmSetupStep: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.purple.opacity(0.15), Color.orange.opacity(0.06)],
                            center: .center,
                            startRadius: 5,
                            endRadius: 44
                        )
                    )
                    .frame(width: 80, height: 80)
                    .shadow(color: Color.purple.opacity(0.1), radius: 16, y: 3)

                Image(systemName: "brain.head.profile")
                    .font(.system(size: 34))
                    .foregroundColor(.orange)
            }

            Text("Set up your local AI")
                .font(heroFont)

            Text("A small AI model runs on your Mac to understand what's on your screen.")
                .font(bodyFont)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 440)

            if appState.vlmAvailable {
                PermissionStatusBadge(
                    granted: true,
                    grantedLabel: "AI Model Ready",
                    deniedLabel: ""
                )
            } else {
                // Local / Cloud toggle
                Picker("Mode", selection: $vlmMode) {
                    ForEach(VLMMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)

                if vlmMode == .cloud {
                    cloudVLMContent
                } else {
                    localVLMContent
                }
            }
        }
    }

    // MARK: - Local VLM Content

    private var localVLMContent: some View {
        VStack(spacing: 10) {
            let ollamaInstalled = isOllamaInstalled()

            if ollamaInstalled {
                PermissionStatusBadge(
                    granted: true,
                    grantedLabel: "Ollama Installed",
                    deniedLabel: ""
                )

                if vlmPullInProgress {
                    VStack(spacing: 6) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                        Text("Pulling models...")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        if !vlmPullOutput.isEmpty {
                            Text(vlmPullOutput)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.accentColor)
                                .font(.system(size: 14))
                            Text("~6 GB download \u{00B7} Runs on Apple Silicon")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            modelRow("qwen3.5:2b", "2.7 GB", "Screen annotation \u{2014} reads your screen and describes what you're doing")
                            modelRow("qwen3.5:4b", "3.4 GB", "SOP generation \u{2014} writes step-by-step procedures from observations")
                            modelRow("all-minilm:l6-v2", "45 MB", "Task matching \u{2014} groups similar work together")
                        }

                        Button("Pull All Recommended Models") {
                            pullOllamaModel()
                        }
                        .buttonStyle(.borderedProminent)

                        Text("Or use any Ollama-compatible model \u{2014} edit annotation_model and sop_model in config.toml after setup.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: 380)
                    }
                    .frame(maxWidth: 440)
                }
            } else {
                VStack(spacing: 8) {
                    Text("Ollama not installed")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    Button("Download Ollama") {
                        if let url = URL(string: "https://ollama.com/download/mac") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)

                    Text("Or install via: brew install ollama")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Cloud VLM Content

    private var cloudVLMContent: some View {
        VStack(spacing: 12) {
            // Privacy consent
            if !remoteConsentGiven {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Privacy Notice")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Text("Cloud VLM sends screenshots of your desktop to a third-party API for analysis. Only enable this if you accept this trade-off.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 350)

                    Button("I Understand & Consent") {
                        remoteConsentGiven = true
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                // Provider picker
                Picker("Provider", selection: $selectedProvider) {
                    ForEach(RemoteProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 280)
                .onChange(of: selectedProvider) { _ in
                    customModelName = ""
                }

                // Model selection
                HStack(spacing: 8) {
                    Text("Model:")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    TextField("Model name", text: $customModelName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 220)
                }

                Text("Default: \(selectedProvider.defaultModel)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                // API Key input
                SecureField("API Key", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)

                Text("Stored securely in macOS Keychain")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                // Save & Test button
                HStack(spacing: 8) {
                    Button("Save Configuration") {
                        saveCloudVLMConfig()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKeyInput.count < 10)

                    if apiKeyValidating {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let valid = apiKeyValid {
                    PermissionStatusBadge(
                        granted: valid,
                        grantedLabel: "Configuration Saved",
                        deniedLabel: "Failed to save"
                    )
                }
            }
        }
    }

    // MARK: - Cloud VLM Config Save

    private func saveCloudVLMConfig() {
        apiKeyValidating = true

        DispatchQueue.global(qos: .userInitiated).async {
            // Store key in Keychain
            let stored = KeychainHelper.store(
                key: "agenthandover-\(selectedProvider.rawValue)-key",
                value: apiKeyInput
            )

            // Write config.toml update
            if stored {
                writeRemoteVLMConfig(
                    provider: selectedProvider.rawValue,
                    model: customModelName.isEmpty ? selectedProvider.defaultModel : customModelName,
                    apiKeyEnv: selectedProvider.envVar
                )
            }

            DispatchQueue.main.async {
                apiKeyValidating = false
                apiKeyValid = stored
                if stored && !apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    appState.vlmAvailable = true
                }
            }
        }
    }

    private func writeRemoteVLMConfig(provider: String, model: String, apiKeyEnv: String) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configDir = home
            .appendingPathComponent("Library/Application Support/agenthandover")
        let configPath = configDir.appendingPathComponent("config.toml")

        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        // Read existing config or start fresh
        var content = (try? String(contentsOf: configPath, encoding: .utf8)) ?? ""

        // Strip any existing remote-mode keys from [vlm] section to avoid
        // duplicates on repeated saves.  Then insert the new values.
        let remoteKeys = ["mode", "provider", "model", "api_key_env"]
        for key in remoteKeys {
            // Match lines like: mode = "remote"  or  provider = "openai"
            // (with optional leading whitespace and any quoted value)
            let pattern = "(?m)^[ \\t]*\(key)[ \\t]*=[ \\t]*\"[^\"]*\"[ \\t]*\\n?"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(content.startIndex..., in: content)
                content = regex.stringByReplacingMatches(
                    in: content, range: range, withTemplate: ""
                )
            }
        }

        let newFields = "mode = \"remote\"\nprovider = \"\(provider)\"\nmodel = \"\(model)\"\napi_key_env = \"\(apiKeyEnv)\"\n"

        if content.contains("[vlm]") {
            if let vlmRange = content.range(of: "[vlm]") {
                let afterVlm = content[vlmRange.upperBound...]
                if let nextSection = afterVlm.range(of: "\n[") {
                    content.insert(contentsOf: "\n" + newFields, at: nextSection.lowerBound)
                } else {
                    content += "\n" + newFields
                }
            }
        } else {
            content += "\n[vlm]\n" + newFields
        }

        try? content.write(to: configPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Screen 7: Browser Extension (Optional, Load Unpacked)

    private var chromeExtensionStep: some View {
        VStack(spacing: sectionSpacing) {
            HStack(spacing: 10) {
                Text("Supercharge browser workflows")
                    .font(heroFont)

                Text("Optional")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.1))
                    )
                    .foregroundColor(.secondary)
            }

            // What the extension does
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.blue.opacity(0.08))
                        .frame(width: 40, height: 40)
                    Image(systemName: "globe.badge.chevron.backward")
                        .font(.system(size: 18))
                        .foregroundColor(.blue)
                }

                Text("Adds CSS selectors, form field names, and page structure to your procedures \u{2014} making browser automation more precise.")
                    .font(bodyFont)
                    .foregroundColor(.secondary)
                    .lineSpacing(4)
            }
            .padding(cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cardRadius)
                    .fill(cardBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cardRadius)
                    .stroke(cardBorder, lineWidth: 1)
            )
            .shadow(color: cardShadow, radius: 8, y: 2)

            // Connection status and install instructions
            if appState.extensionConnected {
                // Already connected
                extensionConnectedView
            } else if !extensionPath.isEmpty {
                // Extension found — show Load Unpacked instructions
                extensionReadyView
            } else {
                // Extension not found — coming soon
                extensionNotFoundView
            }

            // Supported browsers note
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.6))
                Text("Works with Chrome, Brave, and Edge")
                    .font(captionFont)
                    .foregroundColor(captionColor)
            }
        }
    }

    // Extension already connected
    private var extensionConnectedView: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 56, height: 56)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.green)
            }

            Text("Browser extension connected!")
                .font(sectionFont)
                .tracking(0.3)

            Text("You're getting enhanced browser context in your procedures.")
                .font(bodyFont)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: cardRadius)
                .fill(Color.green.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cardRadius)
                .stroke(Color.green.opacity(0.2), lineWidth: 1)
        )
    }

    // Extension files found — Load Unpacked flow
    private var extensionReadyView: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Status header
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.green)
                Text("Extension ready to install")
                    .font(sectionFont)
                    .tracking(0.3)
            }

            // Three numbered steps
            VStack(alignment: .leading, spacing: 10) {
                // Step 1: Open extensions page
                HStack(alignment: .top, spacing: 12) {
                    stepCircle(number: 1)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Open your browser's extension page")
                            .font(.system(size: 13, weight: .medium))
                        Button {
                            openBrowserExtensionsPage()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 11))
                                Text("Open Extensions Page")
                                    .font(.system(size: 12, weight: .medium))
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                // Step 2: Developer Mode
                HStack(alignment: .top, spacing: 12) {
                    stepCircle(number: 2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Enable Developer Mode")
                            .font(.system(size: 13, weight: .medium))
                        Text("Toggle in the top-right corner of the extensions page")
                            .font(captionFont)
                            .foregroundColor(.secondary)
                    }
                }

                // Step 3: Load unpacked
                HStack(alignment: .top, spacing: 12) {
                    stepCircle(number: 3)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Click \"Load unpacked\" and select this folder:")
                            .font(.system(size: 13, weight: .medium))

                        // Path display with copy button
                        HStack(spacing: 0) {
                            Text(extensionPath)
                                .font(monoFont)
                                .foregroundColor(.primary.opacity(0.8))
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer(minLength: 8)

                            Button {
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString(extensionPath, forType: .string)
                                withAnimation { pathCopied = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                    withAnimation { pathCopied = false }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: pathCopied ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 10))
                                    Text(pathCopied ? "Copied" : "Copy")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(pathCopied ? .green : .accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(subtleBg)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                    }
                }
            }

            if let error = chromeOpenError {
                Text(error)
                    .font(captionFont)
                    .foregroundColor(.red)
            }
        }
        .padding(cardPadding)
        .background(
            RoundedRectangle(cornerRadius: cardRadius)
                .fill(cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cardRadius)
                .stroke(Color.green.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: cardShadow, radius: 8, y: 2)
    }

    // Extension not found — coming soon
    private var extensionNotFoundView: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.06))
                    .frame(width: 40, height: 40)
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
            }

            Text("Extension will be available on the Chrome Web Store soon.")
                .font(bodyFont)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Text("For now, you can skip this step \u{2014} AgentHandover works great without it.")
                .font(captionFont)
                .foregroundColor(captionColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: cardRadius)
                .fill(subtleBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cardRadius)
                .stroke(cardBorder, lineWidth: 1)
        )
    }

    private func stepCircle(number: Int) -> some View {
        Text("\(number)")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .frame(width: 24, height: 24)
            .background(
                Circle()
                    .fill(brandGradient)
            )
    }

    // MARK: - Screen 8: Ready — First Recording

    private var readyStep: some View {
        VStack(spacing: sectionSpacing) {
            Text("You're ready!")
                .font(heroFont)

            // Summary checks
            HStack(spacing: 16) {
                readinessChip(
                    icon: "checkmark.shield.fill",
                    label: "Permissions",
                    ok: appState.accessibilityGranted && appState.screenRecordingGranted
                )
                readinessChip(
                    icon: "brain.head.profile",
                    label: "AI Model",
                    ok: appState.vlmAvailable
                )
                readinessChip(
                    icon: "globe",
                    label: "Extension",
                    ok: appState.extensionConnected,
                    optional: true
                )
            }

            // Main recording card — the CTA of the onboarding
            VStack(spacing: 16) {
                Text("Record your first workflow")
                    .font(.system(size: 17, weight: .semibold))

                Text("What's something you do regularly?")
                    .font(bodyFont)
                    .foregroundColor(.secondary)

                TextField("e.g. File expense report, Check inbox, Deploy code...", text: $firstRecordingTitle)
                    .textFieldStyle(.roundedBorder)
                    .font(bodyFont)
                    .frame(maxWidth: 340)

                Button {
                    startServicesAndRecord()
                } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.3))
                                .frame(width: 20, height: 20)
                                .scaleEffect(recordPulse ? 1.3 : 1.0)
                                .opacity(recordPulse ? 0.0 : 0.6)

                            Circle()
                                .fill(Color.white)
                                .frame(width: 10, height: 10)
                        }
                        Text("Start Recording")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.red)
                    )
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .disabled(
                    firstRecordingTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !appState.accessibilityGranted
                    || !appState.vlmAvailable
                )
                .opacity(
                    (firstRecordingTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !appState.accessibilityGranted
                    || !appState.vlmAvailable) ? 0.5 : 1.0
                )
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                        recordPulse = true
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(cardBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.red.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: Color.red.opacity(0.06), radius: 16, y: 4)

            // Secondary: Just start observing
            Button("Or start observing \u{2192}") {
                startServicesOnly()
            }
            .foregroundColor(.accentColor)
            .buttonStyle(.plain)
            .font(bodyFont)

            if serviceStartFailed {
                Text("Services may not have started. Check agenthandover status in Terminal.")
                    .font(captionFont)
                    .foregroundColor(.red)
            } else if !appState.accessibilityGranted {
                Text("Accessibility permission is required (go back to step 5)")
                    .font(captionFont)
                    .foregroundColor(.orange)
            } else if !appState.vlmAvailable {
                Text("An AI model must be configured (go back to step 6)")
                    .font(captionFont)
                    .foregroundColor(.orange)
            }

            HStack(spacing: 4) {
                Text("AgentHandover lives in your menu bar")
                    .font(captionFont)
                    .foregroundColor(captionColor)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10))
                    .foregroundColor(captionColor)
                Text("\u{2014} that's your control center")
                    .font(captionFont)
                    .foregroundColor(captionColor)
            }
        }
    }

    private func readinessChip(icon: String, label: String, ok: Bool, optional: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : (optional ? "minus.circle" : "xmark.circle.fill"))
                .font(.system(size: 14))
                .foregroundColor(ok ? .green : (optional ? .secondary.opacity(0.5) : .orange))
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(ok ? .primary : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(ok ? Color.green.opacity(0.06) : subtleBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ok ? Color.green.opacity(0.15) : cardBorder, lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func startServicesOnly() {
        let ok = ServiceController.startAll()
        if ok {
            onComplete?()
            NSApplication.shared.keyWindow?.close()
        } else {
            serviceStartFailed = true
        }
    }

    private func startServicesAndRecord() {
        let ok = ServiceController.startAll()
        if ok {
            // Write focus-session.json to trigger a recording
            let sessionId = UUID().uuidString
            let signal: [String: Any] = [
                "session_id": sessionId,
                "title": firstRecordingTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                "started_at": ISO8601DateFormatter().string(from: Date()),
                "status": "recording",
            ]
            writeFocusSignalFile(signal)
            onComplete?()
            NSApplication.shared.keyWindow?.close()
        } else {
            serviceStartFailed = true
        }
    }

    private func writeFocusSignalFile(_ signal: [String: Any]) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent("Library/Application Support/agenthandover")
        let target = dir.appendingPathComponent("focus-session.json")
        let tmp = dir.appendingPathComponent(".focus-session.json.tmp")

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: signal, options: .prettyPrinted)
            try data.write(to: tmp, options: .atomic)
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.moveItem(at: tmp, to: target)
        } catch {
            // Silently fail — the recording won't start but services are already running.
            // The user can start a recording from the menu bar.
        }
    }

    // MARK: - Helpers

    private func resolveExtensionPath() {
        // 1. Check installed paths (pkg + Homebrew opt symlinks)
        let installedPaths: [String] = [
            "/usr/local/lib/agenthandover/extension",
            "/usr/local/opt/agenthandover/libexec/extension",
            "/opt/homebrew/opt/agenthandover/libexec/extension",
        ]

        for candidate in installedPaths {
            let manifestPath = (candidate as NSString).appendingPathComponent("manifest.json")
            if FileManager.default.fileExists(atPath: manifestPath) {
                extensionPath = candidate
                return
            }
        }

        // 2. Resolve Homebrew Cellar path by following the CLI binary symlink.
        //    This covers cases where the opt symlink is broken or not yet created.
        //    Pattern: /usr/local/bin/agenthandover -> .../Cellar/agenthandover/HEAD-xxx/bin/agenthandover
        //             -> .../Cellar/agenthandover/HEAD-xxx/libexec/extension/
        let cliBinaryPaths = ["/usr/local/bin/agenthandover", "/opt/homebrew/bin/agenthandover"]
        for binaryPath in cliBinaryPaths {
            let url = URL(fileURLWithPath: binaryPath)
            let resolved = url.resolvingSymlinksInPath().path
                .components(separatedBy: "/")
            if !resolved.isEmpty {
                if let binIdx = resolved.lastIndex(of: "bin") {
                    let prefix = resolved[..<binIdx].joined(separator: "/")
                    let cellarExt = prefix + "/libexec/extension"
                    if FileManager.default.fileExists(atPath: cellarExt + "/manifest.json") {
                        extensionPath = cellarExt
                        return
                    }
                }
            }
        }

        // 3. Check for dev/source build by walking ancestors from the app binary
        //    AND from the CLI binary to find extension/dist relative to repo root.
        var searchRoots: [URL] = []

        // From the running app binary
        if let execPath = Bundle.main.executableURL {
            searchRoots.append(execPath.deletingLastPathComponent())
        }

        // From the CLI binary
        if let cliPath = findCLIBinary() {
            searchRoots.append(URL(fileURLWithPath: cliPath).deletingLastPathComponent())
        }

        // Also check common source build locations
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let commonPaths = [
            "\(home)/Desktop/openmimic/extension/dist",
            "\(home)/Projects/AgentHandover/extension/dist",
            "\(home)/Developer/AgentHandover/extension/dist",
        ]
        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path + "/manifest.json") {
                extensionPath = path
                return
            }
        }

        for root in searchRoots {
            var dir = root
            for _ in 0..<8 {
                let candidate = dir.appendingPathComponent("extension/dist").path
                if FileManager.default.fileExists(atPath: candidate + "/manifest.json") {
                    extensionPath = candidate
                    return
                }
                dir = dir.deletingLastPathComponent()
            }
        }
    }

    /// Find the agenthandover CLI binary on the system.
    private func findCLIBinary() -> String? {
        let knownPaths = [
            "/usr/local/bin/agenthandover",
            "/opt/homebrew/bin/agenthandover",
        ]
        for path in knownPaths {
            if FileManager.default.fileExists(atPath: path) {
                // Resolve symlinks to find the real location
                return URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            }
        }
        return nil
    }

    private func openBrowserExtensionsPage() {
        chromeOpenError = nil

        // Try Chrome first, then Brave, then Edge
        let browsers: [(name: String, url: String)] = [
            ("Google Chrome", "chrome://extensions"),
            ("Brave Browser", "brave://extensions"),
            ("Microsoft Edge", "edge://extensions"),
        ]

        for browser in browsers {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", browser.name, browser.url]
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    return
                }
            } catch {
                continue
            }
        }

        chromeOpenError = "Could not open a supported browser. Open Chrome, Brave, or Edge extensions page manually."
    }

    private func copyPathAndOpenChrome() {
        chromeOpenError = nil

        // Copy extension path to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let copied = pasteboard.setString(extensionPath, forType: .string)
        if !copied {
            chromeOpenError = "Failed to copy path to clipboard."
            return
        }

        // Open chrome://extensions via /usr/bin/open -a "Google Chrome"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Google Chrome", "chrome://extensions"]
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                chromeOpenError = "Could not open Chrome. Is Google Chrome installed?"
            }
        } catch {
            chromeOpenError = "Could not open Chrome: \(error.localizedDescription)"
        }
    }

    private func isOllamaInstalled() -> Bool {
        let paths = [
            "/usr/local/bin/ollama",
            "/opt/homebrew/bin/ollama",
        ]
        return paths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    private func findOllamaPath() -> String? {
        let paths = [
            "/usr/local/bin/ollama",
            "/opt/homebrew/bin/ollama",
        ]
        return paths.first { FileManager.default.fileExists(atPath: $0) }
    }

    private func modelRow(_ name: String, _ size: String, _ description: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\u{2022}")
                .foregroundColor(.orange)
                .font(.system(size: 12))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                    Text(size)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func pullOllamaModel() {
        guard let ollamaPath = findOllamaPath() else { return }

        vlmPullInProgress = true
        vlmPullOutput = "Starting download..."

        let models = [
            ("qwen3.5:2b", "scene annotation"),
            ("qwen3.5:4b", "SOP generation"),
            ("all-minilm:l6-v2", "embeddings"),
        ]

        DispatchQueue.global(qos: .userInitiated).async {
            for (index, (model, purpose)) in models.enumerated() {
                DispatchQueue.main.async {
                    vlmPullOutput = "[\(index + 1)/\(models.count)] Pulling \(model) (\(purpose))..."
                }

                let process = Process()
                process.executableURL = URL(fileURLWithPath: ollamaPath)
                process.arguments = ["pull", model]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()

                    // Read output asynchronously
                    pipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                            let lastLine = output.components(separatedBy: "\n")
                                .filter { !$0.isEmpty }
                                .last ?? ""
                            DispatchQueue.main.async {
                                vlmPullOutput = "[\(index + 1)/\(models.count)] \(model): \(String(lastLine.prefix(60)))"
                            }
                        }
                    }

                    process.waitUntilExit()
                    pipe.fileHandleForReading.readabilityHandler = nil

                    if process.terminationStatus != 0 {
                        DispatchQueue.main.async {
                            vlmPullInProgress = false
                            vlmPullOutput = "Failed to pull \(model). Make sure Ollama is running."
                        }
                        return
                    }
                } catch {
                    DispatchQueue.main.async {
                        vlmPullInProgress = false
                        vlmPullOutput = "Failed to run ollama: \(error.localizedDescription)"
                    }
                    return
                }
            }

            DispatchQueue.main.async {
                vlmPullInProgress = false
                vlmPullOutput = "All models downloaded successfully!"
                appState.vlmAvailable = true
            }
        }
    }
}

// MARK: - Models

enum OnboardingAction {
    case none
    case accessibility
    case screenRecording
    case chromeExtension
    case vlmSetup
}

// MARK: - Subviews

/// Simple macOS Keychain wrapper for storing/retrieving API keys.
struct KeychainHelper {
    static func store(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.agenthandover.app",
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.agenthandover.app",
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func retrieve(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.agenthandover.app",
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }
}

struct PermissionStatusBadge: View {
    let granted: Bool
    let grantedLabel: String
    let deniedLabel: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(granted ? .green : .orange)
            Text(granted ? grantedLabel : deniedLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(granted ? .green : .orange)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill((granted ? Color.green : Color.orange).opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke((granted ? Color.green : Color.orange).opacity(0.15), lineWidth: 1)
        )
    }
}
