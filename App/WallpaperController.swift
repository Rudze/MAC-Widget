import AppKit
import AVFoundation
import Combine
import UniformTypeIdentifiers

/// Fond d'écran animé : une fenêtre au niveau du bureau par écran, toutes branchées
/// sur un seul AVPlayer (une seule vidéo décodée, par la puce média).
/// La lecture s'arrête dès que personne ne la voit : bureau recouvert, écran en veille,
/// session verrouillée, et en option sur batterie ou en mode économie d'énergie.
@MainActor
final class WallpaperController: ObservableObject {
    enum Status: Equatable {
        case off, preparing, playing, still
        case paused(String)
        case failed(String)

        var text: String {
            switch self {
            case .off: "Désactivé"
            case .preparing: "Conversion en vidéo…"
            case .playing: "Lecture"
            case .still: "Image fixe · affichée par macOS, 0 % processeur"
            case .paused(let reason): "En pause · \(reason)"
            case .failed(let message): message
            }
        }
    }

    @Published private(set) var status: Status = .off
    @Published private(set) var poster: NSImage?

    private let settings = AppSettings.shared
    private var windows: [NSWindow] = []
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var loadedPath: String?
    private var loadTask: Task<Void, Never>?
    private var screensAsleep = false
    private var sessionActive = true
    private var cancellables = Set<AnyCancellable>()
    private var windowObservers = Set<AnyCancellable>()

    static let supportedTypes: [UTType] = [.movie, .image]

    /// Image fixe appliquée comme fond d'écran système (nil en mode vidéo).
    private var stillURL: URL?

    func start() {
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reconcile() }
            .store(in: &cancellables)

        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.screensAsleep = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.screensAsleep = false }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.sessionActive = false }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionActive = true }
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked")) { $0.sessionActive = false }
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsUnlocked")) { $0.sessionActive = true }
        observe(NotificationCenter.default, .powerSourceChanged) { _ in }
        observe(NotificationCenter.default, .NSProcessInfoPowerStateDidChange) { _ in }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) {
            $0.rebuildWindows()
            $0.applyStill() // nouvel écran branché
        }

        reconcile()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping (WallpaperController) -> Void) {
        center.publisher(for: name)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                action(self)
                self.updatePlayback()
            }
            .store(in: &cancellables)
    }

    // MARK: État souhaité

    func choose(_ url: URL) {
        settings.wallpaperPath = url.path
        settings.wallpaperEnabled = true
    }

    private func reconcile() {
        guard settings.wallpaperEnabled, let path = settings.wallpaperPath, !path.isEmpty else {
            if loadedPath != nil { restoreSystemWallpaper() }
            tearDown()
            status = .off
            return
        }
        if path != loadedPath { load(path) } else { updatePlayback() }
    }

    private func load(_ path: String) {
        tearDown()
        loadedPath = path
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            status = .failed("Fichier introuvable")
            return
        }

        if AnimatedImageConverter.isAnimatedImage(url) {
            status = .preparing
            loadTask = Task { [weak self] in
                do {
                    let video = try await AnimatedImageConverter.cachedVideo(for: url)
                    guard let self, self.loadedPath == path else { return }
                    self.play(video)
                } catch {
                    guard let self, self.loadedPath == path else { return }
                    self.status = .failed(error.localizedDescription)
                }
            }
        } else if UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) == true {
            play(url)
        } else if UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true {
            showStill(url)
        } else {
            status = .failed("Format non pris en charge.")
        }
    }

    /// Une image fixe n'a pas besoin de fenêtre ni de lecteur : macOS l'affiche lui-même.
    /// On la copie sous un nom unique (macOS garde les fonds en cache par chemin, et l'original
    /// peut être déplacé ou supprimé).
    private func showStill(_ url: URL) {
        let folder = AnimatedImageConverter.cacheDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appendingPathComponent("still-\(Int(Date().timeIntervalSince1970)).\(url.pathExtension.lowercased())")
        do {
            try FileManager.default.copyItem(at: url, to: copy)
        } catch {
            status = .failed("Copie de l'image impossible.")
            return
        }
        stillURL = copy
        poster = PhotoLibrary.downsample(copy, maxPixel: 1200).map { NSImage(cgImage: $0, size: .zero) }
        saveOriginalWallpapers()
        applyStill()
        cleanOldFiles(keeping: copy)
        status = .still
    }

    private func applyStill() {
        guard let stillURL else { return }
        for screen in NSScreen.screens {
            try? NSWorkspace.shared.setDesktopImageURL(stillURL, for: screen, options: [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                .allowClipping: true,
            ])
        }
    }

    private func play(_ url: URL) {
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.allowsExternalPlayback = false
        looper = AVPlayerLooper(player: player, templateItem: item)
        self.player = player
        rebuildWindows()
        updatePlayback()
        Task { await makePoster(asset) }
    }

    private func tearDown() {
        loadTask?.cancel()
        loadTask = nil
        player?.pause()
        looper?.disableLooping()
        looper = nil
        player = nil
        loadedPath = nil
        stillURL = nil
        poster = nil
        windows.forEach { $0.orderOut(nil) }
        windows = []
        windowObservers = []
    }

    // MARK: Fenêtres

    private func rebuildWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows = []
        windowObservers = []
        guard let player else { return }

        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
            window.ignoresMouseEvents = true
            window.isOpaque = true
            window.hasShadow = false
            window.backgroundColor = .black
            window.isReleasedWhenClosed = false
            window.animationBehavior = .none

            let layer = AVPlayerLayer(player: player)
            layer.videoGravity = .resizeAspectFill
            layer.backgroundColor = .black
            let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.layer = layer
            view.wantsLayer = true
            window.contentView = view
            window.setFrame(screen.frame, display: false)
            window.orderFrontRegardless()

            NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification, object: window)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.updatePlayback() }
                .store(in: &windowObservers)
            windows.append(window)
        }
    }

    // MARK: Lecture / pause

    private func updatePlayback() {
        guard let player else { return }
        let reason: String? =
            screensAsleep || !sessionActive ? "écran en veille"
            : settings.pauseOnBattery && MacBattery.isOnBattery() ? "sur batterie"
            : settings.pauseInLowPower && ProcessInfo.processInfo.isLowPowerModeEnabled ? "économie d'énergie"
            : !windows.contains(where: { $0.occlusionState.contains(.visible) }) ? "bureau masqué"
            : nil

        if let reason {
            if player.rate != 0 { player.pause() }
            status = .paused(reason)
        } else {
            if player.rate == 0 { player.play() }
            status = .playing
        }
    }

    // MARK: Fond d'écran système (écran verrouillé, Mission Control, teinte des widgets)

    private func makePoster(_ asset: AVAsset) async {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        guard let (image, _) = try? await generator.image(at: .zero) else { return }
        poster = NSImage(cgImage: image, size: .zero)
        guard settings.syncSystemWallpaper else { return }

        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else { return }
        let folder = AnimatedImageConverter.cacheDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Nom unique : macOS met en cache les fonds d'écran par chemin.
        let url = folder.appendingPathComponent("poster-\(Int(Date().timeIntervalSince1970)).jpg")
        guard (try? data.write(to: url)) != nil else { return }

        saveOriginalWallpapers()
        for screen in NSScreen.screens {
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                .allowClipping: true,
            ])
        }
        cleanOldFiles(keeping: url)
    }

    private func saveOriginalWallpapers() {
        let key = "originalWallpapers"
        guard UserDefaults.standard.dictionary(forKey: key) == nil else { return }
        var originals: [String: String] = [:]
        for screen in NSScreen.screens {
            if let url = NSWorkspace.shared.desktopImageURL(for: screen) {
                originals[screen.localizedName] = url.path
            }
        }
        UserDefaults.standard.set(originals, forKey: key)
    }

    private func restoreSystemWallpaper() {
        let key = "originalWallpapers"
        guard let originals = UserDefaults.standard.dictionary(forKey: key) as? [String: String] else { return }
        for screen in NSScreen.screens {
            guard let path = originals[screen.localizedName] ?? originals.values.first else { continue }
            try? NSWorkspace.shared.setDesktopImageURL(URL(fileURLWithPath: path), for: screen, options: [:])
        }
        UserDefaults.standard.removeObject(forKey: key)
    }

    private func cleanOldFiles(keeping current: URL) {
        let folder = AnimatedImageConverter.cacheDirectory
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in files where (file.lastPathComponent.hasPrefix("poster-") || file.lastPathComponent.hasPrefix("still-"))
            && file != current {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
