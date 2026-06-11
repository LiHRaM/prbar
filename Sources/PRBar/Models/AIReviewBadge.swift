import Foundation

/// Presentation state for the per-row AI review indicator shown in the
/// inbox. A pure mapping from `ReviewState.Status` (plus head-SHA
/// staleness and the PR's role) so the badge logic is unit-testable
/// without a live `ReviewQueueWorker`. The view layer turns each case
/// into an icon + colour + tooltip.
enum AIReviewBadge: Sendable, Equatable, CaseIterable {
    /// No AI review yet, but one is expected for this row (the viewer was
    /// asked to review). Authored-only rows get no badge at all.
    case notYet
    case queued
    case running
    /// Completed against the PR's current head commit.
    case done
    /// Completed, but against an older commit than the PR's current head —
    /// the verdict is for a stale snapshot and a re-run is appropriate.
    case doneStale
    case failed

    /// Derive the badge from the live review entry. `nil` means "render no
    /// badge for this row".
    ///
    /// `reviewedSha` is the head the cached review ran against; when it no
    /// longer matches the PR's `headSha` a completed review is stale.
    init?(status: ReviewState.Status?, reviewedSha: String?, headSha: String, role: PRRole) {
        switch status {
        case .queued:
            self = .queued
        case .running:
            self = .running
        case .failed:
            self = .failed
        case .completed:
            self = reviewedSha == headSha ? .done : .doneStale
        case .none:
            // Without a review entry, only hint "not started" where a
            // review is actually expected. Authored-only rows never
            // enqueue a review, so a permanent "not yet" there is noise.
            guard role == .reviewRequested || role == .both else { return nil }
            self = .notYet
        }
    }
}
