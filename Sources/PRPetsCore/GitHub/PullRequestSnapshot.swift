import Foundation

/// Everything known about the viewer's open pull requests at one moment.
///
/// `pullRequests` also holds "context" PRs that don't involve the viewer but share a stack
/// with one that does, so stacks can be shown whole.
public struct PullRequestSnapshot: Hashable, Codable, Sendable {
    public let viewer: Login
    public let fetchedAt: Date
    public let pullRequests: [PullRequest]
    /// PRs where GitHub reports a pending review request for the viewer, directly or via a team.
    public let reviewRequestedOfViewer: Set<PullRequestID>

    public init(
        viewer: Login,
        fetchedAt: Date,
        pullRequests: [PullRequest],
        reviewRequestedOfViewer: Set<PullRequestID>
    ) {
        self.viewer = viewer
        self.fetchedAt = fetchedAt
        self.pullRequests = Self.uniqued(pullRequests)
        self.reviewRequestedOfViewer = reviewRequestedOfViewer
    }

    public func pullRequest(withID id: PullRequestID) -> PullRequest? {
        pullRequests.first { $0.id == id }
    }

    /// This snapshot without the pull requests `query` leaves out. Sources already filter what they fetch, so this
    /// only matters when the query has narrowed since: ignoring a repository sends its pets home at once instead
    /// of after the next fetch. A wider query still needs a fetch to find anything new.
    public func narrowed(to query: PullRequestQuery) -> PullRequestSnapshot {
        let kept = pullRequests.filter { query.includes($0.repository) }
        guard kept.count < pullRequests.count else { return self }
        return PullRequestSnapshot(
            viewer: viewer,
            fetchedAt: fetchedAt,
            pullRequests: kept,
            reviewRequestedOfViewer: reviewRequestedOfViewer.intersection(kept.map(\.id))
        )
    }

    private static func uniqued(_ pullRequests: [PullRequest]) -> [PullRequest] {
        var seen = Set<PullRequestID>()
        return pullRequests.filter { seen.insert($0.id).inserted }
    }
}

/// Repository-pattern boundary for fetching pull requests. Implementations: `gh` CLI, demo scripts.
public protocol PullRequestSource: Sendable {
    func fetchSnapshot(_ query: PullRequestQuery) async throws -> PullRequestSnapshot
}

/// What the user wants fetched. Built from settings; sources translate it into their own query language.
public struct PullRequestQuery: Hashable, Codable, Sendable {
    /// Limit to these owners (orgs or users). Empty means everywhere.
    public var owners: [String]
    /// Repositories (`owner/name`) to ignore entirely.
    public var excludedRepositories: [String]
    /// Whether to fetch open PRs that share a stack with the viewer's PRs.
    public var includeStackContext: Bool

    public init(owners: [String] = [], excludedRepositories: [String] = [], includeStackContext: Bool = true) {
        self.owners = owners
        self.excludedRepositories = excludedRepositories
        self.includeStackContext = includeStackContext
    }

    /// Whether pull requests in `repository` are wanted, matching names the way GitHub does: ignoring case.
    public func includes(_ repository: RepositoryName) -> Bool {
        let ownerWanted = owners.isEmpty || owners.contains { $0.caseInsensitiveCompare(repository.owner) == .orderedSame }
        let ignored = excludedRepositories.contains { $0.caseInsensitiveCompare(repository.nameWithOwner) == .orderedSame }
        return ownerWanted && !ignored
    }
}
