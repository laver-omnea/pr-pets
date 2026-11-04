import Foundation
import PRPetsCore
import PRPetsDemo
import Testing

private func snapshot(_ pullRequests: [PullRequest], reviewRequested: [PullRequest]? = nil) -> PullRequestSnapshot {
    PullRequestSnapshot(
        viewer: Login("you"),
        fetchedAt: PullRequestFixture.referenceDate,
        pullRequests: pullRequests,
        reviewRequestedOfViewer: Set((reviewRequested ?? pullRequests).map(\.id))
    )
}

@Suite("Filter lists")
struct FilterListTests {
    @Test(arguments: [
        "acme/api",
        "  acme/api ",
        "https://github.com/acme/api",
        "https://github.com/acme/api/",
        "https://github.com/acme/api/pull/12",
        "https://github.com/acme/api.git",
        "https://github.example.com/acme/api/tree/main?tab=readme#top",
        "github.com/acme/api",
        "git@github.com:acme/api.git",
        "ssh://git@github.com/acme/api.git",
        "-repo:acme/api",
        "repo:acme/api",
        "`acme/api`",
        "\"acme/api\"",
    ])
    func repositoriesCanBeTypedPastedAsLinksOrCopiedFromAGitRemote(_ token: String) {
        #expect(FilterListKind.repositories.normalised(token) == "acme/api")
    }

    @Test(arguments: ["", "acme", "acme/", "/api", "acme/api/pull/3", "https://github.com/acme", "ac:me/api", "acme/a?b", "-repo:"])
    func thingsThatAreNotARepositoryAreNotAccepted(_ token: String) {
        #expect(FilterListKind.repositories.normalised(token) == nil)
    }

    @Test(arguments: [
        "acme",
        "@acme",
        "user:acme",
        "org:acme",
        "https://github.com/acme",
        "https://github.com/orgs/acme/repositories",
        "https://github.com/acme/api/pull/3",
        "github.com/acme",
    ])
    func ownersCanBeTypedOrPastedAsLinks(_ token: String) {
        #expect(FilterListKind.owners.normalised(token) == "acme")
    }

    @Test func enterpriseManagedUserLoginsAreOwnersToo() {
        #expect(FilterListKind.owners.normalised("octocat_acme") == "octocat_acme")
    }

    @Test(arguments: ["", "@", "acme/api", "acme corp", "ac.me"])
    func thingsThatAreNotAnOwnerAreNotAccepted(_ token: String) {
        #expect(FilterListKind.owners.normalised(token) == nil)
    }

    @Test func severalEntriesCanBePastedAtOnce() {
        let pasted = "acme/api, acme/web\nhttps://github.com/acme/docs/pull/1  nonsense ACME/API"

        let addition = FilterListKind.repositories.adding(pasted, to: ["acme/legacy"])

        #expect(addition.entries == ["acme/legacy", "acme/api", "acme/web", "acme/docs"])
        #expect(addition.added == ["acme/api", "acme/web", "acme/docs"])
        #expect(addition.alreadyListed.isEmpty, "a repeat within the pasted text isn't worth mentioning")
        #expect(addition.unreadable == ["nonsense"], "kept as typed so it can be fixed")
    }

    @Test func addingSomethingAlreadyListedChangesNothingWhateverItsCase() {
        let addition = FilterListKind.repositories.adding("Acme/Legacy acme/legacy", to: ["acme/legacy"])
        #expect(addition.entries == ["acme/legacy"])
        #expect(addition.added.isEmpty)
        #expect(addition.alreadyListed == ["Acme/Legacy"], "mentioned once")
    }

    @Test func entriesSavedAsTypedByOlderVersionsAreCleanedUpBeforeTheyReachTheQuery() {
        var preferences = Preferences()
        preferences.excludedRepositories = [" acme/api", "https://github.com/acme/web/", "acme", "ACME/API"]
        preferences.onlyOwners = ["@acme", "acme corp"]

        let query = preferences.pullRequestQuery

        #expect(query.excludedRepositories == ["acme/api", "acme/web"])
        #expect(query.owners == ["acme"], "a space would otherwise turn the rest into a free-text search")
    }

    @Test func suggestionsAreTheBusiestRepositoriesNotAlreadyIgnored() {
        let open = snapshot([
            PullRequestFixture.make(1, in: "acme/web"),
            PullRequestFixture.make(2, in: "acme/web"),
            PullRequestFixture.make(3, in: "acme/api"),
            PullRequestFixture.make(4, in: "beta/app"),
            PullRequestFixture.make(5, in: "beta/app"),
            PullRequestFixture.make(6, in: "acme/web"),
        ])

        let suggestions = FilterListKind.repositories.suggestions(from: open, excluding: ["ACME/api"])

        #expect(suggestions == [
            FilterSuggestion(entry: "acme/web", pullRequestCount: 3),
            FilterSuggestion(entry: "beta/app", pullRequestCount: 2),
        ])
    }

    @Test func ownerSuggestionsCountEveryRepositoryTheyOwn() {
        let open = snapshot([
            PullRequestFixture.make(1, in: "acme/web"),
            PullRequestFixture.make(2, in: "beta/app"),
            PullRequestFixture.make(3, in: "acme/api"),
        ])
        #expect(FilterListKind.owners.suggestions(from: open, excluding: []) == [
            FilterSuggestion(entry: "acme", pullRequestCount: 2),
            FilterSuggestion(entry: "beta", pullRequestCount: 1),
        ])
    }
}

@Suite("Narrowing a snapshot")
struct SnapshotNarrowingTests {
    @Test func ignoringARepositoryTakesItsPullRequestsOutStraightAway() {
        let kept = PullRequestFixture.make(1, in: "acme/web")
        let ignored = PullRequestFixture.make(2, in: "acme/legacy")

        let narrowed = snapshot([kept, ignored]).narrowed(to: PullRequestQuery(excludedRepositories: ["Acme/Legacy"]))

        #expect(narrowed.pullRequests == [kept])
        #expect(narrowed.reviewRequestedOfViewer == [kept.id])
    }

    @Test func limitingToOwnersKeepsOnlyTheirRepositories() {
        let acme = PullRequestFixture.make(1, in: "acme/web")
        let beta = PullRequestFixture.make(2, in: "beta/app")
        #expect(snapshot([acme, beta]).narrowed(to: PullRequestQuery(owners: ["ACME"])).pullRequests == [acme])
    }

    @Test func aQueryThatLeavesNothingOutChangesNothing() {
        let open = snapshot([PullRequestFixture.make(1), PullRequestFixture.make(2, in: "acme/api")], reviewRequested: [])
        #expect(open.narrowed(to: PullRequestQuery(owners: ["acme"], excludedRepositories: ["acme/legacy"])) == open)
    }
}
