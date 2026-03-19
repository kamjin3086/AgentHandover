import SwiftUI

/// Displays discovered SOPs in a master-detail layout using NavigationSplitView.
struct WorkflowInboxView: View {
    @StateObject private var sopManager = SOPIndexManager()
    @State private var filter: SOPFilter = .all
    @State private var selectedSOPID: String?

    /// Live lookup: always reflects the latest data from the polling index.
    private var selectedSOP: SOPEntry? {
        guard let id = selectedSOPID else { return nil }
        return sopManager.allSorted.first { $0.id == id }
    }

    enum SOPFilter: String, CaseIterable {
        case all = "All"
        case focus = "Focus"
        case passive = "Discovered"
        case drafts = "Drafts"
        case agentReady = "Agent Ready"
    }

    // Design tokens
    private let cardBg = Color(nsColor: .controlBackgroundColor)
    private let cardBorder = Color.primary.opacity(0.08)
    private let cardRadius: CGFloat = 12

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailPane
        }
        .frame(minWidth: 750, minHeight: 500)
        .onAppear { sopManager.startPolling() }
        .onDisappear { sopManager.stopPolling() }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            Divider()

            if sopManager.index == nil {
                emptyState
            } else if filteredSOPs.isEmpty {
                noMatchState
            } else {
                sopList
            }
        }
        .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 450)
    }

    // MARK: - Detail pane

    private var detailPane: some View {
        Group {
            if let sop = selectedSOP {
                SOPDetailView(sop: sop, sopManager: sopManager)
            } else {
                VStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.primary.opacity(0.03))
                            .frame(width: 64, height: 64)
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary.opacity(0.4))
                    }
                    Text("Select a workflow")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text("Choose a workflow from the sidebar to view its details.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Workflows")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Spacer()
                if let index = sopManager.index {
                    HStack(spacing: 10) {
                        StatPill(
                            count: index.approved_count,
                            label: "approved",
                            color: .green
                        )
                        if index.draft_count > 0 {
                            StatPill(
                                count: index.draft_count,
                                label: "drafts",
                                color: .orange
                            )
                        }
                    }
                }
            }

            // Filter tabs — segmented pill style
            HStack(spacing: 3) {
                ForEach(SOPFilter.allCases, id: \.self) { tab in
                    Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { filter = tab } }) {
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: filter == tab ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                filter == tab
                                    ? RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.accentColor.opacity(0.12))
                                    : nil
                            )
                            .foregroundColor(filter == tab ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.03))
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    // MARK: - List

    private var sopList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filteredSOPs) { sop in
                    SOPRow(sop: sop, isSelected: selectedSOPID == sop.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedSOPID = sop.id
                        }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Empty states

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.primary.opacity(0.03))
                    .frame(width: 56, height: 56)
                Image(systemName: "tray")
                    .font(.system(size: 26))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            Text("No workflows yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.secondary)
            Text("AgentHandover discovers workflows as you work.\nUse Record Workflow for instant capture.")
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var noMatchState: some View {
        VStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 22))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No \(filter.rawValue.lowercased()) workflows")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Filtering

    private var filteredSOPs: [SOPEntry] {
        switch filter {
        case .all: return sopManager.allSorted
        case .focus: return sopManager.allSorted.filter { $0.source == "focus" }
        case .passive: return sopManager.allSorted.filter { $0.source == "passive" }
        case .drafts: return sopManager.drafts
        case .agentReady: return sopManager.allSorted.filter { $0.lifecycleState == "agent_ready" }
        }
    }
}

// MARK: - Row

struct SOPRow: View {
    let sop: SOPEntry
    let isSelected: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Source icon with subtle gradient
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.12)
                            : Color.primary.opacity(0.04)
                    )
                    .frame(width: 38, height: 38)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(
                                isSelected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05),
                                lineWidth: 1
                            )
                    )
                Image(systemName: sop.sourceIcon)
                    .font(.system(size: 15))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }

            VStack(alignment: .leading, spacing: 5) {
                // Title
                Text(sop.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                    .foregroundColor(.primary)

                // Metadata row
                HStack(spacing: 6) {
                    // Lifecycle state pill
                    Text(sop.lifecycleLabel)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(sop.lifecycleColor.opacity(0.1))
                        .foregroundColor(sop.lifecycleColor)
                        .clipShape(Capsule())

                    if sop.confidence > 0 {
                        Text(String(format: "%.0f%%", sop.confidence * 100))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(sop.relativeTime)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(0.08)
                        : (isHovered ? Color.primary.opacity(0.04) : Color.clear)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isSelected ? Color.accentColor.opacity(0.15) : Color.clear,
                    lineWidth: 1
                )
        )
        .padding(.horizontal, 6)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Confidence bar

struct ConfidenceBar: View {
    let value: Double

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(0.08))
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(value >= 0.8 ? 0.4 : 0.2))
                    .frame(width: CGFloat(value) * 30)
            }
        }
        .frame(width: 30, height: 4)
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: String

    var body: some View {
        Text(status.capitalized)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(backgroundColor.opacity(0.1))
            .foregroundColor(backgroundColor)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        .secondary
    }
}

// MARK: - Stat Pill (header)

struct StatPill: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: 10))
        }
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(color.opacity(0.08))
        .clipShape(Capsule())
    }
}
