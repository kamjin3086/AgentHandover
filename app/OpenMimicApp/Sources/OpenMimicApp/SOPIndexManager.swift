import Foundation
import Combine

/// A single SOP entry from the worker's sops-index.json file.
struct SOPEntry: Identifiable, Codable {
    let sop_id: String
    let slug: String
    let title: String
    let source: String
    let status: String
    let confidence: Double
    let created_at: String
    let reviewed_at: String?

    var id: String { sop_id }
}

/// Top-level structure of sops-index.json written by the Python worker.
struct SOPIndex: Codable {
    let updated_at: String
    let sops: [SOPEntry]
    let failed_count: Int
    let draft_count: Int
    let approved_count: Int
}

/// Reads and polls the worker's ``sops-index.json`` so SwiftUI views can
/// display the workflow inbox without direct SQLite access.
@MainActor
final class SOPIndexManager: ObservableObject {
    @Published var index: SOPIndex?

    private var timer: Timer?

    private var indexPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/oc-apprentice/sops-index.json")
    }

    func startPolling(interval: TimeInterval = 5.0) {
        loadIndex()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.loadIndex()
            }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func loadIndex() {
        guard let data = try? Data(contentsOf: indexPath) else { return }
        index = try? JSONDecoder().decode(SOPIndex.self, from: data)
    }

    // MARK: - Filtered views

    var drafts: [SOPEntry] { index?.sops.filter { $0.status == "draft" } ?? [] }
    var approved: [SOPEntry] { index?.sops.filter { $0.status == "approved" } ?? [] }
    var highConfidence: [SOPEntry] { index?.sops.filter { $0.confidence >= 0.8 } ?? [] }

    /// SOPs created in the last 24 hours.
    var recent: [SOPEntry] {
        let cutoff = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-86400))
        return index?.sops.filter { $0.created_at >= cutoff } ?? []
    }
}
