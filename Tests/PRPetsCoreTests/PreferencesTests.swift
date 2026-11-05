import Foundation
import PRPetsCore
import Testing

@Suite("Preferences")
struct PreferencesTests {
    @Test func anOldSettingsFileGetsDefaultsForNewSettings() throws {
        let old = Data(#"{"scale": 4, "labelStyle": "repository"}"#.utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: old)
        #expect(preferences.scale == 4)
        #expect(preferences.labelStyle == .repository)
        #expect(preferences.petLanes == [.needsMyReview])
        #expect(preferences.checkForUpdatesAutomatically)
        #expect(preferences.hideDuringFullScreen)
    }

    @Test func unreadableValuesFallBackInsteadOfFailing() throws {
        let odd = Data(#"{"scale": "huge", "petLanes": ["needsMyAction", "somethingNew"], "roamingArea": "moon"}"#.utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: odd)
        #expect(preferences.scale == Preferences.default.scale)
        #expect(preferences.roamingArea == .nearDoghouse)
    }

    @Test func roundTrips() throws {
        var preferences = Preferences()
        preferences.petLanes = [.needsMyReview, .needsMyAction]
        preferences.scale = 5
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        #expect(decoded == preferences)
    }
}

@Suite("Repository filtering preferences")
struct RepositoryFilteringPreferencesTests {
    @Test func nothingIsIgnoredByDefault() {
        let query = Preferences.default.pullRequestQuery
        #expect(query.excludedRepositories.isEmpty)
        #expect(query.owners.isEmpty)
    }

    @Test func ignoredRepositoriesAndOwnersReachTheQuery() {
        var preferences = Preferences()
        preferences.excludedRepositories = ["acme/legacy", "acme/sandbox"]
        preferences.onlyOwners = ["acme"]

        let query = preferences.pullRequestQuery

        #expect(query.excludedRepositories == ["acme/legacy", "acme/sandbox"], "order is kept")
        #expect(query.owners == ["acme"])
    }

    @Test func changingTheIgnoredRepositoriesChangesTheQuery() {
        // AppModel compares queries to decide whether a settings change needs a re-fetch.
        var preferences = Preferences()
        let before = preferences.pullRequestQuery
        preferences.excludedRepositories = ["acme/legacy"]
        #expect(preferences.pullRequestQuery != before)
    }

    @Test func ignoredRepositoriesSurviveSavingAndLoading() throws {
        var preferences = Preferences()
        preferences.excludedRepositories = ["acme/legacy", "someone/else"]
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        #expect(decoded.excludedRepositories == ["acme/legacy", "someone/else"])
        #expect(decoded.pullRequestQuery == preferences.pullRequestQuery)
    }

    @Test func aSettingsFileWithoutTheListIgnoresNothing() throws {
        let old = Data(#"{"scale": 4}"#.utf8)
        #expect(try JSONDecoder().decode(Preferences.self, from: old).excludedRepositories.isEmpty)
    }

    @Test func aMalformedListIgnoresNothingInsteadOfFailingTheWholeFile() throws {
        let odd = Data(#"{"scale": 4, "excludedRepositories": "acme/legacy"}"#.utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: odd)
        #expect(preferences.excludedRepositories.isEmpty)
        #expect(preferences.scale == 4)
    }
}
