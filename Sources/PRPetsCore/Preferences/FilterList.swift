import Foundation

/// The two lists that decide which pull requests are fetched, and how to read entries for them from whatever
/// people type or paste: bare names, GitHub links, git remotes or search qualifiers.
///
/// GitHub quietly ignores a `-repo:` it can't resolve, and a stray space turns `user:` into a free-text search,
/// so entries are cleaned up here rather than sent as typed.
public enum FilterListKind: Hashable, Sendable {
    /// Orgs or users to limit fetching to (`onlyOwners`).
    case owners
    /// `owner/name` repositories to leave out (`excludedRepositories`).
    case repositories

    /// The entry `token` refers to, in the form saved in preferences, or nil if it can't be read as one.
    public func normalised(_ token: String) -> String? {
        let cleaned = Self.unwrapped(token)
        guard !cleaned.isEmpty else { return nil }
        switch self {
        case .owners: return Self.owner(in: cleaned)
        case .repositories: return Self.repository(in: cleaned)
        }
    }

    /// Adds every entry in `text`, which may hold several separated by commas, spaces or new lines.
    public func adding(_ text: String, to entries: [String]) -> FilterListAddition {
        var result = entries
        var added: [String] = []
        var alreadyListed: [String] = []
        var unreadable: [String] = []
        for token in Self.tokens(in: text) {
            guard let entry = normalised(token) else {
                unreadable.append(token)
                continue
            }
            let isSameEntry = { (other: String) in Self.sameEntry(other, entry) }
            if result.contains(where: isSameEntry) {
                // Repeats within the pasted text aren't worth mentioning; entries that were there before are.
                if entries.contains(where: isSameEntry), !alreadyListed.contains(where: isSameEntry) { alreadyListed.append(entry) }
                continue
            }
            result.append(entry)
            added.append(entry)
        }
        return FilterListAddition(entries: result, added: added, alreadyListed: alreadyListed, unreadable: unreadable)
    }

    /// The saved entries GitHub can use, cleaned up and without repeats. Older versions saved whatever was typed.
    public func usable(_ entries: [String]) -> [String] {
        entries.compactMap(normalised).reduce(into: []) { usable, entry in
            if !usable.contains(where: { Self.sameEntry($0, entry) }) { usable.append(entry) }
        }
    }

    /// Entries that could be added from what's open right now, busiest first, leaving out any already listed.
    public func suggestions(from snapshot: PullRequestSnapshot, excluding entries: [String]) -> [FilterSuggestion] {
        let counts = snapshot.pullRequests.reduce(into: [String: (entry: String, count: Int)]()) { counts, pullRequest in
            let entry = switch self {
            case .owners: pullRequest.repository.owner
            case .repositories: pullRequest.repository.nameWithOwner
            }
            counts[entry.lowercased(), default: (entry, 0)].count += 1
        }
        return counts.values
            .filter { candidate in !entries.contains { Self.sameEntry($0, candidate.entry) } }
            .map { FilterSuggestion(entry: $0.entry, pullRequestCount: $0.count) }
            .sorted { ($1.pullRequestCount, $0.entry.lowercased()) < ($0.pullRequestCount, $1.entry.lowercased()) }
    }

    /// GitHub owner and repository names are case-insensitive.
    private static func sameEntry(_ lhs: String, _ rhs: String) -> Bool {
        lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    // MARK: - Reading entries

    /// Names never contain commas, semicolons or whitespace, so any of them can separate pasted entries.
    private static func tokens(in text: String) -> [String] {
        text.components(separatedBy: separators).filter { !$0.isEmpty }
    }

    /// Strips what tends to come along when copying: quotes, brackets and search qualifiers.
    private static func unwrapped(_ token: String) -> String {
        var cleaned = token.trimmingCharacters(in: wrapping)
        for qualifier in ["-repo:", "repo:", "-user:", "user:", "-org:", "org:", "@"] where cleaned.lowercased().hasPrefix(qualifier) {
            cleaned.removeFirst(qualifier.count)
            break
        }
        return cleaned
    }

    /// `acme`, from `acme`, `@acme`, `user:acme` or a link to anything under `github.com/acme`.
    private static func owner(in token: String) -> String? {
        let path = pathComponents(of: token)
        // A bare `acme/api` is a repository, which this list can't hold; a link under the owner is fine.
        guard let owner = path.first, path.count == 1 || isLink(token) else { return nil }
        return isOwnerName(owner) ? owner : nil
    }

    /// `acme/api`, from `acme/api`, a link to the repository or anything in it, or a git remote.
    private static func repository(in token: String) -> String? {
        let path = pathComponents(of: token)
        guard path.count >= 2, path.count == 2 || isLink(token), isOwnerName(path[0]) else { return nil }
        var name = path[1]
        if name.lowercased().hasSuffix(".git") { name.removeLast(4) }
        return isRepositoryName(name) ? "\(path[0])/\(name)" : nil
    }

    private static func isLink(_ token: String) -> Bool {
        token.contains("://") || token.contains("@") || hostPrefix(of: token) != nil
    }

    /// The path after any scheme and host: `https://github.com/acme/api/pull/3` gives `acme`, `api`, `pull`, `3`.
    private static func pathComponents(of token: String) -> [String] {
        var path = Substring(token)
        if let schemeEnd = path.range(of: "://") {
            path = path[schemeEnd.upperBound...]
            path = path.drop { $0 != "/" }
        } else if let at = path.firstIndex(of: "@"), let colon = path[at...].firstIndex(of: ":") {
            // git@github.com:acme/api.git
            path = path[path.index(after: colon)...]
        } else if let host = hostPrefix(of: token) {
            path = path.dropFirst(host.count)
        }
        guard isLink(token) else { return path.split(separator: "/").map(String.init) }
        var components = path.prefix { $0 != "?" && $0 != "#" }.split(separator: "/").map(String.init)
        // github.com/orgs/acme/… and github.com/users/acme/… are pages about acme.
        if components.count >= 2, ["orgs", "users"].contains(components[0].lowercased()) {
            components.removeFirst()
        }
        return components
    }

    /// `github.com/` in `github.com/acme/api`. Owner names can't contain dots, so a dotted first part is a host.
    private static func hostPrefix(of token: String) -> String? {
        guard let slash = token.firstIndex(of: "/") else { return nil }
        let first = token[..<slash]
        return first.contains(".") ? String(token[...slash]) : nil
    }

    /// Letters, digits, hyphens, and the underscores Enterprise Managed User logins carry.
    private static func isOwnerName(_ name: String) -> Bool {
        !name.isEmpty && name.unicodeScalars.allSatisfy { ownerCharacters.contains($0) }
    }

    private static func isRepositoryName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && name.unicodeScalars.allSatisfy { repositoryCharacters.contains($0) }
    }

    // Built once: the app reads the query, and so normalises every entry, on each overlay frame.
    private static let separators = CharacterSet(charactersIn: ",;").union(.whitespacesAndNewlines)
    private static let wrapping = CharacterSet(charactersIn: "\"'`<>[]()").union(.whitespacesAndNewlines)
    private static let asciiAlphanumerics = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    private static let ownerCharacters = asciiAlphanumerics.union(CharacterSet(charactersIn: "-_"))
    private static let repositoryCharacters = asciiAlphanumerics.union(CharacterSet(charactersIn: "-_."))
}

/// What happened when text was added to a filter list.
public struct FilterListAddition: Hashable, Sendable {
    /// The whole list afterwards: what was there, then the new entries in the order they were given.
    public let entries: [String]
    public let added: [String]
    /// Entries that were already in the list, ignoring case.
    public let alreadyListed: [String]
    /// Pieces that couldn't be read, exactly as given, so they can be left in the field to fix.
    public let unreadable: [String]
}

/// An entry seen in the latest fetch, offered so it doesn't have to be typed.
public struct FilterSuggestion: Hashable, Sendable {
    public let entry: String
    public let pullRequestCount: Int

    public init(entry: String, pullRequestCount: Int) {
        self.entry = entry
        self.pullRequestCount = pullRequestCount
    }
}
