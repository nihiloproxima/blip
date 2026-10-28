import SwiftUI

// MARK: - Onglets

struct TabBar: View {
    let store: Store

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Store.Tab.allCases) { tab in
                TabButton(tab: tab, selected: store.tab == tab, count: store.count(tab)) {
                    withAnimation(.snappy(duration: 0.2)) { store.tab = tab }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

/// Icône + compteur ; l'onglet actif affiche aussi son nom.
private struct TabButton: View {
    let tab: Store.Tab
    let selected: Bool
    let count: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: tab.symbol)
                if selected {
                    Text(tab.title).fontWeight(.semibold)
                }
                if let count, count > 0 {
                    Text("\(count)")
                        .monospacedDigit()
                        .foregroundStyle(tab == .reviews ? Color.orange : Color.secondary)
                }
            }
            .font(.system(size: 11.5))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(selected ? Color.primary.opacity(0.09) : Color.clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(Character("\(tab.rawValue + 1)")), modifiers: .command)
        .help("\(tab.help) (⌘\(tab.rawValue + 1))")
    }
}

/// Le contenu de l'onglet actif.
struct TabContent: View {
    let store: Store
    let close: () -> Void

    var body: some View {
        switch store.tab {
        case .notifications:
            ItemList(
                store: store,
                items: store.notifications,
                open: { open($0, inBackground: $1) },
                clear: { store.markRead([$0]) },
                mute: { store.mute($0) },
                clearSection: { store.markRead($0, bulk: true) }
            ) { item, selected in
                NotificationRow(
                    item: item,
                    state: store.states[item.id],
                    selected: selected,
                    showRepository: !store.settings.groupByRepository,
                    read: { store.markRead([item]) },
                    mute: { store.mute(item) }
                )
            } empty: {
                InboxZeroView(game: store.game, petName: store.settings.petName)
            }
        case .history:
            ItemList(store: store, items: store.history, open: { open($0, inBackground: $1) }) { item, selected in
                NotificationRow(
                    item: item,
                    state: store.states[item.id],
                    selected: selected,
                    showRepository: !store.settings.groupByRepository,
                    readAt: store.readDate(item)
                )
            } empty: {
                EmptyState(symbol: "clock.arrow.circlepath", title: "Rien de lu récemment")
            }
        case .mine, .reviews, .assigned:
            ItemList(store: store, items: workItems, open: { open($0, inBackground: $1) }) { item, selected in
                WorkRow(
                    item: item,
                    selected: selected,
                    showRepository: !store.settings.groupByRepository,
                    showAuthor: store.tab != .mine,
                    showStatus: store.tab != .reviews
                )
            } empty: {
                emptyWork
            }
        }
    }

    private var workItems: [WorkItem]? {
        switch store.tab {
        case .mine: store.work?.mine
        case .reviews: store.work?.reviews
        default: store.work?.assigned
        }
    }

    private var emptyWork: EmptyState {
        switch store.tab {
        case .mine: EmptyState(symbol: "arrow.triangle.pull", title: "Aucune PR ouverte", message: "Tout est mergé, bien joué.")
        case .reviews: EmptyState(symbol: "eye", title: "Personne ne t'attend", message: "Aucune review ne t'est demandée.")
        default: EmptyState(symbol: "person.crop.circle", title: "Rien ne t'est assigné")
        }
    }

    private func open(_ item: GHNotification, inBackground: Bool) {
        store.open(item, inBackground: inBackground)
        if !inBackground { close() }
    }

    private func open(_ item: WorkItem, inBackground: Bool) {
        store.open(item, inBackground: inBackground)
        if !inBackground { close() }
    }
}

// MARK: - Liste filtrable

/// Une liste d'onglet : puces de filtre par dépôt, sections, ou état vide.
/// `items` à nil : pas encore chargé.
struct ItemList<Item: Listable, Row: View, Empty: View>: View {
    let store: Store
    let items: [Item]?
    let open: (Item, _ inBackground: Bool) -> Void
    var clear: ((Item) -> Void)?
    var mute: ((Item) -> Void)?
    var clearSection: (([Item]) -> Void)?
    @ViewBuilder let row: (Item, _ selected: Bool) -> Row
    @ViewBuilder let empty: () -> Empty

    var body: some View {
        if let items {
            VStack(spacing: 0) {
                let repositories = store.repositories(in: items)
                if repositories.count > 1 || store.repositoryFilter != nil {
                    RepositoryFilterBar(store: store, settings: store.settings, repositories: repositories, total: items.count)
                }
                content(items)
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func content(_ items: [Item]) -> some View {
        let sections = store.sections(items)
        if sections.contains(where: { !$0.items.isEmpty }) {
            SectionedList(sections: sections, open: open, clear: clear, mute: mute, clearSection: clearSection, row: row)
        } else if let filter = store.repositoryFilter, !items.isEmpty {
            EmptyState(
                symbol: "line.3.horizontal.decrease.circle",
                title: "Rien pour \(Style.shortName(filter)) ici",
                action: ("Voir tous les dépôts", { store.repositoryFilter = nil })
            )
        } else {
            empty()
        }
    }
}

struct RepositoryFilterBar: View {
    let store: Store
    @Bindable var settings: Settings
    let repositories: [(name: String, count: Int)]
    let total: Int

    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    FilterChip(title: "Tous", count: total, selected: store.repositoryFilter == nil) {
                        store.repositoryFilter = nil
                    }
                    .help("Afficher tous les dépôts")
                    ForEach(repositories, id: \.name) { repository in
                        let selected = store.repositoryFilter == repository.name
                        FilterChip(title: Style.shortName(repository.name), count: repository.count, selected: selected) {
                            store.repositoryFilter = selected ? nil : repository.name
                        }
                        .help(selected ? "Retirer le filtre \(repository.name)" : "Afficher seulement \(repository.name), dans tous les onglets")
                    }
                }
                .padding(.leading, 12)
            }
            Menu {
                Picker("Affichage", selection: $settings.groupByRepository) {
                    Text("Grouper par dépôt").tag(true)
                    Text("Tout par date").tag(false)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Grouper par dépôt ou tout trier par date")
            .padding(.trailing, 12)
        }
        .padding(.vertical, 4)
    }
}

struct FilterChip: View {
    let title: String
    let count: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).lineLimit(1)
                Text("\(count)")
                    .monospacedDigit()
                    .foregroundStyle(selected ? Color.white.opacity(0.75) : Color.secondary)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(selected ? Color.accentColor : Color.primary.opacity(0.07), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Sections défilantes avec navigation au clavier : ↑↓, ↩ (⌘↩ en fond), E ou ⌫, M.
struct SectionedList<Item: Listable, Row: View>: View {
    let sections: [ItemSection<Item>]
    let open: (Item, _ inBackground: Bool) -> Void
    let clear: ((Item) -> Void)?
    let mute: ((Item) -> Void)?
    let clearSection: (([Item]) -> Void)?
    let row: (Item, _ selected: Bool) -> Row
    @State private var selection: String?
    @FocusState private var focused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.items, content: rowView)
                        } header: {
                            header(section)
                        }
                    }
                }
                .padding(.bottom, 6)
            }
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(.downArrow) {
                move(by: 1, proxy)
                return .handled
            }
            .onKeyPress(.upArrow) {
                move(by: -1, proxy)
                return .handled
            }
            .onKeyPress(.return, phases: .down) { press in
                guard let item = selected else { return .ignored }
                open(item, press.modifiers.contains(.command))
                return .handled
            }
            .onKeyPress(keys: ["e", "m", .delete], phases: .down) { press in
                guard let item = selected, let action = press.key == "m" ? mute : clear else { return .ignored }
                action(item)
                return .handled
            }
            .onChange(of: ids, followSelection)
            .task { focused = true }
        }
    }

    private var ids: [String] { sections.flatMap { $0.items.map(\.id) } }

    private var selected: Item? {
        sections.lazy.flatMap(\.items).first { $0.id == selection }
    }

    private func rowView(_ item: Item) -> some View {
        row(item, selection == item.id)
            .contentShape(Rectangle())
            .onTapGesture { open(item, NSEvent.modifierFlags.contains(.command)) }
            .id(item.id)
            .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .trailing).combined(with: .opacity)))
    }

    @ViewBuilder
    private func header(_ section: ItemSection<Item>) -> some View {
        if let repository = section.repository {
            RepositoryHeader(name: repository, count: section.items.count, clear: clearAction(for: section))
        }
    }

    private func clearAction(for section: ItemSection<Item>) -> (() -> Void)? {
        guard let clearSection else { return nil }
        return { clearSection(section.items) }
    }

    private func move(by offset: Int, _ proxy: ScrollViewProxy) {
        let ids = ids
        guard !ids.isEmpty else { return }
        let index = selection.flatMap { ids.firstIndex(of: $0) }.map { $0 + offset } ?? (offset > 0 ? 0 : ids.count - 1)
        selection = ids[min(max(index, 0), ids.count - 1)]
        proxy.scrollTo(selection)
    }

    /// Quand l'élément sélectionné disparaît (lu, archivé…), la sélection passe à celui qui prend sa place.
    private func followSelection(_ old: [String], _ new: [String]) {
        guard let selection, !new.contains(selection) else { return }
        guard let index = old.firstIndex(of: selection), !new.isEmpty else {
            self.selection = nil
            return
        }
        self.selection = new[min(index, new.count - 1)]
    }
}

struct RepositoryHeader: View {
    let name: String
    let count: Int
    let clear: (() -> Void)?

    var body: some View {
        let parts = name.split(separator: "/", maxSplits: 1).map(String.init)
        HStack(spacing: 0) {
            if parts.count == 2 {
                Text(parts[0] + "/").foregroundStyle(.secondary)
            }
            Text(parts.last ?? name).fontWeight(.semibold)
            Text("  \(count)").foregroundStyle(.tertiary)
            Spacer()
            if let clear {
                IconButton("checkmark", help: "Tout marquer comme lu dans ce dépôt", action: clear)
            }
        }
        .font(.system(size: 11))
        .frame(minHeight: 22)
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 2)
        .background(.bar)
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    var message: String?
    var action: (label: String, run: () -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text(title).font(.system(.headline, design: .rounded))
            if let message {
                Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if let action {
                Button(action.label, action: action.run).buttonStyle(.link)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Lignes

struct NotificationRow: View {
    let item: GHNotification
    let state: SubjectState?
    let selected: Bool
    var showRepository = false
    /// Dans l'historique : quand le fil a été lu. Il n'y a alors plus rien à trier.
    var readAt: Date?
    var read: (() -> Void)?
    var mute: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: Style.icon(for: item.subject.type, state: state))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Style.color(for: state))
                .frame(width: 18)
                .padding(.top, 1)
                .help(Style.describe(type: item.subject.type, state: state))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.subject.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    if showRepository {
                        Text(Style.shortName(item.repositoryName))
                        Text("·")
                    }
                    Text(Style.reasonLabel(item.reason))
                        .fontWeight(.semibold)
                        .foregroundStyle(Style.reasonColor(item.reason))
                        .help(Style.reasonHelp(item.reason))
                    if let number = item.number {
                        Text("·")
                        Text("#\(String(number))")
                    }
                    Text("·")
                    Text(readAt.map { "lu \(Style.age(of: $0))" } ?? Style.age(of: item.updatedAt))
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            trailing
        }
        .rowStyle(selected: selected, hovering: hovering)
        .onHover { hovering = $0 }
        .help(readAt == nil
            ? "Ouvrir sur GitHub et marquer comme lu (⌘ clic : en arrière-plan)"
            : "Rouvrir sur GitHub (⌘ clic : en arrière-plan)")
    }

    @ViewBuilder
    private var trailing: some View {
        if let read, let mute, hovering || selected {
            HStack(spacing: 0) {
                IconButton("checkmark", help: "Marquer comme lu (E)", action: read)
                IconButton("bell.slash", help: "Se désabonner (M)", action: mute)
            }
        } else if readAt == nil {
            Text("+\(Game.baseXP(item.reason))")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
                .help("XP gagnée en triant cette notification, multipliée par le combo")
        }
    }
}

struct WorkRow: View {
    let item: WorkItem
    let selected: Bool
    var showRepository = false
    var showAuthor = false
    var showStatus = true
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: Style.icon(for: item))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Style.color(for: item))
                .frame(width: 18)
                .padding(.top, 1)
                .help(Style.describe(item))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    if showRepository {
                        Text(Style.shortName(item.repositoryName))
                        Text("·")
                    }
                    Text("#\(String(item.number))")
                    if showAuthor, let author = item.author {
                        Text("·")
                        Text("@\(author.login)")
                    }
                    if showStatus, let status = Style.status(of: item) {
                        Text("·")
                        Text(status.label).fontWeight(.semibold).foregroundStyle(status.color).help(status.help)
                    }
                    Text("·")
                    Text(Style.age(of: item.updatedAt))
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let checks = Style.checks(item.checks) {
                Image(systemName: checks.symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(checks.color)
                    .help(checks.help)
                    .padding(.top, 2)
            }
        }
        .rowStyle(selected: selected, hovering: hovering)
        .onHover { hovering = $0 }
        .help("Ouvrir sur GitHub (⌘ clic : en arrière-plan)")
    }
}

extension View {
    func rowStyle(selected: Bool, hovering: Bool) -> some View {
        padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? Color.accentColor.opacity(0.2) : hovering ? Color.primary.opacity(0.06) : .clear)
            )
            .padding(.horizontal, 6)
    }
}
