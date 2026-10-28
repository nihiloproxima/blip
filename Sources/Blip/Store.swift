import AppKit
import Observation
import SwiftUI

/// Une section de liste : un dépôt, ou tout à plat quand `repository` est nil.
struct ItemSection<Item: Listable>: Identifiable {
    let repository: String?
    let items: [Item]
    var id: String { repository ?? "" }
}

/// État de l'app : connexion, notifications, tableau de bord, polling et actions de tri.
@MainActor @Observable
final class Store {
    enum Auth: Equatable {
        case checking
        case signedOut(String?)
        case signedIn
    }

    enum Tab: Int, CaseIterable, Identifiable {
        case notifications, mine, reviews, assigned, history

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .notifications: "Notifs"
            case .mine: "Mes PR"
            case .reviews: "Reviews"
            case .assigned: "Assignées"
            case .history: "Historique"
            }
        }

        var symbol: String {
            switch self {
            case .notifications: "bell"
            case .mine: "arrow.triangle.pull"
            case .reviews: "eye"
            case .assigned: "person.crop.circle"
            case .history: "clock.arrow.circlepath"
            }
        }

        var help: String {
            switch self {
            case .notifications: "Notifications non lues"
            case .mine: "Mes PR ouvertes"
            case .reviews: "Les reviews qu'on attend de moi"
            case .assigned: "Issues et PR qui me sont assignées"
            case .history: "Notifications déjà lues ou archivées"
            }
        }
    }

    private(set) var auth = Auth.checking
    /// Toutes les notifications non lues renvoyées par GitHub, y compris celles masquées dans les réglages.
    private var inbox: [GHNotification] = []
    /// nil tant que le tableau de bord n'a pas été chargé.
    private var fetchedWork: Work?
    private(set) var states: [String: SubjectState] = [:]
    /// CI des PR encore ouvertes, par notification.
    private(set) var checks: [String: String] = [:]
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var lastSync: Date?
    /// Du nouveau depuis la dernière ouverture du popover : l'icône passe en couleur.
    private(set) var hasNews = false
    /// Appelé à chaque arrivée de notifications, pour faire sauter l'icône.
    @ObservationIgnored var onNews: (() -> Void)?
    /// Onglet et filtre survivent à la fermeture du popover, pas au redémarrage.
    var tab = Tab.notifications {
        didSet { if tab == .history { Task { await refreshHistory() } } }
    }
    var repositoryFilter: String?
    /// Recherche (⌘F), combinée au filtre de dépôt ; remise à zéro à chaque ouverture du popover.
    var searchText = ""

    let game = Game()
    let settings = Settings()
    let updater = Updater()

    /// Notifications lues renvoyées par GitHub.
    private var readOnGitHub: [GHNotification] = []
    /// Triées depuis le lancement, visibles tout de suite dans l'historique (même archivées).
    private var recentlyCleared: [GHNotification] = []

    @ObservationIgnored private let notifier = Notifier()
    @ObservationIgnored private var client: GitHub?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var pollInterval = 60
    @ObservationIgnored private var lastModified: String?
    @ObservationIgnored private var lastFullFetch = Date.distantPast
    @ObservationIgnored private var workFetchedAt = Date.distantPast
    @ObservationIgnored private var historyFetchedAt = Date.distantPast
    /// `updatedAt` des fils déjà affichés, pour repérer les nouveautés (nil avant le premier chargement).
    @ObservationIgnored private var seen: [String: Date]?
    /// Fils triés localement que l'API peut encore renvoyer quelques secondes.
    @ObservationIgnored private var pending: [String: Date] = [:]
    @ObservationIgnored private var clearedAt: [String: Date] = [:]
    @ObservationIgnored private var stateStamps: [String: Date] = [:]

    init() {
        notifier.onOpen = { [weak self] id in
            guard let self, let item = notifications.first(where: { $0.id == id }) else { return }
            open(item)
        }
    }

    /// Ce que Blip montre (liste, compteur, humeur, bannières) : l'inbox moins ce qui est masqué dans les réglages.
    var notifications: [GHNotification] { inbox.filter { settings.shows($0) } }

    /// Le tableau de bord, sans les dépôts masqués.
    var work: Work? {
        fetchedWork.map { work in
            Work(
                mine: work.mine.filter { settings.shows(repository: $0.repositoryName) },
                reviews: work.reviews.filter { settings.shows(repository: $0.repositoryName) },
                assigned: work.assigned.filter { settings.shows(repository: $0.repositoryName) }
            )
        }
    }

    /// Dépôts croisés jusqu'ici, plus ceux masqués : ce que les réglages proposent de filtrer.
    var knownRepositories: [String] {
        var names = Set(settings.hiddenRepositories)
        names.formUnion((inbox + readOnGitHub + recentlyCleared).map(\.repositoryName))
        if let fetchedWork { names.formUnion((fetchedWork.mine + fetchedWork.reviews + fetchedWork.assigned).map(\.repositoryName)) }
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var mood: Mood { Mood(unread: notifications.count) }

    /// Quelqu'un attend une action : review demandée, mention, assignation…
    var hasUrgent: Bool {
        notifications.contains { Game.isUrgent($0.reason) } || !(work?.reviews.isEmpty ?? true)
    }

    /// Historique : ce qui a été lu ou archivé, le plus récemment lu en premier.
    var history: [GHNotification] {
        let unread = Set(inbox.map(\.id))
        var seen = Set<String>()
        return (recentlyCleared + readOnGitHub)
            .filter { !unread.contains($0.id) && settings.shows($0) && seen.insert($0.id).inserted }
            .sorted { readDate($0) > readDate($1) }
    }

    func readDate(_ item: GHNotification) -> Date {
        clearedAt[item.id] ?? item.lastReadAt ?? item.updatedAt
    }

    // MARK: - Filtre et regroupement

    /// Ce qui correspond à la recherche : chaque mot doit apparaître (casse et accents ignorés).
    func searched<Item: Listable>(_ items: [Item]) -> [Item] {
        let words = searchText.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return items }
        return items.filter { item in words.allSatisfy { item.searchableText.localizedStandardContains($0) } }
    }

    /// Recherche et filtre de dépôt : ce qui est affiché, et ce sur quoi agit « tout marquer comme lu ».
    func filtered<Item: Listable>(_ items: [Item]) -> [Item] {
        let matching = searched(items)
        guard let repositoryFilter else { return matching }
        return matching.filter { $0.repositoryName == repositoryFilter }
    }

    /// Groupé par dépôt dans l'ordre de la liste (donc le plus récent d'abord), ou une seule section à plat.
    func sections<Item: Listable>(_ items: [Item]) -> [ItemSection<Item>] {
        let visible = filtered(items)
        guard settings.groupByRepository else { return [ItemSection(repository: nil, items: visible)] }
        var order: [String] = []
        var groups: [String: [Item]] = [:]
        for item in visible {
            if groups[item.repositoryName] == nil { order.append(item.repositoryName) }
            groups[item.repositoryName, default: []].append(item)
        }
        return order.map { ItemSection(repository: $0, items: groups[$0]!) }
    }

    /// Dépôts d'une liste, du plus chargé au moins chargé ; le filtre actif reste toujours visible.
    func repositories<Item: Listable>(in items: [Item]) -> [(name: String, count: Int)] {
        var counts = Dictionary(items.map { ($0.repositoryName, 1) }, uniquingKeysWith: +)
        if let repositoryFilter, counts[repositoryFilter] == nil { counts[repositoryFilter] = 0 }
        return counts
            .map { (name: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
    }

    /// Compteur affiché sur un onglet, filtre compris (nil : rien à afficher).
    func count(_ tab: Tab) -> Int? {
        switch tab {
        case .notifications: filtered(notifications).count
        case .mine: work.map { filtered($0.mine).count }
        case .reviews: work.map { filtered($0.reviews).count }
        case .assigned: work.map { filtered($0.assigned).count }
        case .history: nil
        }
    }

    // MARK: - Connexion

    func start() async {
        if let count = Demo.count {
            inbox = Array(Demo.notifications.prefix(count))
            states = Demo.states
            fetchedWork = Demo.work
            lastSync = .now
            auth = .signedIn
            return
        }
        switch settings.tokenSource {
        case .githubCLI:
            if let token = await Credentials.ghToken() { begin(token) } else { auth = .signedOut("GitHub CLI n'a pas renvoyé de token. Lance `gh auth login`.") }
        case .keychain:
            if let token = Credentials.keychainToken() { begin(token) } else { auth = .signedOut(nil) }
        case nil:
            auth = .signedOut(nil)
        }
    }

    func connectWithGitHubCLI() async {
        guard let token = await Credentials.ghToken() else {
            auth = .signedOut("GitHub CLI n'a pas renvoyé de token. Lance `gh auth login`.")
            return
        }
        await connect(token: token, source: .githubCLI)
    }

    func connect(token: String, source: TokenSource) async {
        let client = GitHub(token: token.trimmingCharacters(in: .whitespacesAndNewlines))
        isLoading = true
        defer { isLoading = false }
        do {
            settings.login = try await client.login()
            if source == .keychain { try Credentials.saveToKeychain(client.token) }
            settings.tokenSource = source
            begin(client.token)
        } catch {
            auth = .signedOut(error.localizedDescription)
        }
    }

    func signOut(_ reason: String? = nil) {
        pollTask?.cancel()
        client = nil
        if settings.tokenSource == .keychain { Credentials.deleteFromKeychain() }
        settings.tokenSource = nil
        inbox = []
        fetchedWork = nil
        readOnGitHub = []
        recentlyCleared = []
        states = [:]
        checks = [:]
        stateStamps = [:]
        seen = nil
        pending = [:]
        lastModified = nil
        workFetchedAt = .distantPast
        historyFetchedAt = .distantPast
        repositoryFilter = nil
        searchText = ""
        tab = .notifications
        error = nil
        auth = .signedOut(reason)
    }

    private func begin(_ token: String) {
        client = GitHub(token: token)
        auth = .signedIn
        if settings.systemNotifications { requestNotificationPermission() }
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled, let self {
                await refresh()
                await refreshWork(maxAge: 300)
                try? await Task.sleep(for: .seconds(pollInterval))
            }
        }
    }

    func requestNotificationPermission() {
        notifier.requestPermission()
    }

    // MARK: - Synchronisation

    /// À l'ouverture du popover, tout ce qui est visible est remis à jour.
    func popoverOpened() {
        hasNews = false
        searchText = ""
        Task { await refresh(force: true) }
        Task { await refreshWork() }
        if tab == .history { Task { await refreshHistory() } }
    }

    func refreshAll() {
        Task { await refresh(force: true) }
        Task { await refreshWork(maxAge: 0) }
        if tab == .history { Task { await refreshHistory(maxAge: 0) } }
    }

    /// `force` ignore le cache 304 ; sinon on refait quand même une liste complète toutes les 5 min,
    /// au cas où des fils auraient été lus ailleurs sans changer `Last-Modified`.
    func refresh(force: Bool = false) async {
        guard let client, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let full = force || Date.now.timeIntervalSince(lastFullFetch) > 300
        do {
            switch try await client.notifications(participating: settings.participatingOnly, ifModifiedSince: full ? nil : lastModified) {
            case .notModified(let interval):
                pollInterval = interval
            case .updated(let items, let lastModified, let interval):
                pollInterval = interval
                self.lastModified = lastModified
                lastFullFetch = .now
                apply(items)
            }
            error = nil
            lastSync = .now
        } catch GitHubError.unauthorized {
            // Le token de `gh` a pu être renouvelé entre-temps.
            if settings.tokenSource == .githubCLI, let token = await Credentials.ghToken(), token != client.token {
                self.client = GitHub(token: token)
            } else {
                signOut("GitHub a refusé le token, reconnecte-toi.")
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Mes PR, reviews demandées et assignations : une requête GraphQL, au plus une fois par `maxAge`.
    func refreshWork(maxAge: TimeInterval = 60) async {
        guard let client, Date.now.timeIntervalSince(workFetchedAt) >= maxAge else { return }
        workFetchedAt = .now
        do {
            fetchedWork = try await client.work()
        } catch {
            workFetchedAt = .distantPast
            self.error = "Tableau de bord : \(error.localizedDescription)"
        }
    }

    /// Les 100 dernières notifications lues côté GitHub (les fils archivés n'y sont plus).
    func refreshHistory(maxAge: TimeInterval = 60) async {
        guard let client, Date.now.timeIntervalSince(historyFetchedAt) >= maxAge else { return }
        historyFetchedAt = .now
        do {
            if case .updated(let items, _, _) = try await client.notifications(all: true, participating: settings.participatingOnly, maxPages: 2) {
                readOnGitHub = items.filter { !$0.unread }
                await loadStates(for: readOnGitHub)
            }
        } catch {
            historyFetchedAt = .distantPast
            self.error = "Historique : \(error.localizedDescription)"
        }
    }

    private func apply(_ items: [GHNotification]) {
        let ids = Set(items.map(\.id))
        pending = pending.filter { ids.contains($0.key) }
        let unread = items.filter { item in pending[item.id].map { item.updatedAt > $0 } ?? true }

        if let seen {
            let fresh = unread.filter { item in settings.shows(item) && (seen[item.id].map { item.updatedAt > $0 } ?? true) }
            if !fresh.isEmpty {
                if settings.systemNotifications { notifier.post(fresh) }
                hasNews = true
                onNews?()
            }
        }
        seen = Dictionary(unread.map { ($0.id, $0.updatedAt) }, uniquingKeysWith: { first, _ in first })

        withAnimation(.snappy) { inbox = unread }
        if notifications.isEmpty { _ = game.reachInboxZero() }
        Task { await loadStates(for: unread) }
    }

    /// État des PR / issues et CI des PR. Un fil fermé ou mergé ne bouge plus : il n'est redemandé
    /// que s'il a une nouvelle activité. Un fil ouvert l'est à chaque synchro complète, car sa CI
    /// peut changer sans que la notification soit mise à jour.
    private func loadStates(for items: [GHNotification]) async {
        guard let client else { return }
        let stale = items.filter { $0.number != nil && stateStamps[$0.id] != $0.updatedAt }
        guard !stale.isEmpty, let result = try? await client.subjects(of: stale) else { return }
        for item in stale {
            let info = result[item.id]
            if info?.state.isOpen != true { stateStamps[item.id] = item.updatedAt }
            states[item.id] = info?.state ?? states[item.id]
            checks[item.id] = info?.state.isOpen == true ? info?.checks : nil
        }
    }

    // MARK: - Ouverture et tri

    /// Ouvre le fil dans le navigateur ; s'il était non lu, il est marqué lu (et rapporte de l'XP).
    /// En arrière-plan (⌘), le navigateur ne passe pas devant : pratique pour enchaîner.
    func open(_ item: GHNotification, inBackground: Bool = false) {
        guard let client else { return }
        browse(inBackground) { await client.webURL(for: item) }
        if inbox.contains(where: { $0.id == item.id }) { clear([item]) }
    }

    func open(_ item: WorkItem, inBackground: Bool = false) {
        browse(inBackground) { item.url }
    }

    func markRead(_ items: [GHNotification], bulk: Bool = false) {
        clear(items, bulk: bulk)
    }

    /// Se désabonne du fil : plus aucune notification pour cette PR / issue.
    func mute(_ item: GHNotification) {
        clear([item], unsubscribe: true)
    }

    private func browse(_ inBackground: Bool, _ url: @escaping @Sendable () async -> URL) {
        Task {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = !inBackground
            _ = try? await NSWorkspace.shared.open(await url(), configuration: configuration)
        }
    }

    private func clear(_ items: [GHNotification], bulk: Bool = false, unsubscribe: Bool = false) {
        guard let client, !items.isEmpty else { return }
        let ids = Set(items.map(\.id))
        for item in items {
            pending[item.id] = item.updatedAt
            clearedAt[item.id] = .now
        }
        recentlyCleared = Array((items + recentlyCleared.filter { !ids.contains($0.id) }).prefix(50))
        withAnimation(.snappy) { inbox.removeAll { ids.contains($0.id) } }

        let leveledUp = game.award(items.map(\.reason), bulk: bulk)
        if notifications.isEmpty, game.reachInboxZero() {
            play("Purr")
        } else if leveledUp {
            play("Hero")
        } else {
            play(game.combo >= 3 ? "Glass" : "Pop")
        }

        let done = settings.markAsDone
        Task {
            do {
                // Par paquets de 8 pour rester poli avec l'API.
                let all = Array(ids)
                for start in stride(from: 0, to: all.count, by: 8) {
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        for id in all[start..<min(start + 8, all.count)] {
                            group.addTask {
                                if unsubscribe { try await client.unsubscribe(id) }
                                if done { try await client.markDone(id) } else { try await client.markRead(id) }
                            }
                        }
                        try await group.waitForAll()
                    }
                }
            } catch {
                for id in ids { pending[id] = nil }
                await refresh(force: true)
                self.error = "Synchro GitHub ratée : \(error.localizedDescription)"
            }
        }
    }

    private func play(_ sound: String) {
        guard settings.sounds else { return }
        (NSSound(named: sound)?.copy() as? NSSound)?.play()
    }
}

// MARK: - Recherche

extension GHNotification {
    var searchableText: String {
        [subject.title, repository.fullName, number.map { "#\($0)" }, Style.reasonLabel(reason), Style.describe(type: subject.type, state: nil)]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}

extension WorkItem {
    var searchableText: String {
        [title, repositoryName, "#\(number)", author.map { "@\($0.login)" }, Style.status(of: self)?.label]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}
