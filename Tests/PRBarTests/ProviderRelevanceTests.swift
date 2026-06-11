import XCTest
@testable import PRBar

final class ProviderRelevanceTests: XCTestCase {
    func testSuppressionOffWarnsAboutEveryProvider() {
        let relevant = ProviderRelevance.relevantProviders(
            suppressionEnabled: false,
            defaultProviderRaw: ProviderID.claude.rawValue,
            repoOverrides: []
        )
        XCTAssertEqual(relevant, Set(ProviderID.allCases))
    }

    func testSuppressionOffIgnoresRepoOverrides() {
        // The off-path is an early return that must discard all config,
        // not coincidentally widen to it. The override must COINCIDE with
        // the default (both .claude) so the post-guard set would be the
        // strict subset {.claude}: dropping the guard fails this test,
        // whereas a non-overlapping override would union back to allCases
        // and hide the regression.
        let relevant = ProviderRelevance.relevantProviders(
            suppressionEnabled: false,
            defaultProviderRaw: ProviderID.claude.rawValue,
            repoOverrides: [.claude]
        )
        XCTAssertEqual(relevant, Set(ProviderID.allCases))
    }

    func testConcreteDefaultDropsTheOtherProvider() {
        let claudeOnly = ProviderRelevance.relevantProviders(
            suppressionEnabled: true,
            defaultProviderRaw: ProviderID.claude.rawValue,
            repoOverrides: []
        )
        XCTAssertEqual(claudeOnly, [.claude])

        let codexOnly = ProviderRelevance.relevantProviders(
            suppressionEnabled: true,
            defaultProviderRaw: ProviderID.codex.rawValue,
            repoOverrides: []
        )
        XCTAssertEqual(codexOnly, [.codex])
    }

    func testAutoKeepsBothProviders() {
        let relevant = ProviderRelevance.relevantProviders(
            suppressionEnabled: true,
            defaultProviderRaw: ProviderID.autoSentinel,
            repoOverrides: []
        )
        XCTAssertEqual(relevant, Set(ProviderID.allCases))
    }

    func testRepoOverrideReintroducesAProvider() {
        let relevant = ProviderRelevance.relevantProviders(
            suppressionEnabled: true,
            defaultProviderRaw: ProviderID.claude.rawValue,
            repoOverrides: [.codex]
        )
        XCTAssertEqual(relevant, [.claude, .codex])
    }

    func testUnrecognisedDefaultFallsBackToWarningAboutEverything() {
        let relevant = ProviderRelevance.relevantProviders(
            suppressionEnabled: true,
            defaultProviderRaw: "not-a-real-provider",
            repoOverrides: []
        )
        XCTAssertEqual(relevant, Set(ProviderID.allCases))
    }
}
