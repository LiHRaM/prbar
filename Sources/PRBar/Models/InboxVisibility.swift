import Foundation

/// Opt-in control for whether already-reviewed (APPROVED) review-requested
/// PRs stay visible in the Inbox list.
///
/// These PRs never contribute to the menu-bar badge — `BadgeCounter` drops
/// `reviewDecision == "APPROVED"` from the review-requested count — yet the
/// Inbox still shows them, sunk to the bottom bucket. When the user opts in,
/// the list matches the badge by removing them entirely instead of just
/// sorting them last.
enum InboxVisibility {
    /// Default off (unset key reads false): hiding rows is a deliberate
    /// opt-in. Views read this via `@AppStorage`.
    static let hideReviewedKey = "hideReviewedFromInbox"

    /// A review-requested PR is "already reviewed" when its decision is
    /// APPROVED — the same exclusion the badge applies.
    static func isAlreadyReviewed(_ pr: InboxPR) -> Bool {
        pr.reviewDecision == "APPROVED"
    }

    /// Apply the opt-in filter to an already role-filtered inbox list.
    static func filter(_ prs: [InboxPR], hideReviewed: Bool) -> [InboxPR] {
        guard hideReviewed else { return prs }
        return prs.filter { !isAlreadyReviewed($0) }
    }
}
