import XCTest
@testable import PRBar

final class InboxVisibilityTests: XCTestCase {
    func testFilterDisabledKeepsEverything() {
        let prs = [
            makePR(nodeId: "A", reviewDecision: "APPROVED"),
            makePR(nodeId: "R", reviewDecision: "REVIEW_REQUIRED"),
            makePR(nodeId: "C", reviewDecision: "CHANGES_REQUESTED"),
            makePR(nodeId: "N", reviewDecision: nil),
        ]
        let result = InboxVisibility.filter(prs, hideReviewedByOthers: false)
        XCTAssertEqual(result.map(\.nodeId), ["A", "R", "C", "N"])
    }

    func testFilterEnabledDropsReviewedByOthers() {
        let prs = [
            makePR(nodeId: "A", reviewDecision: "APPROVED"),
            makePR(nodeId: "R", reviewDecision: "REVIEW_REQUIRED"),
            makePR(nodeId: "C", reviewDecision: "CHANGES_REQUESTED"),
            makePR(nodeId: "N", reviewDecision: nil),
        ]
        let result = InboxVisibility.filter(prs, hideReviewedByOthers: true)
        // A PR another reviewer has already decided (APPROVED or
        // CHANGES_REQUESTED) is dropped; not-yet-reviewed / unknown stay
        // actionable because they're still waiting on you.
        XCTAssertEqual(result.map(\.nodeId), ["R", "N"])
    }

    // MARK: helpers

    private func makePR(nodeId: String, reviewDecision: String?) -> InboxPR {
        InboxPR(
            nodeId: nodeId,
            owner: "o",
            repo: "r",
            number: 1,
            title: "t",
            body: "",
            url: URL(string: "https://github.com/o/r/pull/1")!,
            author: "a",
            headRef: "h",
            baseRef: "main",
            headSha: "abc",
            isDraft: false,
            role: .reviewRequested,
            mergeable: "MERGEABLE",
            mergeStateStatus: "BLOCKED",
            reviewDecision: reviewDecision,
            checkRollupState: "PENDING",
            totalAdditions: 1,
            totalDeletions: 0,
            changedFiles: 1,
            hasAutoMerge: false,
            autoMergeEnabledBy: nil,
            allCheckSummaries: [],
            allowedMergeMethods: [.squash],
            autoMergeAllowed: true,
            deleteBranchOnMerge: true
        )
    }
}
