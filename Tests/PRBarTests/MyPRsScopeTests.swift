import XCTest
@testable import PRBar

final class MyPRsScopeTests: XCTestCase {
    // MARK: MyPRsCategory classification

    func testCategoryClassification() {
        XCTAssertEqual(MyPRsCategory.of(makePR(merge: "CLEAN", review: "APPROVED")), .readyToMerge)
        XCTAssertEqual(MyPRsCategory.of(makePR(merge: "BLOCKED", review: "APPROVED")), .approvedWaiting)
        XCTAssertEqual(MyPRsCategory.of(makePR(merge: "CONFLICTING")), .conflicts)
        XCTAssertEqual(MyPRsCategory.of(makePR(merge: "DIRTY")), .conflicts)
        XCTAssertEqual(MyPRsCategory.of(makePR(ci: "FAILURE")), .redCI)
        XCTAssertEqual(MyPRsCategory.of(makePR(ci: "ERROR")), .redCI)
        XCTAssertEqual(MyPRsCategory.of(makePR(ci: "PENDING")), .ciInFlight)
        XCTAssertEqual(MyPRsCategory.of(makePR(ci: "EXPECTED")), .ciInFlight)
        XCTAssertEqual(MyPRsCategory.of(makePR(review: "CHANGES_REQUESTED")), .changesRequested)
        XCTAssertEqual(MyPRsCategory.of(makePR(review: "REVIEW_REQUIRED")), .reviewRequired)
        XCTAssertEqual(MyPRsCategory.of(makePR()), .other)
        XCTAssertEqual(MyPRsCategory.of(makePR(isDraft: true, merge: "CLEAN", review: "APPROVED")), .draft)
    }

    /// Merge state outranks CI: a blocked-approved PR that is also failing CI
    /// classifies as approved-waiting (mergeState checked first), matching the
    /// list's sort precedence.
    func testCategoryPrecedenceMergeStateBeatsCI() {
        let pr = makePR(merge: "BLOCKED", review: "APPROVED", ci: "FAILURE")
        XCTAssertEqual(MyPRsCategory.of(pr), .approvedWaiting)
    }

    /// Draft is checked before every other signal, so a draft is `.draft`
    /// regardless of merge/CI/review state — it must never leak into a
    /// non-draft category (and thus into `.needsAttention`).
    func testDraftBeatsAllOtherSignals() {
        XCTAssertEqual(MyPRsCategory.of(makePR(isDraft: true, merge: "CONFLICTING")), .draft)
        XCTAssertEqual(MyPRsCategory.of(makePR(isDraft: true, ci: "FAILURE")), .draft)
        XCTAssertEqual(MyPRsCategory.of(makePR(isDraft: true, review: "CHANGES_REQUESTED")), .draft)
    }

    /// The list sort order is `MyPRsCategory`'s declaration order via its
    /// synthesized `Comparable`. This pins the canonical attention order
    /// (failing CI surfaces above conflicts; idle above drafts) so a future
    /// case reordering fails the build.
    func testCategoryComparableOrder() {
        let canonical: [MyPRsCategory] = [
            .readyToMerge, .approvedWaiting, .changesRequested, .redCI,
            .conflicts, .ciInFlight, .reviewRequired, .other, .draft,
        ]
        XCTAssertEqual(canonical.shuffled().sorted(), canonical)
    }

    // MARK: MyPRsScope.includes

    func testScopeAllShowsEverything() {
        for pr in samplePRs() {
            XCTAssertTrue(MyPRsScope.all.includes(pr, badgeReadyToMerge: true, badgeCIFailed: true))
        }
    }

    func testScopeNeedsAttention() {
        let show: [InboxPR] = [
            makePR(merge: "CLEAN", review: "APPROVED"),    // ready-to-merge
            makePR(merge: "BLOCKED", review: "APPROVED"),  // approved-and-waiting (shown per request)
            makePR(review: "CHANGES_REQUESTED"),
            makePR(ci: "FAILURE"),                         // red CI
            makePR(merge: "CONFLICTING"),
        ]
        let hide: [InboxPR] = [
            makePR(ci: "PENDING"),                         // CI in flight
            makePR(review: "REVIEW_REQUIRED"),
            makePR(),                                      // idle / other
        ]
        for pr in show {
            XCTAssertTrue(MyPRsScope.needsAttention.includes(pr, badgeReadyToMerge: true, badgeCIFailed: true),
                          "expected shown: \(MyPRsCategory.of(pr))")
        }
        for pr in hide {
            XCTAssertFalse(MyPRsScope.needsAttention.includes(pr, badgeReadyToMerge: true, badgeCIFailed: true),
                           "expected hidden: \(MyPRsCategory.of(pr))")
        }
    }

    func testScopeCounterOnlyMatchesBadge() {
        let ready = makePR(merge: "CLEAN", review: "APPROVED")
        let red = makePR(ci: "FAILURE")
        let idle = makePR()

        XCTAssertTrue(MyPRsScope.counterOnly.includes(ready, badgeReadyToMerge: true, badgeCIFailed: true))
        XCTAssertTrue(MyPRsScope.counterOnly.includes(red, badgeReadyToMerge: true, badgeCIFailed: true))
        XCTAssertFalse(MyPRsScope.counterOnly.includes(idle, badgeReadyToMerge: true, badgeCIFailed: true))
    }

    /// `.counterOnly` honours the badge source toggles: a disabled source
    /// excludes those PRs from the count, so they are hidden from the list.
    func testScopeCounterOnlyRespectsSourceToggles() {
        let ready = makePR(merge: "CLEAN", review: "APPROVED")
        let red = makePR(ci: "FAILURE")

        XCTAssertFalse(MyPRsScope.counterOnly.includes(ready, badgeReadyToMerge: false, badgeCIFailed: true),
                       "ready-to-merge hidden when its badge source is off")
        XCTAssertFalse(MyPRsScope.counterOnly.includes(red, badgeReadyToMerge: true, badgeCIFailed: false),
                       "red-CI hidden when its badge source is off")
    }

    /// CI-failed counts toward the badge independently of merge state /
    /// approval, so `.counterOnly` shows a blocked-approved PR with red CI
    /// even though its *category* is approvedWaiting.
    func testScopeCounterOnlyCIFailedIsIndependentOfMergeState() {
        let pr = makePR(merge: "BLOCKED", review: "APPROVED", ci: "FAILURE")
        XCTAssertEqual(MyPRsCategory.of(pr), .approvedWaiting)
        XCTAssertTrue(MyPRsScope.counterOnly.includes(pr, badgeReadyToMerge: false, badgeCIFailed: true))
    }

    /// The load-bearing invariant: `.counterOnly` shows a PR exactly when the
    /// badge counts it on an authored arm (ready-to-merge or red CI), for every
    /// source-toggle combination and every role. Asserted per-PR rather than as
    /// a total so a PR that hits both arms — which the badge tallies twice — is
    /// still correctly shown once. Guards against the list and the menu-bar
    /// badge drifting apart.
    func testCounterOnlyShownIffBadgeCountsItAuthored() {
        let prs = [
            makePR(nodeId: "READY", merge: "CLEAN", review: "APPROVED"),
            makePR(nodeId: "RED", ci: "FAILURE"),
            makePR(nodeId: "BOTH_READY", role: .both, merge: "CLEAN", review: "APPROVED"),
            makePR(nodeId: "DOUBLE", merge: "CLEAN", review: "APPROVED", ci: "FAILURE"), // ready AND failing
            makePR(nodeId: "IDLE"),
        ]
        for ready in [false, true] {
            for ciFailed in [false, true] {
                let sources = BadgeCounter.Sources(readyToMerge: ready, reviewRequested: true, ciFailed: ciFailed)
                for pr in prs {
                    let shown = MyPRsScope.counterOnly.includes(pr, badgeReadyToMerge: ready, badgeCIFailed: ciFailed)
                    let badge = BadgeCounter.counts(prs: [pr], sources: sources)
                    let counted = (badge.readyToMerge + badge.ciFailed) > 0
                    XCTAssertEqual(shown, counted,
                                   "counterOnly vs badge mismatch for \(pr.nodeId) (ready=\(ready) ci=\(ciFailed))")
                }
            }
        }
    }

    /// `.counterOnly` mirrors only the badge's AUTHORED arms, never the
    /// review-requested arm. A `.both` PR awaiting review contributes to the
    /// badge total yet must stay hidden from My PRs under `.counterOnly` — this
    /// pins that divergence so "track the whole badge total" can't sneak in.
    func testCounterOnlyExcludesReviewRequestedArm() {
        let pr = makePR(nodeId: "BOTH_REQ", role: .both, merge: "BLOCKED", review: "REVIEW_REQUIRED")
        let badge = BadgeCounter.counts(prs: [pr], sources: .allOn)
        XCTAssertEqual(badge.reviewRequested, 1, "badge counts it via the review-requested arm")
        XCTAssertEqual(badge.readyToMerge + badge.ciFailed, 0, "but not via any authored arm")
        XCTAssertFalse(MyPRsScope.counterOnly.includes(pr, badgeReadyToMerge: true, badgeCIFailed: true),
                       "counterOnly tracks authored arms only, never review-requested")
    }

    // MARK: visibleAuthored (shared list + tab-count filter)

    func testVisibleAuthoredRoutesByRole() {
        let prs = [
            makePR(nodeId: "AUTH", merge: "CLEAN", review: "APPROVED"),
            makePR(nodeId: "BOTH", role: .both, ci: "FAILURE"),
            makePR(nodeId: "REQ", role: .reviewRequested, merge: "CLEAN", review: "APPROVED"),
        ]
        let visible = MyPRsScope.visibleAuthored(
            from: prs, draftHandling: .show, scope: .all,
            badgeReadyToMerge: true, badgeCIFailed: true
        )
        // authored + both are mine; review-requested-only is not.
        XCTAssertEqual(Set(visible.map(\.nodeId)), ["AUTH", "BOTH"])
    }

    func testVisibleAuthoredDraftHandlingVsScope() {
        let draft = makePR(nodeId: "DRAFT", isDraft: true, merge: "CLEAN", review: "APPROVED")
        let idle = makePR(nodeId: "IDLE")
        let ready = makePR(nodeId: "READY", merge: "CLEAN", review: "APPROVED")
        let prs = [draft, idle, ready]

        // .hide removes the draft regardless of scope.
        let hidden = MyPRsScope.visibleAuthored(
            from: prs, draftHandling: .hide, scope: .all,
            badgeReadyToMerge: true, badgeCIFailed: true
        )
        XCTAssertFalse(hidden.contains { $0.isDraft })

        // .needsAttention drops the idle PR but the scope must NOT re-gate the
        // draft — draft visibility is owned by draftHandling (here: shown).
        let attn = MyPRsScope.visibleAuthored(
            from: prs, draftHandling: .show, scope: .needsAttention,
            badgeReadyToMerge: true, badgeCIFailed: true
        )
        XCTAssertEqual(Set(attn.map(\.nodeId)), ["DRAFT", "READY"])

        // .hide + .needsAttention together: the draft filter removes the draft
        // and the scope removes the idle PR simultaneously.
        let hiddenAttn = MyPRsScope.visibleAuthored(
            from: prs, draftHandling: .hide, scope: .needsAttention,
            badgeReadyToMerge: true, badgeCIFailed: true
        )
        XCTAssertEqual(Set(hiddenAttn.map(\.nodeId)), ["READY"])
    }

    /// Drafts are governed by `MyDraftHandling`, never by the scope. Under
    /// `.silence` a draft stays listed even at the narrowest `.counterOnly`
    /// scope — matching `.silence`'s "visible in the list, off the badge"
    /// contract (so the list can legitimately show a silenced draft the badge
    /// doesn't count). `.hide` removes it regardless of scope.
    func testVisibleAuthoredCounterOnlyDefersDraftsToDraftHandling() {
        let draft = makePR(nodeId: "DRAFT", isDraft: true, ci: "FAILURE")
        let silenced = MyPRsScope.visibleAuthored(
            from: [draft], draftHandling: .silence, scope: .counterOnly,
            badgeReadyToMerge: true, badgeCIFailed: true
        )
        XCTAssertEqual(silenced.map(\.nodeId), ["DRAFT"],
                       "a silenced draft stays listed under counterOnly")

        let hidden = MyPRsScope.visibleAuthored(
            from: [draft], draftHandling: .hide, scope: .counterOnly,
            badgeReadyToMerge: true, badgeCIFailed: true
        )
        XCTAssertTrue(hidden.isEmpty, "a hidden draft is removed regardless of scope")
    }

    func testVisibleAuthoredCounterOnlyThreadsSourceToggles() {
        let ready = makePR(nodeId: "READY", merge: "CLEAN", review: "APPROVED")
        let red = makePR(nodeId: "RED", ci: "FAILURE")
        let idle = makePR(nodeId: "IDLE")
        let visible = MyPRsScope.visibleAuthored(
            from: [ready, red, idle], draftHandling: .show, scope: .counterOnly,
            badgeReadyToMerge: false, badgeCIFailed: true
        )
        // readyToMerge source off + ciFailed source on → only the red-CI PR
        // survives, confirming the toggles flow through visibleAuthored.
        XCTAssertEqual(visible.map(\.nodeId), ["RED"])
    }

    // MARK: helpers

    private func samplePRs() -> [InboxPR] {
        [
            makePR(merge: "CLEAN", review: "APPROVED"),
            makePR(merge: "BLOCKED", review: "APPROVED"),
            makePR(review: "CHANGES_REQUESTED"),
            makePR(ci: "FAILURE"),
            makePR(merge: "CONFLICTING"),
            makePR(ci: "PENDING"),
            makePR(review: "REVIEW_REQUIRED"),
            makePR(),
        ]
    }

    /// `merge`/`ci` default to sentinel strings that match no real GitHub
    /// state, so `makePR()` with no signals lands squarely in `.other`.
    private func makePR(
        nodeId: String = "PR_1",
        role: PRRole = .authored,
        isDraft: Bool = false,
        merge: String = "UNKNOWN",
        review: String? = nil,
        ci: String = "NONE"
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
            mergeStateStatus: merge,
            reviewDecision: review,
            checkRollupState: ci,
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
