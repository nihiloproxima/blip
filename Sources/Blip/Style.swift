import SwiftUI

/// Icônes, couleurs et libellés partagés par l'UI et les bannières.
enum Style {
    static func icon(for type: String, state: SubjectState?) -> String {
        switch (type, state) {
        case ("PullRequest", .merged): "arrow.triangle.merge"
        case ("PullRequest", _): "arrow.triangle.pull"
        case ("Issue", .closed): "checkmark.circle"
        case ("Issue", .notPlanned): "circle.slash"
        case ("Issue", _): "smallcircle.filled.circle"
        case ("Release", _): "tag"
        case ("Discussion", _): "bubble.left.and.bubble.right"
        case ("Commit", _): "text.bubble"
        case ("CheckSuite", _), ("WorkflowRun", _): "bolt.circle"
        case ("RepositoryVulnerabilityAlert", _), ("RepositoryDependabotAlertsThread", _): "exclamationmark.shield"
        case ("RepositoryInvitation", _): "envelope"
        default: "bell"
        }
    }

    /// Couleurs de GitHub pour l'état d'une PR / issue.
    static func color(for state: SubjectState?) -> Color {
        switch state {
        case .open: Color(rgb: 0x2DA44E)
        case .merged: Color(rgb: 0x8250DF)
        case .closed: Color(rgb: 0xCF222E)
        case .draft, .notPlanned: .secondary
        case nil: .secondary
        }
    }

    static func icon(for item: WorkItem) -> String {
        item.isPullRequest ? "arrow.triangle.pull" : "smallcircle.filled.circle"
    }

    static func color(for item: WorkItem) -> Color {
        color(for: item.isDraft == true ? .draft : .open)
    }

    /// Où en est la PR : brouillon, ou décision de review.
    static func status(of item: WorkItem) -> (label: String, color: Color, help: String)? {
        if item.isDraft == true { return ("Brouillon", .secondary, "PR en brouillon, pas encore prête pour la review") }
        return switch item.reviewDecision {
        case "APPROVED": ("Approuvée", Color(rgb: 0x2DA44E), "Review approuvée, prête à merger")
        case "CHANGES_REQUESTED": ("Modifs demandées", .orange, "Un reviewer demande des changements")
        case "REVIEW_REQUIRED": ("Review requise", .secondary, "En attente d'une review approuvée")
        default: nil
        }
    }

    /// « PR mergée », « Issue fermée »… pour l'infobulle de l'icône.
    static func describe(type: String, state: SubjectState?) -> String {
        let kind = switch type {
        case "PullRequest": "PR"
        case "Issue": "Issue"
        case "Release": "Release"
        case "Discussion": "Discussion"
        case "Commit": "Commentaire de commit"
        case "CheckSuite", "WorkflowRun": "GitHub Actions"
        case "RepositoryVulnerabilityAlert", "RepositoryDependabotAlertsThread": "Alerte Dependabot"
        case "RepositoryInvitation": "Invitation à un dépôt"
        default: type
        }
        guard type == "PullRequest" || type == "Issue", let state else { return kind }
        let status = switch state {
        case .open: "ouverte"
        case .draft: "en brouillon"
        case .merged: "mergée"
        case .closed: type == "Issue" ? "terminée" : "fermée sans merge"
        case .notPlanned: "fermée, non prévue"
        }
        return "\(kind) \(status)"
    }

    static func describe(_ item: WorkItem) -> String {
        describe(type: item.kind, state: item.isDraft == true ? .draft : .open)
    }

    static func checks(_ state: String?) -> (symbol: String, color: Color, help: String)? {
        switch state {
        case "SUCCESS": ("checkmark.circle.fill", Color(rgb: 0x2DA44E), "CI au vert")
        case "FAILURE", "ERROR": ("xmark.circle.fill", Color(rgb: 0xCF222E), "CI en échec")
        case "PENDING", "EXPECTED": ("hourglass", .orange, "CI en cours")
        default: nil
        }
    }

    /// `owner/repo` → `repo`, pour les puces et les listes à plat.
    static func shortName(_ repository: String) -> String {
        repository.split(separator: "/").last.map(String.init) ?? repository
    }

    static func reasonLabel(_ reason: String) -> String {
        switch reason {
        case "review_requested": "Review demandée"
        case "mention": "Mentionné"
        case "team_mention": "Équipe mentionnée"
        case "assign": "Assigné"
        case "author": "Auteur"
        case "comment": "Commentaire"
        case "state_change": "Changement d'état"
        case "ci_activity": "CI"
        case "subscribed": "Abonné"
        case "manual": "Suivi"
        case "security_alert": "Alerte sécurité"
        case "invitation": "Invitation"
        case "approval_requested": "Approbation demandée"
        default: reason.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// Raisons proposées dans les filtres des réglages, des plus urgentes aux plus passives.
    static let filterableReasons = [
        "review_requested", "mention", "team_mention", "assign", "approval_requested", "security_alert",
        "author", "comment", "state_change", "ci_activity", "subscribed", "manual", "invitation",
    ]

    /// Familles de sujets proposées dans les filtres (voir `GHNotification.subjectKind`).
    static let subjectKinds: [(kind: String, label: String)] = [
        ("PullRequest", "Pull requests"), ("Issue", "Issues"), ("Discussion", "Discussions"),
        ("Release", "Releases"), ("Commit", "Commits"), ("Actions", "GitHub Actions"), ("Security", "Alertes de sécurité"),
    ]

    /// Pourquoi GitHub t'envoie cette notification.
    static func reasonHelp(_ reason: String) -> String {
        switch reason {
        case "review_requested": "On te demande une review"
        case "mention": "Quelqu'un t'a mentionné avec @"
        case "team_mention": "Une de tes équipes a été mentionnée"
        case "assign": "On t'a assigné ce fil"
        case "author": "Tu as créé ce fil"
        case "comment": "Tu as commenté ce fil"
        case "state_change": "Tu as changé l'état de ce fil"
        case "ci_activity": "Un workflow GitHub Actions que tu as lancé est terminé"
        case "subscribed": "Tu suis ce dépôt"
        case "manual": "Tu t'es abonné à ce fil"
        case "security_alert": "Une vulnérabilité a été détectée dans ce dépôt"
        case "invitation": "On t'invite à contribuer à ce dépôt"
        case "approval_requested": "Un déploiement attend ton approbation"
        default: reasonLabel(reason)
        }
    }

    /// Ce que l'humeur du compagnon veut dire.
    static func moodHelp(_ mood: Mood, urgent: Bool) -> String {
        let meaning = switch mood {
        case .zen: "Zen : inbox zero"
        case .happy: "Content : moins de 5 notifications"
        case .worried: "Inquiet : 5 notifications ou plus"
        case .panic: "Panique : 15 notifications ou plus"
        }
        return urgent ? meaning + "\n! : quelqu'un attend une action de ta part" : meaning
    }

    static func reasonColor(_ reason: String) -> Color {
        switch reason {
        case "review_requested", "approval_requested": .purple
        case "mention", "team_mention": .blue
        case "assign": .orange
        case "security_alert": .red
        default: .secondary
        }
    }

    /// « maintenant », « 12 min », « 3 h », « 2 j », puis la date.
    static func age(of date: Date, now: Date = .now) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        return switch seconds {
        case ..<60: "maintenant"
        case ..<3600: "\(seconds / 60) min"
        case ..<86_400: "\(seconds / 3600) h"
        case ..<(7 * 86_400): "\(seconds / 86_400) j"
        default: date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_FR")))
        }
    }

    /// Réplique du compagnon selon l'état de la boîte.
    static func line(mood: Mood, unread: Int, urgent: Bool) -> String {
        if urgent { return "Quelqu'un t'attend, on y va ?" }
        return switch mood {
        case .zen: "Inbox zero. Je fais la sieste."
        case .happy: "Quelques miettes à grignoter."
        case .worried: "\(unread) notifs… ça commence à faire beaucoup."
        case .panic: "AU SECOURS, \(unread) notifs !"
        }
    }
}
