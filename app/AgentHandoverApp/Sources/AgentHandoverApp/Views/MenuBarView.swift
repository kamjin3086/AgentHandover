import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var delegate: AppDelegate
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.openWindow) private var openWindow

    // Focus recording state
    @State private var isRecording = false
    @State private var focusSessionTitle: String = ""
    @State private var focusSessionId: UUID?
    @State private var recordingStartTime: Date?
    @State private var showTitlePrompt = false
    @State private var elapsedTimer: Timer?
    @State private var elapsedSeconds: Int = 0
    @State private var showMoreActions = false

    var body: some View {
        VStack(spacing: 0) {
            // Status + brand
            statusHeader

            // Main content area
            VStack(spacing: 12) {
                // Today's progress card
                todayCard

                // Attention items (questions, drafts)
                if hasAttentionItems {
                    attentionSection
                }

                // Primary action: Record
                recordSection

                // Quick links grid
                quickLinksGrid

                // Footer: services + quit
                footerSection
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(width: 320)
        .onChange(of: delegate.pendingOnboarding) { pending in
            if pending {
                delegate.pendingOnboarding = false
                openWindow(id: "onboarding")
            }
        }
        .onChange(of: appState.focusQuestionsAvailable) { available in
            if available {
                openWindow(id: "focus-qa")
            }
        }
        .onAppear {
            if !hasCompletedOnboarding && delegate.pendingOnboarding {
                delegate.pendingOnboarding = false
                openWindow(id: "onboarding")
            }
            syncFocusState()
        }
        .onDisappear {
            elapsedTimer?.invalidate()
            elapsedTimer = nil
        }
    }

    // MARK: - Status Header

    private var statusHeader: some View {
        HStack(spacing: 10) {
            // Animated status indicator
            ZStack {
                Circle()
                    .fill(appState.health.color.opacity(0.2))
                    .frame(width: 32, height: 32)
                Circle()
                    .fill(appState.health.color)
                    .frame(width: 10, height: 10)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(statusTitle)
                    .font(.system(size: 13, weight: .semibold))
                Text(statusSubtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Setup needed indicator
            if !hasCompletedOnboarding || !appState.accessibilityGranted {
                Button(action: { openWindow(id: "onboarding") }) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.orange)
                }
                .buttonStyle(.plain)
                .help("Setup needed")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.primary.opacity(0.03))
    }

    private var statusTitle: String {
        if isRecording { return "Recording..." }
        if appState.userStopped { return "Paused" }
        switch appState.health {
        case .healthy: return "Observing"
        case .warning: return "Observing"
        case .down: return "Offline"
        case .stopped: return "Stopped"
        }
    }

    private var statusSubtitle: String {
        if isRecording {
            return "\(focusSessionTitle) · \(formattedElapsed)"
        }
        if appState.userStopped { return "Tap Start to resume learning" }
        if !appState.daemonRunning && !appState.workerRunning {
            return "Services not running"
        }
        if appState.eventsToday > 0 {
            return "Learning from your work"
        }
        return "Waiting for activity"
    }

    // MARK: - Today Card

    private var todayCard: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Today")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
            }

            HStack(spacing: 16) {
                TodayStat(
                    icon: "camera.viewfinder",
                    value: "\(appState.eventsToday)",
                    label: "Captured",
                    color: .blue
                )
                TodayStat(
                    icon: "doc.text",
                    value: "\(appState.sopsGenerated)",
                    label: "Learned",
                    color: .purple
                )
                if appState.sopAgentReadyCount > 0 {
                    TodayStat(
                        icon: "checkmark.shield",
                        value: "\(appState.sopAgentReadyCount)",
                        label: "Ready",
                        color: .green
                    )
                } else {
                    TodayStat(
                        icon: "hourglass",
                        value: "\(appState.vlmQueuePending)",
                        label: "Processing",
                        color: .orange
                    )
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.04))
        )
    }

    // MARK: - Attention Section

    private var hasAttentionItems: Bool {
        appState.focusQuestionsAvailable || appState.sopDraftCount > 0
    }

    private var attentionSection: some View {
        VStack(spacing: 6) {
            // Focus Q&A pending
            if appState.focusQuestionsAvailable {
                Button(action: { openWindow(id: "focus-qa") }) {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.orange.opacity(0.15))
                                .frame(width: 28, height: 28)
                            Image(systemName: "questionmark.bubble.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.orange)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Finish your workflow")
                                .font(.system(size: 12, weight: .medium))
                            Text("Answer a few questions to complete")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.orange.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
            }

            // Drafts to review
            if appState.sopDraftCount > 0 {
                Button(action: { openWindow(id: "micro-review") }) {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.blue.opacity(0.15))
                                .frame(width: 28, height: 28)
                            Image(systemName: "checkmark.rectangle.stack.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.blue)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(appState.sopDraftCount) workflow\(appState.sopDraftCount == 1 ? "" : "s") to review")
                                .font(.system(size: 12, weight: .medium))
                            Text("Approve to make agent-ready")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Record Section

    private var recordSection: some View {
        Group {
            if isRecording {
                // Active recording
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .opacity(pulsingOpacity)
                            .animation(
                                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                                value: pulsingOpacity
                            )
                        Text(focusSessionTitle)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Spacer()
                        Text(formattedElapsed)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Button(action: stopFocusSession) {
                        HStack {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 10))
                            Text("Stop Recording")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.12))
                        .foregroundColor(.red)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.red.opacity(0.3), lineWidth: 1)
                )
            } else if showTitlePrompt {
                // Title input
                VStack(alignment: .leading, spacing: 8) {
                    Text("What are you about to do?")
                        .font(.system(size: 12, weight: .medium))

                    TextField("e.g. File expense report", text: $focusSessionTitle)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))

                    HStack {
                        Button("Cancel") {
                            showTitlePrompt = false
                            focusSessionTitle = ""
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                        Spacer()

                        Button(action: { startFocusSession(title: focusSessionTitle) }) {
                            HStack(spacing: 4) {
                                Image(systemName: "record.circle")
                                    .font(.system(size: 10))
                                Text("Start")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                        }
                        .disabled(focusSessionTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .buttonStyle(.plain)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.primary.opacity(0.04))
                )
            } else {
                // Record button
                Button(action: { showTitlePrompt = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "record.circle")
                            .font(.system(size: 15))
                            .foregroundColor(.red)
                        Text("Record a Workflow")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.primary.opacity(0.04))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Quick Links

    private var quickLinksGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
        ], spacing: 8) {
            QuickLink(icon: "tray.full", label: "Workflows", badge: appState.sopTotalCount) {
                openWindow(id: "workflows")
            }
            QuickLink(icon: "calendar.badge.clock", label: "Digest") {
                openWindow(id: "daily-digest")
            }
            QuickLink(icon: "checkmark.rectangle.stack", label: "Review") {
                openWindow(id: "micro-review")
            }
            QuickLink(icon: "gearshape", label: "Settings") {
                openConfig()
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack(spacing: 0) {
            // Service toggle
            if appState.daemonRunning || appState.workerRunning {
                Button(action: {
                    appState.userStopped = true
                    ServiceController.stopAll()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 8))
                        Text("Pause")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: {
                    appState.userStopped = false
                    ServiceController.startAll()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 8))
                        Text("Start")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Service pills (compact)
            HStack(spacing: 4) {
                Circle()
                    .fill(appState.daemonRunning ? Color.green : Color.red.opacity(0.5))
                    .frame(width: 5, height: 5)
                Circle()
                    .fill(appState.workerRunning ? Color.green : Color.red.opacity(0.5))
                    .frame(width: 5, height: 5)
                Circle()
                    .fill(appState.extensionConnected ? Color.green : Color.red.opacity(0.5))
                    .frame(width: 5, height: 5)
            }
            .help("Daemon · Worker · Extension")

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .buttonStyle(.plain)
            .keyboardShortcut("q")
        }
        .padding(.top, 4)
    }

    // MARK: - Focus Recording Helpers

    private var pulsingOpacity: Double {
        isRecording ? 0.3 : 1.0
    }

    private var formattedElapsed: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func syncFocusState() {
        if appState.focusSessionActive {
            isRecording = true
            focusSessionTitle = appState.focusSessionTitle
            focusSessionId = UUID(uuidString: appState.focusSessionId ?? "")
            if let startedStr = appState.focusSessionStartedAt {
                let fmt = ISO8601DateFormatter()
                if let restored = fmt.date(from: startedStr) {
                    recordingStartTime = restored
                    elapsedSeconds = Int(Date().timeIntervalSince(restored))
                    elapsedTimer?.invalidate()
                    elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                        elapsedSeconds += 1
                    }
                }
            }
        }
    }

    private func startFocusSession(title: String) {
        let sessionId = UUID()
        let signal: [String: Any] = [
            "session_id": sessionId.uuidString,
            "title": title,
            "started_at": ISO8601DateFormatter().string(from: Date()),
            "status": "recording"
        ]
        writeFocusSignalFile(signal)

        focusSessionId = sessionId
        focusSessionTitle = title
        recordingStartTime = Date()
        isRecording = true
        showTitlePrompt = false
        elapsedSeconds = 0

        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            elapsedSeconds += 1
        }
    }

    private func stopFocusSession() {
        guard let sessionId = focusSessionId else { return }

        var startedAt: String
        if let startTime = recordingStartTime {
            startedAt = ISO8601DateFormatter().string(from: startTime)
        } else if let existing = readExistingSignalStartedAt() {
            startedAt = existing
        } else {
            startedAt = ISO8601DateFormatter().string(from: Date())
        }

        let signal: [String: Any] = [
            "session_id": sessionId.uuidString,
            "title": focusSessionTitle,
            "started_at": startedAt,
            "status": "stopped"
        ]
        writeFocusSignalFile(signal)

        elapsedTimer?.invalidate()
        elapsedTimer = nil
        isRecording = false
        focusSessionId = nil
        recordingStartTime = nil
        focusSessionTitle = ""
        elapsedSeconds = 0
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
            print("Failed to write focus-session.json: \(error)")
        }
    }

    private func readExistingSignalStartedAt() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let path = home.appendingPathComponent(
            "Library/Application Support/agenthandover/focus-session.json"
        )
        guard let data = try? Data(contentsOf: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let startedAt = json["started_at"] as? String else {
            return nil
        }
        return startedAt
    }

    private func openConfig() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configPath = home
            .appendingPathComponent("Library/Application Support/agenthandover/config.toml")
        NSWorkspace.shared.open(configPath)
    }
}

// MARK: - Components

struct TodayStat: View {
    let icon: String
    let value: String
    let label: String
    var color: Color = .primary

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct QuickLink: View {
    let icon: String
    let label: String
    var badge: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text(label)
                    .font(.system(size: 11))
                if badge > 0 {
                    Spacer()
                    Text("\(badge)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
    }
}
