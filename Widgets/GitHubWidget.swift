import SwiftUI
import WidgetKit

struct GitHubEntry: TimelineEntry {
    let date: Date
    let snapshot: GitHubSnapshot?
    var style = Appearance().github
}

struct GitHubProvider: TimelineProvider {
    func placeholder(in context: Context) -> GitHubEntry {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let days = (0..<140).map { i -> ContributionDay in
            let date = Calendar.current.date(byAdding: .day, value: i - 139, to: .now)!
            let level = (i * 7 + i / 3) % 5
            return ContributionDay(date: formatter.string(from: date), count: level * 2, level: level)
        }
        let commits = [
            GitHubCommit(id: "1", repo: "toi/MacWidget", message: "Ajoute le widget GitHub", date: .now.addingTimeInterval(-1800)),
            GitHubCommit(id: "2", repo: "toi/MacWidget", message: "Cadran personnalisable", date: .now.addingTimeInterval(-7200)),
        ]
        return GitHubEntry(date: .now, snapshot: GitHubSnapshot(username: "toi", days: days, commits: commits, updated: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (GitHubEntry) -> Void) {
        let entry = load()
        completion(entry.snapshot == nil ? placeholder(in: context) : entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GitHubEntry>) -> Void) {
        completion(Timeline(entries: [load()], policy: .after(.now.addingTimeInterval(30 * 60))))
    }

    private func load() -> GitHubEntry {
        GitHubEntry(date: .now, snapshot: SharedStore.read(GitHubSnapshot.self, from: SharedStore.githubFile),
                    style: Appearance.current.github)
    }
}

struct GitHubWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.github, provider: GitHubProvider()) { entry in
            GitHubView(entry: entry)
        }
        .configurationDisplayName("GitHub")
        .description("Ton graphe de contributions et tes derniers commits.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct GitHubView: View {
    let entry: GitHubEntry
    @ResolvedFamily private var family

    var body: some View {
        Group {
            if let s = entry.snapshot {
                switch family {
                case .systemSmall: small(s)
                case .systemLarge: large(s)
                default: medium(s)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right").font(.title2)
                    Text("Indique ton pseudo GitHub\ndans MacWidget")
                        .font(.system(size: 12, weight: .medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.secondary)
                }
            }
        }
        .foregroundStyle(Theme.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetBackground(entry.style)
        .widgetURL(WidgetLink.github.url)
    }

    private func header(_ s: GitHubSnapshot) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 11, weight: .bold))
            Text(s.username).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.secondary)
    }

    private func stat(_ value: Int, _ label: String, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(value)")
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .widgetAccentable()
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.secondary)
        }
    }

    private func small(_ s: GitHubSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header(s)
            HStack(alignment: .top, spacing: 14) {
                stat(s.today, "aujourd'hui", size: 26)
                stat(s.streak, "jours d'affilée", size: 26)
            }
            ContributionGrid(days: s.days, weeks: 9)
        }
    }

    private func medium(_ s: GitHubSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                header(s)
                Text("\(s.total) contributions sur un an")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            ContributionGrid(days: s.days, weeks: 22)
            HStack(spacing: 18) {
                stat(s.today, "aujourd'hui", size: 17)
                stat(s.streak, "jours d'affilée", size: 17)
                if let last = s.commits.first {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(last.message).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        Text(last.date.formatted(.relative(presentation: .named)))
                            .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    }
                }
            }
        }
    }

    private func large(_ s: GitHubSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(s)
            ContributionGrid(days: s.days, weeks: 22)
                .frame(height: 108)
            HStack(spacing: 22) {
                stat(s.today, "aujourd'hui", size: 20)
                stat(s.streak, "jours d'affilée", size: 20)
                stat(s.total, "sur un an", size: 20)
            }
            Divider().overlay(Theme.track)
            if s.commits.isEmpty {
                Text("Aucun commit public récent").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            ForEach(s.commits.prefix(4)) { c in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(Theme.primary).frame(width: 5, height: 5).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.message).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text("\(c.repo.split(separator: "/").last.map(String.init) ?? c.repo) · \(c.date.formatted(.relative(presentation: .named)))")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Graphe façon GitHub, en nuances de blanc : une colonne par semaine, dimanche en haut.
struct ContributionGrid: View {
    let days: [ContributionDay]
    let weeks: Int

    private var columns: [[ContributionDay?]] {
        guard let last = days.last, let lastDate = Self.parse(last.date) else { return [] }
        // La dernière colonne est la semaine en cours, éventuellement incomplète.
        let weekday = Calendar(identifier: .gregorian).component(.weekday, from: lastDate) // 1 = dimanche
        let padded = days.map { Optional($0) } + Array(repeating: nil, count: 7 - weekday)
        let needed = weeks * 7
        let slice = padded.suffix(needed)
        let cells = Array(repeating: nil, count: max(needed - slice.count, 0)) + Array(slice)
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
    }

    private static func parse(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.date(from: s)
    }

    private static let opacities = [0.09, 0.32, 0.52, 0.76, 1.0]

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 2.5
            let cell = max(min((geo.size.width - gap * CGFloat(weeks - 1)) / CGFloat(weeks),
                               (geo.size.height - gap * 6) / 7), 2)
            HStack(alignment: .top, spacing: gap) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { i in
                            let day = i < week.count ? week[i] : nil
                            RoundedRectangle(cornerRadius: cell * 0.25)
                                .fill(Theme.primary.opacity(day.map { Self.opacities[min(max($0.level, 0), 4)] } ?? 0))
                                .frame(width: cell, height: cell)
                        }
                    }
                }
            }
            .widgetAccentable()
        }
    }
}
