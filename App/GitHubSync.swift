import AppKit
import Security
import WidgetKit

/// Récupère le graphe de contributions et les derniers commits, toutes les 30 min.
/// Sans jeton : page publique des contributions + recherche de commits publics.
/// Avec un jeton (Keychain) : API GraphQL, qui inclut aussi les contributions privées.
@MainActor
final class GitHubSync: ObservableObject {
    @Published var username: String {
        didSet { UserDefaults.standard.set(username, forKey: "githubUser") }
    }
    @Published private(set) var snapshot: GitHubSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var hasToken = Keychain.read() != nil

    private var timer: Timer?

    init() {
        username = UserDefaults.standard.string(forKey: "githubUser") ?? ""
        snapshot = SharedStore.read(GitHubSnapshot.self, from: SharedStore.githubFile)
    }

    func start() {
        let timer = Timer(timeInterval: 30 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 5 * 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    func setToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { Keychain.delete() } else { Keychain.save(trimmed) }
        hasToken = !trimmed.isEmpty
        refresh()
    }

    func refresh() {
        let user = username.trimmingCharacters(in: .whitespaces)
        guard !user.isEmpty, !isLoading else { return }
        isLoading = true
        let token = Keychain.read()
        Task {
            do {
                async let commits = Self.recentCommits(user, token: token)
                let days = if let token {
                    try await Self.contributionsGraphQL(user, token: token)
                } else {
                    try await Self.contributionsPublic(user)
                }
                let snapshot = GitHubSnapshot(username: user, days: days,
                                              commits: (try? await commits) ?? [], updated: Date())
                let changed = snapshot.days != self.snapshot?.days || snapshot.commits != self.snapshot?.commits
                self.snapshot = snapshot
                self.error = nil
                SharedStore.write(snapshot, to: SharedStore.githubFile)
                if changed { WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.github) }
            } catch {
                self.error = error.localizedDescription
            }
            self.isLoading = false
        }
    }

    // MARK: Réseau

    enum Failure: LocalizedError {
        case http(Int), notFound, parse
        var errorDescription: String? {
            switch self {
            case .http(401): "Jeton GitHub refusé."
            case .http(let code): "GitHub a répondu \(code)."
            case .notFound: "Utilisateur GitHub introuvable."
            case .parse: "Réponse GitHub illisible."
            }
        }
    }

    private static func get(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { throw Failure.notFound }
        guard (200..<300).contains(code) else { throw Failure.http(code) }
        return data
    }

    private static func apiRequest(_ url: URL, token: String?) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return request
    }

    /// Page publique (celle qu'affiche le profil) : chaque case a `data-date`, `data-level`
    /// et une infobulle « N contributions on … ».
    private static func contributionsPublic(_ user: String) async throws -> [ContributionDay] {
        let escaped = user.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? user
        let url = URL(string: "https://github.com/users/\(escaped)/contributions")!
        guard let html = String(data: try await get(URLRequest(url: url, timeoutInterval: 20)), encoding: .utf8)
        else { throw Failure.parse }

        var counts: [String: Int] = [:]
        let tips = try NSRegularExpression(pattern: #"<tool-tip[^>]*for="([^"]+)"[^>]*>([^<]*)</tool-tip>"#)
        for m in tips.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let id = Range(m.range(at: 1), in: html), let text = Range(m.range(at: 2), in: html) else { continue }
            counts[String(html[id])] = Int(html[text].prefix { $0.isNumber }) ?? 0
        }

        var days: [ContributionDay] = []
        let cells = try NSRegularExpression(pattern: #"<td[^>]*data-date="([^"]+)"[^>]*>"#)
        for m in cells.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let tagRange = Range(m.range, in: html), let dateRange = Range(m.range(at: 1), in: html) else { continue }
            let tag = String(html[tagRange])
            let id = attribute("id", in: tag) ?? ""
            let level = Int(attribute("data-level", in: tag) ?? "0") ?? 0
            days.append(ContributionDay(date: String(html[dateRange]), count: counts[id] ?? 0, level: level))
        }
        guard !days.isEmpty else { throw Failure.parse }
        return days.sorted { $0.date < $1.date }
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        guard let range = tag.range(of: " \(name)=\"") else { return nil }
        return String(tag[range.upperBound...].prefix { $0 != "\"" })
    }

    private static func contributionsGraphQL(_ user: String, token: String) async throws -> [ContributionDay] {
        var request = apiRequest(URL(string: "https://api.github.com/graphql")!, token: token)
        request.httpMethod = "POST"
        let query = """
        query($login: String!) { user(login: $login) { contributionsCollection { contributionCalendar {
          weeks { contributionDays { date contributionCount contributionLevel } } } } } }
        """
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": ["login": user]])

        struct Response: Decodable {
            struct Day: Decodable { let date: String; let contributionCount: Int; let contributionLevel: String }
            struct Week: Decodable { let contributionDays: [Day] }
            struct Calendar: Decodable { let weeks: [Week] }
            struct Collection: Decodable { let contributionCalendar: Calendar }
            struct User: Decodable { let contributionsCollection: Collection }
            struct DataField: Decodable { let user: User? }
            let data: DataField?
        }
        let response = try JSONDecoder().decode(Response.self, from: try await get(request))
        guard let user = response.data?.user else { throw Failure.notFound }
        let levels = ["NONE": 0, "FIRST_QUARTILE": 1, "SECOND_QUARTILE": 2, "THIRD_QUARTILE": 3, "FOURTH_QUARTILE": 4]
        return user.contributionsCollection.contributionCalendar.weeks.flatMap(\.contributionDays).map {
            ContributionDay(date: $0.date, count: $0.contributionCount, level: levels[$0.contributionLevel] ?? 0)
        }
    }

    private static func recentCommits(_ user: String, token: String?) async throws -> [GitHubCommit] {
        // Des dépôts publient des commits datés de 2099 : sans borne, ils occupent le haut du tri.
        let tomorrow = Date().addingTimeInterval(86_400).formatted(.iso8601.year().month().day())
        var components = URLComponents(string: "https://api.github.com/search/commits")!
        components.queryItems = [
            URLQueryItem(name: "q", value: "author:\(user) committer-date:<=\(tomorrow)"),
            URLQueryItem(name: "sort", value: "committer-date"),
            URLQueryItem(name: "order", value: "desc"),
            URLQueryItem(name: "per_page", value: "20"),
        ]
        struct Response: Decodable {
            struct Person: Decodable { let date: String }
            struct Commit: Decodable { let message: String; let committer: Person }
            struct Repo: Decodable { let full_name: String }
            struct Item: Decodable { let sha: String; let commit: Commit; let repository: Repo }
            let items: [Item]
        }
        let response = try JSONDecoder().decode(Response.self, from: try await get(apiRequest(components.url!, token: token)))

        let iso = ISO8601DateFormatter()
        let isoFraction = ISO8601DateFormatter()
        isoFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let limit = Date().addingTimeInterval(3600) // ignore les dates de commit fantaisistes dans le futur
        return response.items.compactMap { item -> GitHubCommit? in
            guard let date = isoFraction.date(from: item.commit.committer.date) ?? iso.date(from: item.commit.committer.date),
                  date < limit else { return nil }
            let message = item.commit.message.split(separator: "\n").first.map(String.init) ?? ""
            return GitHubCommit(id: item.sha, repo: item.repository.full_name, message: message, date: date)
        }
        .prefix(8)
        .map { $0 }
    }
}

/// Jeton GitHub rangé dans le trousseau, jamais dans un fichier.
enum Keychain {
    private static let service = "com.rudy.macwidget.github"

    private static var query: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: "token"]
    }

    static func save(_ token: String) {
        delete()
        var attributes = query
        attributes[kSecValueData] = Data(token.utf8)
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func read() -> String? {
        var q = query
        q[kSecReturnData] = true
        q[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
