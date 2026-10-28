import Foundation
import Observation

/// La couche jeu : XP, niveaux, combos et série d'inbox zero.
@MainActor @Observable
final class Game {
    struct Gain: Equatable {
        let id = UUID()
        let date = Date.now
        let xp: Int
        let combo: Int
    }

    private(set) var xp: Int { didSet { defaults.set(xp, forKey: "xp") } }
    private(set) var cleared: Int { didSet { defaults.set(cleared, forKey: "cleared") } }
    private(set) var bestCombo: Int { didSet { defaults.set(bestCombo, forKey: "bestCombo") } }
    private(set) var streak: Int { didSet { defaults.set(streak, forKey: "streak") } }
    private var lastZeroDay: Date? { didSet { defaults.set(lastZeroDay, forKey: "lastZeroDay") } }

    /// Multiplicateur en cours ; retombe à 0 quand on laisse filer la fenêtre de combo.
    private(set) var combo = 0
    /// Dernier gain, pour animer le « +XP ».
    private(set) var lastGain: Gain?
    /// Niveau tout juste atteint, pour la bannière.
    private(set) var levelUp: Int?

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var comboReset: Task<Void, Never>?

    private static let comboWindow = Duration.seconds(8)
    private static let maxCombo = 5

    init() {
        let defaults = UserDefaults.standard
        xp = defaults.integer(forKey: "xp")
        cleared = defaults.integer(forKey: "cleared")
        bestCombo = defaults.integer(forKey: "bestCombo")
        streak = defaults.integer(forKey: "streak")
        lastZeroDay = defaults.object(forKey: "lastZeroDay") as? Date
    }

    // MARK: - Niveaux

    var level: Int { Self.level(for: xp) }

    /// XP cumulée pour atteindre un niveau : 0, 50, 150, 300, 500…
    static func threshold(_ level: Int) -> Int { 25 * level * (level - 1) }

    static func level(for xp: Int) -> Int {
        var level = 1
        while threshold(level + 1) <= xp { level += 1 }
        return level
    }

    var levelProgress: Double {
        let floor = Self.threshold(level)
        return Double(xp - floor) / Double(Self.threshold(level + 1) - floor)
    }

    var xpToNextLevel: Int { Self.threshold(level + 1) - xp }

    // MARK: - Récompenses

    static func baseXP(_ reason: String) -> Int {
        switch reason {
        case "review_requested", "security_alert", "approval_requested": 30
        case "mention", "team_mention", "assign": 20
        case "author", "comment", "state_change": 10
        default: 5
        }
    }

    /// Ce qui mérite qu'on s'en occupe vite : le compagnon lève la main.
    static func isUrgent(_ reason: String) -> Bool {
        ["review_requested", "security_alert", "approval_requested", "mention", "team_mention", "assign"].contains(reason)
    }

    /// Récompense le tri de notifications et renvoie `true` en cas de passage de niveau.
    /// Trier vite enchaîne les combos ; le tri en masse rapporte l'XP de base, sans combo.
    @discardableResult
    func award(_ reasons: [String], bulk: Bool = false) -> Bool {
        comboReset?.cancel()
        if bulk {
            combo = 0
        } else {
            combo = min(combo + 1, Self.maxCombo)
            bestCombo = max(bestCombo, combo)
            comboReset = Task { [weak self] in
                try? await Task.sleep(for: Self.comboWindow)
                if !Task.isCancelled { self?.combo = 0 }
            }
        }
        cleared += reasons.count
        return add(reasons.map(Self.baseXP).reduce(0, +) * max(combo, 1))
    }

    /// Premier inbox zero de la journée : prolonge la série et donne un bonus.
    /// Renvoie `false` si la journée était déjà comptée.
    func reachInboxZero() -> Bool {
        let today = Calendar.current.startOfDay(for: .now)
        if let lastZeroDay, Calendar.current.isDate(lastZeroDay, inSameDayAs: today) { return false }
        streak = lastZeroDay.map { Self.isUnbroken(since: $0, today: today) } == true ? streak + 1 : 1
        lastZeroDay = today
        add(20 + 10 * min(streak, 5))
        return true
    }

    /// Série en cours : elle casse dès qu'un jour ouvré passe sans inbox zero (les week-ends ne comptent pas).
    var currentStreak: Int {
        guard let lastZeroDay, Self.isUnbroken(since: lastZeroDay, today: Calendar.current.startOfDay(for: .now)) else { return 0 }
        return streak
    }

    func dismissLevelUp() {
        levelUp = nil
    }

    @discardableResult
    private func add(_ amount: Int) -> Bool {
        let before = level
        xp += amount
        lastGain = Gain(xp: amount, combo: combo)
        guard level > before else { return false }
        levelUp = level
        return true
    }

    private static func isUnbroken(since lastDay: Date, today: Date) -> Bool {
        let calendar = Calendar.current
        var day = calendar.date(byAdding: .day, value: 1, to: lastDay)!
        while day < today {
            if !calendar.isDateInWeekend(day) { return false }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return true
    }
}

/// Préférences, persistées dans les UserDefaults.
@MainActor @Observable
final class Settings {
    var petName: String { didSet { defaults.set(petName, forKey: "petName") } }
    var participatingOnly: Bool { didSet { defaults.set(participatingOnly, forKey: "participatingOnly") } }
    var markAsDone: Bool { didSet { defaults.set(markAsDone, forKey: "markAsDone") } }
    var systemNotifications: Bool { didSet { defaults.set(systemNotifications, forKey: "systemNotifications") } }
    var sounds: Bool { didSet { defaults.set(sounds, forKey: "sounds") } }
    /// Listes groupées par dépôt, ou à plat par date.
    var groupByRepository: Bool { didSet { defaults.set(groupByRepository, forKey: "groupByRepository") } }
    var tokenSource: TokenSource? { didSet { defaults.set(tokenSource?.rawValue, forKey: "tokenSource") } }
    var login: String? { didSet { defaults.set(login, forKey: "login") } }

    @ObservationIgnored private let defaults = UserDefaults.standard

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: ["petName": "Blip", "systemNotifications": true, "sounds": true, "groupByRepository": true])
        petName = defaults.string(forKey: "petName") ?? "Blip"
        participatingOnly = defaults.bool(forKey: "participatingOnly")
        markAsDone = defaults.bool(forKey: "markAsDone")
        systemNotifications = defaults.bool(forKey: "systemNotifications")
        sounds = defaults.bool(forKey: "sounds")
        groupByRepository = defaults.bool(forKey: "groupByRepository")
        tokenSource = defaults.string(forKey: "tokenSource").flatMap(TokenSource.init)
        login = defaults.string(forKey: "login")
    }
}
