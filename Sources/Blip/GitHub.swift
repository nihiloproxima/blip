import Foundation

/// Ce qui s'affiche dans une liste groupable et filtrable par dépôt.
protocol Listable: Identifiable, Hashable where ID == String {
    var repositoryName: String { get }
    /// Ce sur quoi porte la recherche (⌘F).
    var searchableText: String { get }
}

struct GHNotification: Listable, Decodable, Sendable {
    let id: String
    let reason: String
    let unread: Bool
    let updatedAt: Date
    let lastReadAt: Date?
    let subject: Subject
    let repository: Repository

    struct Subject: Decodable, Hashable, Sendable {
        let title: String
        let url: URL?
        let latestCommentUrl: URL?
        let type: String
    }

    struct Repository: Decodable, Hashable, Sendable {
        let fullName: String
        let htmlUrl: URL
    }

    var repositoryName: String { repository.fullName }

    /// Famille du sujet pour les filtres : les variantes de CI et d'alertes de sécurité sont regroupées.
    var subjectKind: String {
        switch subject.type {
        case "CheckSuite", "WorkflowRun": "Actions"
        case "RepositoryVulnerabilityAlert", "RepositoryDependabotAlertsThread", "SecurityAdvisory": "Security"
        default: subject.type
        }
    }

    /// Numéro de l'issue ou de la PR, déduit de l'URL d'API du sujet.
    var number: Int? {
        guard subject.type == "PullRequest" || subject.type == "Issue" else { return nil }
        return subject.url.flatMap { Int($0.lastPathComponent) }
    }
}

/// PR ou issue ouverte qui te concerne, trouvée par la recherche GitHub.
struct WorkItem: Listable, Decodable, Sendable {
    let id: String
    let kind: String
    let number: Int
    let title: String
    let url: URL
    let updatedAt: Date
    let isDraft: Bool?
    /// `APPROVED`, `CHANGES_REQUESTED`, `REVIEW_REQUIRED` ou nil.
    let reviewDecision: String?
    let author: Author?
    let repository: Repository
    private let commits: LastCommit?

    struct Author: Decodable, Hashable, Sendable { let login: String }
    struct Repository: Decodable, Hashable, Sendable { let nameWithOwner: String }

    var repositoryName: String { repository.nameWithOwner }
    var isPullRequest: Bool { kind == "PullRequest" }
    var checks: String? { commits?.checks }
}

/// `commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }` d'une PR.
struct LastCommit: Decodable, Hashable, Sendable {
    let nodes: [Node]
    struct Node: Decodable, Hashable, Sendable { let commit: Commit }
    struct Commit: Decodable, Hashable, Sendable { let statusCheckRollup: Rollup? }
    struct Rollup: Decodable, Hashable, Sendable { let state: String }

    /// CI du dernier commit : `SUCCESS`, `FAILURE`, `ERROR`, `PENDING`, `EXPECTED` ou nil.
    var checks: String? { nodes.first?.commit.statusCheckRollup?.state }
}

/// Le travail en cours : mes PR, les reviews qu'on m'a demandées, ce qui m'est assigné.
struct Work: Sendable {
    var mine: [WorkItem] = []
    var reviews: [WorkItem] = []
    var assigned: [WorkItem] = []
}

enum SubjectState: Sendable {
    case open, draft, merged, closed, notPlanned

    /// Encore susceptible de changer (et d'avoir une CI qui tourne).
    var isOpen: Bool { self == .open || self == .draft }
}

/// État d'une PR ou d'une issue, et de sa CI pour une PR.
struct SubjectInfo: Sendable {
    let state: SubjectState
    let checks: String?
}

enum GitHubError: LocalizedError {
    case unauthorized
    case rateLimited(Date?)
    case http(Int, String?)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            "GitHub a refusé le token."
        case .rateLimited(let reset):
            "Limite d'API atteinte" + (reset.map { ", reprise à \($0.formatted(date: .omitted, time: .shortened))" } ?? "") + "."
        case .http(let status, let message):
            "GitHub a répondu \(status)" + (message.map { " : \($0)" } ?? "") + "."
        }
    }
}

/// Client minimal de l'API GitHub : uniquement ce dont Blip a besoin.
struct GitHub: Sendable {
    let token: String

    enum Poll: Sendable {
        case notModified(interval: Int)
        case updated([GHNotification], lastModified: String?, interval: Int)
    }

    private static let api = URL(string: "https://api.github.com")!

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func login() async throws -> String {
        struct User: Decodable { let login: String }
        return try await Self.decoder.decode(User.self, from: send(Self.api.appending(path: "user"))).login
    }

    /// Notifications non lues, ou toutes avec `all` (pour l'historique). Avec `ifModifiedSince`,
    /// GitHub répond 304 sans rien décompter du rate limit tant que rien n'a bougé :
    /// c'est le mode de polling qu'il recommande.
    func notifications(all: Bool = false, participating: Bool, ifModifiedSince: String? = nil, maxPages: Int = 5) async throws -> Poll {
        var next: URL? = Self.api.appending(path: "notifications").appending(queryItems: [
            URLQueryItem(name: "all", value: String(all)),
            URLQueryItem(name: "per_page", value: "50"),
            URLQueryItem(name: "participating", value: String(participating)),
        ])
        var items: [GHNotification] = []
        var lastModified: String?
        var interval = 60
        for page in 0..<maxPages {
            guard let url = next else { break }
            var request = request(url)
            if page == 0, let ifModifiedSince {
                request.setValue(ifModifiedSince, forHTTPHeaderField: "If-Modified-Since")
            }
            let (data, response) = try await perform(request, accepting: [304])
            if page == 0 {
                interval = max(60, Int(response.value(forHTTPHeaderField: "X-Poll-Interval") ?? "") ?? 60)
                if response.statusCode == 304 { return .notModified(interval: interval) }
                lastModified = response.value(forHTTPHeaderField: "Last-Modified")
            }
            items += try Self.decoder.decode([GHNotification].self, from: data)
            next = Self.nextPage(response.value(forHTTPHeaderField: "Link"))
        }
        return .updated(items, lastModified: lastModified, interval: interval)
    }

    func markRead(_ id: String) async throws {
        try await send(Self.api.appending(path: "notifications/threads/\(id)"), method: "PATCH")
    }

    /// « Terminé » : retire aussi le fil de la boîte de réception web.
    func markDone(_ id: String) async throws {
        try await send(Self.api.appending(path: "notifications/threads/\(id)"), method: "DELETE")
    }

    func unsubscribe(_ id: String) async throws {
        try await send(Self.api.appending(path: "notifications/threads/\(id)/subscription"), method: "PUT", body: ["ignored": true])
    }

    /// État (ouverte, mergée…) des PR et issues, et CI des PR, en une requête GraphQL par lot de 50.
    func subjects(of items: [GHNotification]) async throws -> [String: SubjectInfo] {
        struct Node: Decodable { let state: String?; let isDraft: Bool?; let stateReason: String?; let commits: LastCommit? }
        struct Repository: Decodable { let issueOrPullRequest: Node? }
        struct Response: Decodable { let data: [String: Repository?]? }

        var result: [String: SubjectInfo] = [:]
        let targets = items.filter { $0.number != nil }
        for start in stride(from: 0, to: targets.count, by: 50) {
            var ids: [String: String] = [:]
            var fields: [String] = []
            for (index, item) in targets[start..<min(start + 50, targets.count)].enumerated() {
                let parts = item.repository.fullName.split(separator: "/", maxSplits: 1).map(String.init)
                guard parts.count == 2, let number = item.number else { continue }
                ids["n\(index)"] = item.id
                fields.append("""
                n\(index): repository(owner: \(Self.quoted(parts[0])), name: \(Self.quoted(parts[1]))) { \
                issueOrPullRequest(number: \(number)) { ... on PullRequest { state isDraft \
                commits(last: 1) { nodes { commit { statusCheckRollup { state } } } } } ... on Issue { state stateReason } } }
                """)
            }
            guard !fields.isEmpty else { continue }
            let data = try await send(Self.api.appending(path: "graphql"), method: "POST", body: ["query": "query { \(fields.joined(separator: " ")) }"])
            for (alias, repository) in try Self.decoder.decode(Response.self, from: data).data ?? [:] {
                guard let id = ids[alias], let node = repository?.issueOrPullRequest, let state = node.state else { continue }
                let subjectState: SubjectState = switch state {
                case "MERGED": .merged
                case "CLOSED": node.stateReason == "NOT_PLANNED" ? .notPlanned : .closed
                default: node.isDraft == true ? .draft : .open
                }
                result[id] = SubjectInfo(state: subjectState, checks: node.commits?.checks)
            }
        }
        return result
    }

    /// Les trois recherches du tableau de bord, en une seule requête GraphQL.
    func work() async throws -> Work {
        struct Search: Decodable { let nodes: [WorkItem] }
        struct Payload: Decodable { let mine: Search; let reviews: Search; let assigned: Search }
        struct Response: Decodable { let data: Payload }

        func search(_ alias: String, _ query: String) -> String {
            "\(alias): search(type: ISSUE, first: 50, query: \(Self.quoted(query + " archived:false sort:updated-desc"))) { nodes { ...item } }"
        }
        let query = """
        query {
          \(search("mine", "is:pr is:open author:@me"))
          \(search("reviews", "is:pr is:open review-requested:@me"))
          \(search("assigned", "is:open assignee:@me"))
        }
        fragment item on SearchResultItem {
          kind: __typename
          ... on PullRequest { id number title url updatedAt isDraft reviewDecision author { login } repository { nameWithOwner } \
        commits(last: 1) { nodes { commit { statusCheckRollup { state } } } } }
          ... on Issue { id number title url updatedAt author { login } repository { nameWithOwner } }
        }
        """
        let data = try await send(Self.api.appending(path: "graphql"), method: "POST", body: ["query": query])
        let payload = try Self.decoder.decode(Response.self, from: data).data
        return Work(mine: payload.mine.nodes, reviews: payload.reviews.nodes, assigned: payload.assigned.nodes)
    }

    /// Page web d'une notification, ancrée sur le dernier commentaire quand c'est possible.
    func webURL(for item: GHNotification) async -> URL {
        let repository = item.repository.htmlUrl
        if let api = item.subject.url {
            // https://api.github.com/repos/{owner}/{repo}/{kind}/{id}
            let parts = api.pathComponents
            if parts.count >= 6 {
                let anchor = Self.commentAnchor(item.subject.latestCommentUrl)
                switch parts[4] {
                case "pulls": return Self.url(repository.appending(path: "pull/\(parts[5])"), fragment: anchor)
                case "issues": return Self.url(repository.appending(path: "issues/\(parts[5])"), fragment: anchor)
                case "commits": return repository.appending(path: "commit/\(parts[5])")
                default: break
                }
            }
            // Releases et autres : l'API du sujet donne directement l'URL web.
            struct Page: Decodable { let htmlUrl: URL }
            if let data = try? await send(api), let page = try? Self.decoder.decode(Page.self, from: data) {
                return page.htmlUrl
            }
        }
        return switch item.subject.type {
        case "Discussion": repository.appending(path: "discussions").appending(queryItems: [URLQueryItem(name: "discussions_q", value: item.subject.title)])
        case "CheckSuite", "WorkflowRun": repository.appending(path: "actions")
        case "RepositoryVulnerabilityAlert", "RepositoryDependabotAlertsThread": repository.appending(path: "security/dependabot")
        default: repository
        }
    }

    // MARK: - HTTP

    @discardableResult
    private func send(_ url: URL, method: String = "GET", body: (any Encodable & Sendable)? = nil) async throws -> Data {
        var request = request(url)
        request.httpMethod = method
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return try await perform(request).0
    }

    private func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }

    private func perform(_ request: URLRequest, accepting extra: Set<Int> = []) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if (200..<300).contains(http.statusCode) || extra.contains(http.statusCode) { return (data, http) }
        if http.statusCode == 401 { throw GitHubError.unauthorized }
        if [403, 429].contains(http.statusCode), http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" {
            let reset = http.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:))
            throw GitHubError.rateLimited(reset)
        }
        struct Message: Decodable { let message: String }
        throw GitHubError.http(http.statusCode, try? JSONDecoder().decode(Message.self, from: data).message)
    }

    private static func nextPage(_ link: String?) -> URL? {
        guard let part = link?.split(separator: ",").first(where: { $0.contains(#"rel="next""#) }),
              let start = part.firstIndex(of: "<"), let end = part.firstIndex(of: ">") else { return nil }
        return URL(string: String(part[part.index(after: start)..<end]))
    }

    /// `…/issues/comments/42` → `issuecomment-42`, `…/pulls/comments/42` → `discussion_r42`.
    private static func commentAnchor(_ url: URL?) -> String? {
        guard let parts = url?.pathComponents, parts.count >= 7, parts[parts.count - 2] == "comments" else { return nil }
        let id = parts[parts.count - 1]
        return switch parts[4] {
        case "issues": "issuecomment-\(id)"
        case "pulls": "discussion_r\(id)"
        default: nil
        }
    }

    private static func url(_ url: URL, fragment: String?) -> URL {
        guard let fragment, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.fragment = fragment
        return components.url ?? url
    }

    /// Littéral de chaîne GraphQL (même syntaxe d'échappement que JSON).
    private static func quoted(_ string: String) -> String {
        String(decoding: (try? JSONEncoder().encode(string)) ?? Data(#""""#.utf8), as: UTF8.self)
    }
}
