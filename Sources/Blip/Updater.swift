import AppKit
import Observation

/// Mises à jour via les releases GitHub du dépôt : Blip vérifie la dernière release,
/// propose de l'installer, remplace l'app sur place puis se relance.
@MainActor @Observable
final class Updater {
    struct Release: Equatable, Sendable {
        let version: String
        let page: URL
        let archive: URL
    }

    enum Phase: Equatable {
        case idle, installing
        case failed(String)
    }

    private(set) var available: Release?
    private(set) var phase = Phase.idle
    private(set) var checkedAt: Date?

    static let repository = "nihiloproxima/blip"
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String

    /// Rien à mettre à jour hors bundle (`swift run`) ni en mode démo.
    private var isEnabled: Bool { Self.version != nil && Bundle.main.bundleIdentifier != nil && Demo.count == nil }

    /// Blip ne peut se remplacer que si son dossier est accessible en écriture
    /// (ce n'est pas le cas d'une app lancée en translocation par Gatekeeper) ; sinon on renvoie vers la release.
    var canInstall: Bool {
        FileManager.default.isWritableFile(atPath: Bundle.main.bundleURL.deletingLastPathComponent().path)
    }

    func start() {
        guard isEnabled else { return }
        Task {
            while !Task.isCancelled {
                await check()
                try? await Task.sleep(for: .seconds(6 * 3600))
            }
        }
    }

    func check() async {
        guard isEnabled, let current = Self.version else { return }
        struct Payload: Decodable {
            let tagName: String
            let htmlUrl: URL
            let assets: [Asset]
            struct Asset: Decodable { let name: String; let browserDownloadUrl: URL }
        }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let payload = try? decoder.decode(Payload.self, from: data) else { return }
        checkedAt = .now
        let version = String(payload.tagName.trimmingPrefix("v"))
        guard version.compare(current, options: .numeric) == .orderedDescending,
              let archive = payload.assets.first(where: { $0.name == "Blip.zip" }) else {
            available = nil
            return
        }
        available = Release(version: version, page: payload.htmlUrl, archive: archive.browserDownloadUrl)
    }

    func install() {
        guard let release = available, phase != .installing else { return }
        phase = .installing
        Task {
            do {
                try await Self.replace(Bundle.main.bundleURL, with: release)
                Self.relaunch(Bundle.main.bundleURL)
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Installation

    private enum Failure: LocalizedError {
        case download(Int)
        case tool(String)
        case unexpectedBundle

        var errorDescription: String? {
            switch self {
            case .download(let status): "Téléchargement impossible (HTTP \(status))."
            case .tool(let name): "La mise à jour a échoué à l'étape « \(name) »."
            case .unexpectedBundle: "L'archive téléchargée ne contient pas la bonne version de Blip."
            }
        }
    }

    /// Télécharge et décompresse la release à côté de l'app (même volume), vérifie le bundle et sa signature,
    /// puis l'échange avec l'app en place.
    private static func replace(_ app: URL, with release: Release) async throws {
        let (archive, response) = try await URLSession.shared.download(from: release.archive)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure.download(status) }

        let identifier = Bundle.main.bundleIdentifier
        try await Task.detached {
            let files = FileManager.default
            let staging = try files.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: app, create: true)
            defer { try? files.removeItem(at: staging) }
            try run("/usr/bin/ditto", ["-x", "-k", archive.path, staging.path], step: "décompression")

            let candidate = staging.appending(path: "Blip.app")
            let bundle = Bundle(url: candidate)
            guard bundle?.bundleIdentifier == identifier,
                  bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == release.version else {
                throw Failure.unexpectedBundle
            }
            try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", candidate.path], step: "vérification de la signature")
            _ = try files.replaceItemAt(app, withItemAt: candidate)
        }.value
    }

    private nonisolated static func run(_ tool: String, _ arguments: [String], step: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.tool(step) }
    }

    /// Un petit shell attend que Blip ait quitté pour rouvrir la nouvelle version.
    private static func relaunch(_ app: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", #"while kill -0 "$1" 2>/dev/null; do sleep 0.2; done; open "$2""#, "sh", String(getpid()), app.path]
        try? process.run()
        NSApp.terminate(nil)
    }
}
