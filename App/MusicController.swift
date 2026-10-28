import AppKit
import ImageIO
import UniformTypeIdentifiers
import WidgetKit

/// Morceau en cours dans Musique (Apple Music) et commandes de lecture.
/// Les changements arrivent par la notification distribuée de Musique : aucune interrogation
/// régulière. AppleScript ne sert qu'à lire la position / la pochette et à envoyer les commandes,
/// et seulement si Musique est déjà ouvert (on ne le lance jamais sans action de l'utilisateur).
@MainActor
final class MusicController: ObservableObject {
    @Published private(set) var nowPlaying: NowPlaying?

    private static let bundleID = "com.apple.Music"
    private var artworkTrackID: String?

    func start() {
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.Music.playerInfo"),
                                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == Self.bundleID else { return }
            MainActor.assumeIsolated { self?.publish(nil) }
        }
        refresh()
    }

    private var isMusicRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }

    func send(_ command: MusicCommand) {
        let verb = switch command {
        case .playpause: "playpause"
        case .next: "next track"
        case .previous: "previous track"
        }
        // Ici seulement, on accepte de lancer Musique : l'utilisateur a appuyé sur lecture.
        _ = Self.run("tell application \"Music\" to \(verb)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.refresh() }
    }

    func refresh() {
        guard isMusicRunning else { publish(nil); return }
        let script = """
        tell application "Music"
            if player state is stopped then return {"stopped"}
            set t to current track
            return {player state as text, name of t, artist of t, album of t, duration of t, player position, persistent ID of t}
        end tell
        """
        guard let result = Self.run(script), result.numberOfItems >= 7,
              let state = result.atIndex(1)?.stringValue, state != "stopped" else {
            publish(nil)
            return
        }
        let trackID = result.atIndex(7)?.stringValue ?? ""
        var info = NowPlaying(title: result.atIndex(2)?.stringValue ?? "",
                              artist: result.atIndex(3)?.stringValue ?? "",
                              album: result.atIndex(4)?.stringValue ?? "",
                              isPlaying: state == "playing",
                              duration: result.atIndex(5)?.doubleValue ?? 0,
                              position: result.atIndex(6)?.doubleValue ?? 0,
                              positionDate: Date(),
                              artworkFile: nowPlaying?.artworkFile)
        if trackID != artworkTrackID {
            artworkTrackID = trackID
            info.artworkFile = saveArtwork(trackID: trackID)
        }
        publish(info)
    }

    private func publish(_ info: NowPlaying?) {
        // La position bouge sans cesse : on ne recharge le widget que si le morceau ou l'état change.
        let changed = info?.title != nowPlaying?.title || info?.isPlaying != nowPlaying?.isPlaying
            || info?.artworkFile != nowPlaying?.artworkFile || abs((info?.position ?? 0) - (nowPlaying.map { $0.position + Date().timeIntervalSince($0.positionDate) } ?? 0)) > 3
        nowPlaying = info
        if info == nil { artworkTrackID = nil }
        SharedStore.write(info, to: SharedStore.musicFile)
        if changed { WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.music) }
    }

    /// Pochette réduite à 600 px, nom unique par morceau pour que le widget ne garde pas l'ancienne.
    private func saveArtwork(trackID: String) -> String? {
        let folder = SharedStore.directory.appendingPathComponent("Music", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        guard let data = Self.run("tell application \"Music\" to get raw data of artwork 1 of current track")?.data,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 600,
              ] as CFDictionary)
        else { return nil }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(trackID.isEmpty ? UUID().uuidString : trackID).jpg")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? url.path : nil
    }

    private static func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        return NSAppleScript(source: source)?.executeAndReturnError(&error)
    }
}
