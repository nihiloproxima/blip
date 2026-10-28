import ServiceManagement
import SwiftUI

struct PopoverView: View {
    static let size = CGSize(width: 380, height: 580)

    let store: Store
    let close: () -> Void
    @State private var showingSettings = false
    @State private var searching = false
    @FocusState private var focus: PopoverFocus?

    var body: some View {
        Group {
            switch store.auth {
            case .checking:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .signedOut(let error):
                OnboardingView(store: store, error: error)
            case .signedIn:
                VStack(spacing: 0) {
                    HeaderView(store: store, showingSettings: $showingSettings)
                    Divider()
                    if showingSettings {
                        SettingsView(store: store, settings: store.settings)
                    } else {
                        TabBar(store: store) { openSearch() }
                        if searching || !store.searchText.isEmpty {
                            SearchField(text: Bindable(store).searchText, focus: $focus) { closeSearch() }
                        }
                        TabContent(store: store, focus: $focus, close: close).id(store.tab)
                    }
                    Divider()
                    if let release = store.updater.available {
                        UpdateBanner(updater: store.updater, release: release)
                        Divider()
                    }
                    FooterView(store: store)
                }
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .onKeyPress(.escape) {
            if searching || !store.searchText.isEmpty { closeSearch() } else { close() }
            return .handled
        }
    }

    private func openSearch() {
        showingSettings = false
        searching = true
        focus = .search
    }

    private func closeSearch() {
        store.searchText = ""
        searching = false
        focus = .list
    }
}

// MARK: - En-tête : le compagnon et sa progression

struct HeaderView: View {
    let store: Store
    @Binding var showingSettings: Bool
    @State private var blink = false
    @State private var hop = false
    @State private var openedAt = Date.now

    var body: some View {
        let game = store.game
        HStack(alignment: .top, spacing: 12) {
            PetView(mood: store.mood, level: game.level, alert: store.hasUrgent, blink: blink)
                .frame(width: 64, height: 64)
                .offset(y: hop ? -8 : 0)
                .help(Style.moodHelp(store.mood, urgent: store.hasUrgent))
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(store.settings.petName).font(.system(.headline, design: .rounded))
                    Chip("Niv. \(game.level)", color: .purple)
                        .help(xpHelp)
                    if game.currentStreak > 0 {
                        Chip("🔥 \(game.currentStreak)", color: .orange)
                            .help("Série d'inbox zero, en jours ouvrés")
                    }
                    Spacer()
                    if store.isLoading {
                        ProgressView().controlSize(.small).frame(width: 22, height: 22)
                    } else {
                        IconButton("arrow.clockwise", help: "Rafraîchir maintenant (Blip vérifie tout seul chaque minute)") { store.refreshAll() }
                    }
                    if store.tab == .notifications && !showingSettings {
                        let visible = store.filtered(store.notifications)
                        IconButton("checkmark.circle", help: store.repositoryFilter.map { "Tout marquer comme lu dans \(Style.shortName($0))" } ?? "Tout marquer comme lu") {
                            store.markRead(visible, bulk: true)
                        }
                        .disabled(visible.isEmpty)
                    }
                    IconButton(showingSettings ? "xmark" : "gearshape", help: showingSettings ? "Fermer les réglages" : "Réglages") { showingSettings.toggle() }
                }
                HStack(spacing: 8) {
                    XPBar(progress: game.levelProgress)
                    Text("\(game.xpToNextLevel) XP → \(game.level + 1)")
                        .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .overlay(alignment: .trailing) {
                            if let gain = game.lastGain, gain.date > openedAt {
                                XPFloater(gain: gain).id(gain.id)
                            }
                        }
                }
                .help(xpHelp)
                Group {
                    if let level = game.levelUp {
                        Text(levelUpText(level)).foregroundStyle(.purple).fontWeight(.bold)
                    } else if game.combo > 1 {
                        Text("COMBO x\(game.combo) !").foregroundStyle(.orange).fontWeight(.heavy)
                            .help("Trie la suivante en moins de 8 s pour monter le multiplicateur (jusqu'à x5)")
                    } else {
                        Text(Style.line(mood: store.mood, unread: store.notifications.count, urgent: store.hasUrgent))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 11, design: .rounded))
                .lineLimit(1)
            }
        }
        .padding(12)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 2.5...5)))
                blink = true
                try? await Task.sleep(for: .milliseconds(140))
                blink = false
            }
        }
        .task(id: game.levelUp) {
            guard game.levelUp != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            game.dismissLevelUp()
        }
        .onChange(of: game.lastGain) {
            withAnimation(.spring(duration: 0.15)) { hop = true }
            withAnimation(.spring(duration: 0.35, bounce: 0.5).delay(0.15)) { hop = false }
        }
    }

    private var xpHelp: String {
        let game = store.game
        return "\(game.xp) XP au total, encore \(game.xpToNextLevel) avant le niveau \(game.level + 1)"
    }

    private func levelUpText(_ level: Int) -> String {
        guard let accessory = Pet.accessories.first(where: { $0.level == level }) else { return "NIVEAU \(level) !" }
        return "NIVEAU \(level) ! \(store.settings.petName) a trouvé \(accessory.name) !"
    }
}

struct XPBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(LinearGradient(colors: [Color(rgb: 0x7EE2A8), Color(rgb: 0x8FD3FF)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, geometry.size.width * progress))
            }
        }
        .frame(height: 6)
        .animation(.spring(duration: 0.5), value: progress)
    }
}

/// « +30 » qui s'envole à chaque tri.
struct XPFloater: View {
    let gain: Game.Gain
    @State private var flying = false

    var body: some View {
        Text("+\(gain.xp)")
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .foregroundStyle(gain.combo > 1 ? .orange : .green)
            .fixedSize()
            .offset(y: flying ? -26 : -8)
            .opacity(flying ? 0 : 1)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeOut(duration: 1)) { flying = true }
            }
    }
}

struct Chip: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.16), in: Capsule())
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    init(_ symbol: String, help: String, action: @escaping () -> Void) {
        self.symbol = symbol
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

// MARK: - Inbox zero : l'écran des scores

struct InboxZeroView: View {
    let game: Game
    let petName: String

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            VStack(spacing: 6) {
                Text("✨ Inbox zero ✨").font(.system(.title2, design: .rounded, weight: .heavy))
                Text("\(petName) digère tranquillement.").foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Score(value: "\(game.cleared)", label: "triées")
                    .help("Notifications triées depuis le début")
                Score(value: "x\(game.bestCombo)", label: "meilleur combo")
                    .help("Ton plus long enchaînement de tris à moins de 8 s d'écart")
                Score(value: "\(game.currentStreak) j", label: "série")
                    .help("Jours ouvrés d'affilée avec un inbox zero (les week-ends ne cassent pas la série)")
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private struct Score: View {
        let value: String
        let label: String

        var body: some View {
            VStack(spacing: 2) {
                Text(value).font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit())
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 96, height: 58)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

struct FooterView: View {
    let store: Store

    var body: some View {
        HStack(spacing: 6) {
            if let error = store.error {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(error).lineLimit(1).truncationMode(.tail).help(error)
            } else {
                if let lastSync = store.lastSync {
                    Text("À jour · \(lastSync.formatted(date: .omitted, time: .shortened))")
                        .help("Dernière synchro avec GitHub. Blip vérifie chaque minute, et à chaque ouverture.")
                }
                Spacer()
                Text(store.tab == .notifications ? "↑↓  ↩ ouvrir  ⌘↩ en fond  E lu  M muet" : "↑↓  ↩ ouvrir  ⌘↩ en fond  ⌘1-5 onglets")
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

/// Une nouvelle release est sortie : on propose de l'installer.
struct UpdateBanner: View {
    let updater: Updater
    let release: Updater.Release

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").foregroundStyle(.purple)
            switch updater.phase {
            case .idle:
                Text("Blip \(release.version) est disponible")
                Link("Nouveautés", destination: release.page)
                Spacer()
                if updater.canInstall {
                    Button("Installer et relancer", action: updater.install)
                } else {
                    Link("Télécharger", destination: release.page)
                }
            case .installing:
                Text("Installation de Blip \(release.version)…")
                Spacer()
                ProgressView().controlSize(.small)
            case .failed(let message):
                Text(message).foregroundStyle(.red).lineLimit(2).help(message)
                Spacer()
                Button("Réessayer", action: updater.install)
            }
        }
        .font(.system(size: 11))
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.purple.opacity(0.08))
    }
}

// MARK: - Réglages

struct SettingsView: View {
    let store: Store
    @Bindable var settings: Settings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?

    var body: some View {
        let game = store.game
        Form {
            Section("Compagnon") {
                TextField("Nom", text: $settings.petName)
                    .help("Le nom de ton compagnon")
                LabeledContent("Progression", value: "Niv. \(game.level) · \(game.xp) XP")
                LabeledContent("Notifications triées", value: "\(game.cleared)")
                LabeledContent("Meilleur combo", value: "x\(game.bestCombo)")
                if let next = Pet.accessories.first(where: { $0.level > game.level }) {
                    LabeledContent("Prochain objet", value: "\(next.name), niv. \(next.level)")
                }
            }
            Section("Notifications") {
                Toggle("Seulement celles qui me concernent", isOn: $settings.participatingOnly)
                    .help("Masque les fils de dépôts suivis où tu n'es ni mentionné, ni assigné, ni sollicité, ni participant")
                Toggle("Archiver (« Terminé ») plutôt que marquer lu", isOn: $settings.markAsDone)
                    .help("Le fil quitte aussi ta boîte de réception sur github.com. GitHub ne le renvoie plus dans l'historique.")
                Toggle("Bannières macOS", isOn: $settings.systemNotifications)
                    .help("Une bannière à chaque nouvelle notification ; un clic l'ouvre sur GitHub")
                Toggle("Sons", isOn: $settings.sounds)
                    .help("Petits sons quand tu tries, montes de niveau ou atteins l'inbox zero")
            }
            VisibilitySection(settings: settings, repositories: store.knownRepositories)
            Section("Système") {
                Toggle("Lancer à l'ouverture de session", isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) }))
                    .help("Démarre Blip automatiquement quand tu ouvres ta session macOS")
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.red)
                }
                LabeledContent("Version", value: versionStatus)
                Button("Rechercher une mise à jour") { Task { await store.updater.check() } }
            }
            Section("Compte") {
                LabeledContent("GitHub", value: settings.login.map { "@\($0)" } ?? "—")
                LabeledContent("Token", value: settings.tokenSource == .githubCLI ? "GitHub CLI" : "Trousseau")
                Button("Se déconnecter", role: .destructive) { store.signOut() }
                    .help(settings.tokenSource == .githubCLI
                        ? "Blip oublie ton compte ; GitHub CLI reste connecté"
                        : "Blip oublie ton compte et supprime le token du trousseau")
                Button("Quitter Blip") { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.participatingOnly) {
            Task { await store.refresh(force: true) }
        }
        .onChange(of: settings.systemNotifications) {
            if settings.systemNotifications { store.requestNotificationPermission() }
        }
    }

    private var versionStatus: String {
        let version = Updater.version ?? "dev"
        if let release = store.updater.available { return "\(version) · \(release.version) disponible" }
        return store.updater.checkedAt == nil ? version : "\(version) · à jour"
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            launchError = nil
        } catch {
            launchError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// Réglages fins de ce que Blip affiche : organisations, dépôts, raisons et types de sujets.
/// Tout est visible par défaut ; chaque interrupteur ajoute ou retire une exclusion.
struct VisibilitySection: View {
    @Bindable var settings: Settings
    /// Dépôts croisés jusqu'ici, plus ceux déjà masqués.
    let repositories: [String]

    var body: some View {
        Section {
            DisclosureGroup {
                ForEach(owners, id: \.self) { owner in
                    Toggle(isOn: visibility(\.hiddenOwners, owner)) {
                        Text("\(owner), tous ses dépôts").fontWeight(.semibold)
                    }
                    .help("Masque tous les dépôts de \(owner), y compris ceux qui apparaîtront plus tard")
                    ForEach(repositories.filter { Settings.owner(of: $0) == owner }, id: \.self) { repository in
                        Toggle(Style.shortName(repository), isOn: visibility(\.hiddenRepositories, repository))
                            .padding(.leading, 16)
                            .disabled(settings.hiddenOwners.contains(owner))
                    }
                }
            } label: {
                LabeledContent("Dépôts", value: summary(settings.hiddenOwners.count + settings.hiddenRepositories.count))
            }
            DisclosureGroup {
                ForEach(Style.filterableReasons, id: \.self) { reason in
                    Toggle(Style.reasonLabel(reason), isOn: visibility(\.hiddenReasons, reason))
                        .help(Style.reasonHelp(reason))
                }
            } label: {
                LabeledContent("Raisons", value: summary(settings.hiddenReasons.count, feminine: true))
            }
            .help("Pourquoi GitHub t'envoie la notification : review, mention, abonnement…")
            DisclosureGroup {
                ForEach(Style.subjectKinds, id: \.kind) { subject in
                    Toggle(subject.label, isOn: visibility(\.hiddenSubjects, subject.kind))
                }
            } label: {
                LabeledContent("Sujets", value: summary(settings.hiddenSubjects.count))
            }
            .help("Sur quoi porte la notification : PR, issue, release…")
            if settings.hidesSomething {
                Button("Tout réafficher") { settings.showAll() }
            }
        } header: {
            Text("Ce que Blip affiche")
        } footer: {
            Text("Ce qui est masqué disparaît partout dans Blip : liste, compteur, humeur, bannières et tableau de bord. Rien ne change sur GitHub.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var owners: [String] {
        Set(repositories.map { Settings.owner(of: $0) }).union(settings.hiddenOwners)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func summary(_ hidden: Int, feminine: Bool = false) -> String {
        hidden == 0 ? "Tout est visible" : "\(hidden) masqué\(feminine ? "e" : "")\(hidden > 1 ? "s" : "")"
    }

    /// Interrupteur « visible » adossé à un ensemble d'exclusions.
    private func visibility(_ hidden: ReferenceWritableKeyPath<Settings, Set<String>>, _ value: String) -> Binding<Bool> {
        Binding(
            get: { !settings[keyPath: hidden].contains(value) },
            set: { visible in
                if visible {
                    settings[keyPath: hidden].remove(value)
                } else {
                    settings[keyPath: hidden].insert(value)
                }
            }
        )
    }
}

// MARK: - Connexion

struct OnboardingView: View {
    let store: Store
    let error: String?
    @State private var token = ""

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            PetView(mood: .happy, level: 1).frame(width: 96, height: 96)
            Text("Salut, moi c'est \(store.settings.petName) !")
                .font(.system(.title3, design: .rounded, weight: .bold))
            Text("Je me nourris de tes notifications GitHub. Trie-les vite pour enchaîner les combos et me faire grandir.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if Credentials.ghPath != nil {
                Button {
                    Task { await store.connectWithGitHubCLI() }
                } label: {
                    Label("Utiliser mon compte GitHub CLI", systemImage: "terminal").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .help("Blip relit `gh auth token` à chaque lancement : aucun token n'est stocké")
                Text("ou avec un token").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                SecureField("ghp_…", text: $token)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(connect)
                    .help("Token classic avec les scopes notifications et repo, rangé dans le trousseau macOS")
                Button("Connecter", action: connect).disabled(token.isEmpty)
            }
            Link("Créer un token classic (scopes notifications et repo)", destination: URL(string: "https://github.com/settings/tokens/new?scopes=notifications,repo&description=Blip")!)
                .font(.caption)
            if store.isLoading {
                ProgressView().controlSize(.small)
            } else if let error {
                Text(error).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            Spacer()
            Button("Quitter") { NSApp.terminate(nil) }
                .buttonStyle(.link)
                .font(.caption)
        }
        .padding(24)
    }

    private func connect() {
        let token = token
        Task { await store.connect(token: token, source: .keychain) }
    }
}
