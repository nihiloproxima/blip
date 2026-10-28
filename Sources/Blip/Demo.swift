import Foundation

/// Mode démo pour les captures d'écran : `Blip -demo 9` affiche les 9 premières notifications factices
/// (`-demo 0` pour l'écran d'inbox zero), sans token ni réseau.
/// La progression se règle de la même façon, via les UserDefaults : `-xp 620 -streak 4`…
enum Demo {
    static let count = UserDefaults.standard.string(forKey: "demo").flatMap(Int.init)

    static var notifications: [GHNotification] {
        [
            item("1", "acme/storefront", .pullRequest(482), "Refonte du tunnel de paiement", reason: "review_requested", minutes: 4),
            item("2", "acme/storefront", .issue(477), "Le panier se vide après la connexion avec Apple", reason: "mention", minutes: 22),
            item("3", "acme/payments-api", .pullRequest(131), "Webhooks Stripe idempotents", reason: "assign", minutes: 35),
            item("4", "acme/storefront", .pullRequest(475), "Passer à Vite 6", reason: "author", minutes: 70),
            item("5", "acme/payments-api", .other("RepositoryDependabotAlertsThread"), "Vulnérabilité critique dans undici", reason: "security_alert", minutes: 130),
            item("6", "acme/payments-api", .other("CheckSuite"), "CI en échec sur main", reason: "ci_activity", minutes: 190),
            item("7", "nihiloproxima/blip", .issue(12), "Afficher le nombre de notifications par dépôt", reason: "comment", minutes: 300),
            item("8", "nihiloproxima/blip", .other("Release"), "v0.2.0", reason: "subscribed", minutes: 1_500),
            item("9", "nihiloproxima/blip", .other("Discussion"), "Idées d'accessoires pour le compagnon", reason: "comment", minutes: 2_900),
        ]
    }

    static let states: [String: SubjectState] = ["1": .open, "2": .open, "3": .draft, "4": .merged, "7": .closed]

    /// Vide à inbox zero, pour que l'écran des scores soit au calme.
    static var work: Work {
        guard count != 0 else { return Work() }
        return Work(
            mine: decode([
                work("acme/storefront", 486, "Paiement en un clic avec Apple Pay", minutes: 12, review: "REVIEW_REQUIRED", checks: "PENDING"),
                work("acme/payments-api", 131, "Webhooks Stripe idempotents", minutes: 36, draft: true, checks: "FAILURE"),
                work("nihiloproxima/blip", 14, "Onglets Mes PR, Reviews et Assignées", minutes: 140, review: "APPROVED", checks: "SUCCESS"),
                work("acme/storefront", 479, "Passer les images en AVIF", minutes: 1_600, review: "CHANGES_REQUESTED", checks: "SUCCESS"),
            ]),
            reviews: decode([
                work("acme/storefront", 482, "Refonte du tunnel de paiement", minutes: 4, checks: "SUCCESS", author: "alice-acme"),
                work("acme/payments-api", 128, "Limiter les tentatives de remboursement", minutes: 200, checks: "PENDING", author: "bob-acme"),
            ]),
            assigned: decode([
                work("acme/storefront", 477, "Le panier se vide après la connexion avec Apple", minutes: 22, issue: true, author: "alice-acme"),
            ])
        )
    }

    private enum Kind {
        case pullRequest(Int), issue(Int), other(String)
    }

    private static func item(_ id: String, _ repository: String, _ kind: Kind, _ title: String, reason: String, minutes: Double) -> GHNotification {
        let api = URL(string: "https://api.github.com/repos/\(repository)")!
        let (type, url): (String, URL?) = switch kind {
        case .pullRequest(let number): ("PullRequest", api.appending(path: "pulls/\(number)"))
        case .issue(let number): ("Issue", api.appending(path: "issues/\(number)"))
        case .other(let type): (type, nil)
        }
        return GHNotification(
            id: id,
            reason: reason,
            unread: true,
            updatedAt: .now.addingTimeInterval(-minutes * 60),
            lastReadAt: nil,
            subject: .init(title: title, url: url, latestCommentUrl: nil, type: type),
            repository: .init(fullName: repository, htmlUrl: URL(string: "https://github.com/\(repository)")!)
        )
    }

    /// Un résultat de la recherche GraphQL du tableau de bord : `WorkItem` ne se construit qu'en JSON.
    private static func work(
        _ repository: String, _ number: Int, _ title: String, minutes: Double, issue: Bool = false,
        draft: Bool = false, review: String? = nil, checks: String? = nil, author: String = "nihiloproxima"
    ) -> [String: Any] {
        var node: [String: Any] = [
            "id": "\(repository)#\(number)",
            "kind": issue ? "Issue" : "PullRequest",
            "number": number,
            "title": title,
            "url": "https://github.com/\(repository)/\(issue ? "issues" : "pull")/\(number)",
            "updatedAt": ISO8601DateFormatter().string(from: .now.addingTimeInterval(-minutes * 60)),
            "author": ["login": author],
            "repository": ["nameWithOwner": repository],
        ]
        if !issue { node["isDraft"] = draft }
        if let review { node["reviewDecision"] = review }
        if let checks { node["commits"] = ["nodes": [["commit": ["statusCheckRollup": ["state": checks]]]]] }
        return node
    }

    private static func decode(_ nodes: [[String: Any]]) -> [WorkItem] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try! decoder.decode([WorkItem].self, from: JSONSerialization.data(withJSONObject: nodes))
    }
}
