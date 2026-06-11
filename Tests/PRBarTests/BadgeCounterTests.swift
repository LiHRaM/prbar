import XCTest
@testable import PRBar

final class BadgeCounterTests: XCTestCase {
    func testReadyToMergeAndReviewRequestedAndCIFailedCountIndependently() {
        let prs = [
            makePR(nodeId: "M1", role: .authored, mergeStateStatus: "CLEAN", reviewDecision: "APPROVED"),
            makePR(nodeId: "R1", role: .reviewRequested, reviewDecision: "REVIEW_REQUIRED"),
            makePR(nodeId: "C1", role: .authored, checkRollupState: "FAILURE"),
            // Authored PR that's both red CI *and* not ready: counts only as CI red.
            makePR(nodeId: "C2", role: .authored, checkRollupState: "ERROR"),
        ]

        let c = BadgeCounter.counts(prs: prs, sources: .allOn)
        XCTAssertEqual(c.readyToMerge, 1)
        XCTAssertEqual(c.reviewRequested, 1)
        XCTAssertEqual(c.ciFailed, 2)
        XCTAssertEqual(c.total, 4)
        XCTAssertEqual(BadgeCounter.title(prs: prs, sources: .allOn), "4")
    }

    func testTogglesFilterOutSources() {
        let prs = [
            makePR(nodeId: "M1", role: .authored, mergeStateStatus: "CLEAN", reviewDecision: "APPROVED"),
            makePR(nodeId: "R1", role: .reviewRequested, reviewDecision: "REVIEW_REQUIRED"),
        ]
        var sources = BadgeCounter.Sources.allOn
        sources.readyToMerge = false
        let c = BadgeCounter.counts(prs: prs, sources: sources)
        XCTAssertEqual(c.readyToMerge, 0, "disabled source should contribute 0")
        XCTAssertEqual(c.reviewRequested, 1)
    }

    func testEmptyTitleWhenNothingActionable() {
        let prs = [
            // Approved review request shouldn't fire — already handled.
            makePR(nodeId: "R1", role: .reviewRequested, reviewDecision: "APPROVED"),
            // Draft authored PR — even if mergeable, drafts don't count as ready.
            makePR(nodeId: "M1", role: .authored, isDraft: true,
                   mergeStateStatus: "CLEAN", reviewDecision: "APPROVED"),
        ]
        XCTAssertEqual(BadgeCounter.title(prs: prs, sources: .allOn), "")
    }

    func testAuthoredDraftSuppressedWhenIncludeAuthoredDraftsFalse() {
        // Red CI (not ready-to-merge): isReadyToMerge already guards !isDraft,
        // so the failing-CI arm is the only way to reach the suppression branch.
        let pr = makePR(nodeId: "D1", role: .authored, isDraft: true, checkRollupState: "FAILURE")
        var sources = BadgeCounter.Sources.allOn
        XCTAssertEqual(BadgeCounter.counts(prs: [pr], sources: sources).ciFailed, 1)
        sources.includeAuthoredDrafts = false
        XCTAssertEqual(BadgeCounter.counts(prs: [pr], sources: sources).ciFailed, 0,
                       "authored draft excluded when includeAuthoredDrafts is off")
    }

    func testNonFailingCIDoesNotCount() {
        let prs = [
            makePR(nodeId: "S1", role: .authored, checkRollupState: "SUCCESS"),
            makePR(nodeId: "P1", role: .authored, checkRollupState: "PENDING"),
        ]
        XCTAssertEqual(BadgeCounter.counts(prs: prs, sources: .allOn).ciFailed, 0,
                       "only FAILURE/ERROR count as red CI")
    }

    func testBothRoleCountsForBothSources() {
        // role=.both: counts as ready-to-merge AND as review-requested
        // (they're independent counters — the user is responsible *and*
        // being asked to review).
        let pr = makePR(
            nodeId: "X1",
            role: .both,
            isDraft: false,
            mergeStateStatus: "CLEAN",
            reviewDecision: "APPROVED"
        )
        // reviewDecision == APPROVED suppresses the review-requested
        // counter; we want a state where both sources fire. Tweak the
        // PR so it's still mergeable but we haven't reviewed it yet.
        let pr2 = makePR(
            nodeId: "X2",
            role: .both,
            mergeStateStatus: "CLEAN",
            reviewDecision: "REVIEW_REQUIRED"
        )
        let c = BadgeCounter.counts(prs: [pr, pr2], sources: .allOn)
        // pr (APPROVED) → ready-to-merge only.
        // pr2 (REVIEW_REQUIRED) → review-requested only (not mergeable per isReadyToMerge).
        XCTAssertEqual(c.readyToMerge, 1)
        XCTAssertEqual(c.reviewRequested, 1)
    }

    // MARK: helpers

    private func makePR(
        nodeId: String,
        role: PRRole,
        isDraft: Bool = false,
        mergeStateStatus: String = "BLOCKED",
        reviewDecision: String? = nil,
        checkRollupState: String = "PENDING"
    ) -> InboxPR {
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
            isDraft: isDraft,
            role: role,
            mergeable: "MERGEABLE",
            mergeStateStatus: mergeStateStatus,
            reviewDecision: reviewDecision,
            checkRollupState: checkRollupState,
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
