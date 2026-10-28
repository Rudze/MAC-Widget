import AppKit
import SwiftUI
import WidgetKit

struct MusicEntry: TimelineEntry {
    let date: Date
    let nowPlaying: NowPlaying?
    var style = Appearance().music
}

struct MusicProvider: TimelineProvider {
    func placeholder(in context: Context) -> MusicEntry {
        MusicEntry(date: .now, nowPlaying: NowPlaying(title: "Titre du morceau", artist: "Artiste", album: "Album",
                                                      isPlaying: true, duration: 210, position: 64,
                                                      positionDate: .now, artworkFile: nil))
    }

    func getSnapshot(in context: Context, completion: @escaping (MusicEntry) -> Void) {
        let entry = load()
        completion(entry.nowPlaying == nil && context.isPreview ? placeholder(in: context) : entry)
    }

    /// L'app recharge le widget à chaque changement de morceau ; la progression avance seule.
    func getTimeline(in context: Context, completion: @escaping (Timeline<MusicEntry>) -> Void) {
        let entry = load()
        let policy: TimelineReloadPolicy = entry.nowPlaying.map { $0.isPlaying ? .after($0.endDate.addingTimeInterval(2)) : .never } ?? .never
        completion(Timeline(entries: [entry], policy: policy))
    }

    private func load() -> MusicEntry {
        MusicEntry(date: .now, nowPlaying: SharedStore.read(NowPlaying.self, from: SharedStore.musicFile),
                   style: Appearance.current.music)
    }
}

struct MusicWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.music, provider: MusicProvider()) { entry in
            MusicView(entry: entry)
        }
        .configurationDisplayName("Musique")
        .description("Le morceau en cours dans Apple Music, avec lecture, pause et suivant.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

/// Dans un widget flottant, les boutons appellent directement l'app ;
/// dans la galerie, ce sont des liens `macwidget://music/…` (sans App Intents, absents hors Xcode).
private struct MusicActionKey: EnvironmentKey {
    static let defaultValue: ((MusicCommand) -> Void)? = nil
}

extension EnvironmentValues {
    var musicAction: ((MusicCommand) -> Void)? {
        get { self[MusicActionKey.self] }
        set { self[MusicActionKey.self] = newValue }
    }
}

private struct MusicButton: View {
    let command: MusicCommand
    let symbol: String
    let size: CGFloat
    @Environment(\.musicAction) private var action

    var body: some View {
        let label = Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .frame(width: size * 1.9, height: size * 1.9)
            .contentShape(Rectangle())
        if let action {
            Button { action(command) } label: { label }.buttonStyle(.plain)
        } else {
            Link(destination: URL(string: "macwidget://music/\(command.rawValue)")!) { label }
        }
    }
}

struct MusicView: View {
    let entry: MusicEntry
    @ResolvedFamily private var family

    var body: some View {
        Group {
            if let np = entry.nowPlaying {
                switch family {
                case .systemSmall: small(np)
                case .systemLarge: large(np)
                default: medium(np)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "music.note").font(.system(size: 26, weight: .light))
                    Text("Rien en lecture").font(.system(size: 13, weight: .semibold))
                    if family != .systemSmall {
                        MusicButton(command: .playpause, symbol: "play.fill", size: 16)
                    }
                }
                .foregroundStyle(Theme.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(Theme.primary)
        .widgetBackground(entry.style)
        // Petit format : pas de liens multiples possibles, un clic = lecture / pause.
        .widgetURL(family == .systemSmall ? URL(string: "macwidget://music/playpause") : nil)
    }

    // MARK: Éléments

    @ViewBuilder
    private func artwork(_ np: NowPlaying, size: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
        if let path = np.artworkFile, let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image)
                .fullColorResizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(shape)
        } else {
            shape.fill(Theme.track)
                .frame(width: size, height: size)
                .overlay(Image(systemName: "music.note").font(.system(size: size * 0.35)).foregroundStyle(Theme.secondary))
        }
    }

    private func titles(_ np: NowPlaying, titleSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(np.title).font(.system(size: titleSize, weight: .semibold)).lineLimit(1)
            Text(np.artist).font(.system(size: titleSize - 2)).foregroundStyle(Theme.secondary).lineLimit(1)
        }
    }

    /// Progression animée par le système quand ça joue, figée en pause.
    @ViewBuilder
    private func progress(_ np: NowPlaying) -> some View {
        Group {
            if np.isPlaying, np.endDate > entry.date {
                ProgressView(timerInterval: np.startDate...np.endDate, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
            } else {
                ProgressView(value: np.progress)
            }
        }
        .progressViewStyle(.linear)
        .tint(Theme.primary)
        .labelsHidden()
        .widgetAccentable()
    }

    private func controls(_ np: NowPlaying, size: CGFloat) -> some View {
        HStack(spacing: size * 0.6) {
            MusicButton(command: .previous, symbol: "backward.fill", size: size * 0.8)
            MusicButton(command: .playpause, symbol: np.isPlaying ? "pause.fill" : "play.fill", size: size)
            MusicButton(command: .next, symbol: "forward.fill", size: size * 0.8)
        }
    }

    // MARK: Tailles

    private func small(_ np: NowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                artwork(np, size: 64)
                Spacer()
                Image(systemName: np.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .semibold))
            }
            Spacer(minLength: 0)
            titles(np, titleSize: 13)
            progress(np)
        }
    }

    private func medium(_ np: NowPlaying) -> some View {
        HStack(spacing: 14) {
            artwork(np, size: 138)
            VStack(alignment: .leading, spacing: 8) {
                titles(np, titleSize: 15)
                Text(np.album).font(.system(size: 11)).foregroundStyle(Theme.tertiary).lineLimit(1)
                Spacer(minLength: 0)
                progress(np)
                controls(np, size: 18)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func large(_ np: NowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            artwork(np, size: 200)
                .frame(maxWidth: .infinity)
            titles(np, titleSize: 17)
            progress(np)
            controls(np, size: 24)
                .frame(maxWidth: .infinity)
        }
    }
}
