import SwiftUI

/// Displays discovered SOPs organized by status: drafts needing review,
/// recently discovered, high confidence, and all approved.
struct WorkflowInboxView: View {
    @StateObject private var sopManager = SOPIndexManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Workflows")
                    .font(.title2)
                    .bold()
                Spacer()
                if let index = sopManager.index {
                    Text("\(index.approved_count) approved")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()

            Divider()

            if sopManager.index == nil {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No workflows yet")
                        .foregroundColor(.secondary)
                    Text("OpenMimic will discover workflows as you work.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Drafts needing review
                        if !sopManager.drafts.isEmpty {
                            SOPSection(
                                title: "Needs Review",
                                icon: "doc.badge.clock",
                                color: .orange,
                                sops: sopManager.drafts
                            )
                        }

                        // Recent
                        if !sopManager.recent.isEmpty {
                            SOPSection(
                                title: "Recently Discovered",
                                icon: "sparkles",
                                color: .blue,
                                sops: sopManager.recent
                            )
                        }

                        // High confidence
                        if !sopManager.highConfidence.isEmpty {
                            SOPSection(
                                title: "High Confidence",
                                icon: "checkmark.seal",
                                color: .green,
                                sops: sopManager.highConfidence
                            )
                        }

                        // All approved
                        if !sopManager.approved.isEmpty {
                            SOPSection(
                                title: "All Approved",
                                icon: "checkmark.circle",
                                color: .green,
                                sops: sopManager.approved
                            )
                        }

                        // Failed count
                        if let index = sopManager.index, index.failed_count > 0 {
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.red)
                                Text("\(index.failed_count) failed generation(s)")
                                    .font(.caption)
                                    .foregroundColor(.red)
                                Spacer()
                                Text("Run: openmimic sops failed")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(width: 360, height: 480)
        .onAppear { sopManager.startPolling() }
        .onDisappear { sopManager.stopPolling() }
    }
}

// MARK: - Section

struct SOPSection: View {
    let title: String
    let icon: String
    let color: Color
    let sops: [SOPEntry]

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(color)
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("(\(sops.count))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal)

            if isExpanded {
                ForEach(sops) { sop in
                    SOPRow(sop: sop)
                }
            }
        }
    }
}

// MARK: - Row

struct SOPRow: View {
    let sop: SOPEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(sop.title)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    StatusBadge(status: sop.status)
                    Text(sop.source)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if sop.confidence > 0 {
                        Text(String(format: "%.0f%%", sop.confidence * 100))
                            .font(.caption2)
                            .foregroundColor(sop.confidence >= 0.8 ? .green : .orange)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(6)
        .padding(.horizontal, 8)
    }
}

// MARK: - Badge

struct StatusBadge: View {
    let status: String

    var body: some View {
        Text(status.capitalized)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor.opacity(0.15))
            .foregroundColor(backgroundColor)
            .cornerRadius(4)
    }

    private var backgroundColor: Color {
        switch status {
        case "approved": return .green
        case "draft": return .orange
        case "rejected": return .red
        default: return .gray
        }
    }
}
