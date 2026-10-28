import AppKit
import SwiftUI

/// Icône de barre de menus + popover. La vue SwiftUI n'existe que popover ouvert.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let store = Store()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem!
    private var hopTask: Task<Void, Never>?
    private var lift = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }
        popover.behavior = .transient
        popover.delegate = self
        store.onNews = { [weak self] in self?.hop() }
        trackStatusItem()

        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.store.refresh(force: true) }
        }
        Task { await store.start() }
        store.updater.start()
    }

    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
    }

    /// Redessine l'icône dès que le nombre de notifications, l'humeur ou le niveau change.
    private func trackStatusItem() {
        withObservationTracking(updateStatusItem) { [weak self] in
            Task { @MainActor in self?.trackStatusItem() }
        }
    }

    private func updateStatusItem() {
        let count = store.notifications.count
        statusItem.button?.image = Pet.menuBarImage(
            mood: store.mood,
            level: store.game.level,
            alert: store.hasUrgent,
            colored: store.hasNews && count > 0,
            lift: lift
        )
        statusItem.button?.title = count > 0 ? "\(count)" : ""
        statusItem.button?.toolTip = statusTooltip(count: count)
    }

    private func statusTooltip(count: Int) -> String {
        var lines = [count > 0 ? "\(count) notification\(count > 1 ? "s" : "") GitHub non lue\(count > 1 ? "s" : "")" : "Inbox zero"]
        if let reviews = store.work?.reviews.count, reviews > 0 {
            lines.append("\(reviews) review\(reviews > 1 ? "s" : "") t'attend\(reviews > 1 ? "ent" : "")")
        } else if store.hasUrgent {
            lines.append("Quelqu'un attend une action de ta part")
        }
        lines.append("Clic : ouvrir · Clic droit : rafraîchir ou quitter")
        return lines.joined(separator: "\n")
    }

    /// Deux petits sauts quand des notifications arrivent.
    private func hop() {
        hopTask?.cancel()
        hopTask = Task {
            for lift in [1, 2, 3, 3, 2, 1, 0, 1, 2, 1, 0] {
                guard !Task.isCancelled else { return }
                self.lift = lift
                updateStatusItem()
                try? await Task.sleep(for: .milliseconds(45))
            }
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Rafraîchir", action: #selector(refreshNow), keyEquivalent: "r").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quitter Blip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem.menu = menu
            sender.performClick(nil)
            statusItem.menu = nil
        } else if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.contentViewController = NSHostingController(rootView: PopoverView(store: store) { [weak self] in
                self?.popover.performClose(nil)
            })
            popover.contentSize = PopoverView.size
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            NSApp.activate()
            store.popoverOpened()
        }
    }

    @objc private func refreshNow() {
        store.refreshAll()
    }
}
