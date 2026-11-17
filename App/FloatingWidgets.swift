import AppKit
import Combine
import SwiftUI
import WidgetKit

/// Widgets « flottants » (option, désactivée par défaut) : les mêmes vues que dans la galerie,
/// mais dans des fenêtres transparentes posées sur le bureau. Là, « Aucun » fond est réellement
/// transparent, ce que WidgetKit ne permet pas (macOS y met toujours un fond).
enum FloatingKind: String, Codable, CaseIterable, Identifiable {
    case clock, battery, calendar, system, github, music, photo1, photo2, photo3

    var id: String { rawValue }

    /// Ce qu'ouvre un clic ; nil = le widget laisse passer les clics vers le bureau.
    var link: WidgetLink? {
        switch self {
        case .calendar: .calendar
        case .system: .activity
        case .github: .github
        default: nil
        }
    }

    var photoSlot: Int? {
        switch self {
        case .photo1: 0
        case .photo2: 1
        case .photo3: 2
        default: nil
        }
    }

    var label: String {
        switch self {
        case .clock: "Horloge"
        case .battery: "Batteries"
        case .calendar: "Calendrier"
        case .system: "Ressources"
        case .github: "GitHub"
        case .music: "Musique"
        case .photo1, .photo2, .photo3: "Cadre photo \((photoSlot ?? 0) + 1)"
        }
    }

    var symbol: String {
        switch self {
        case .clock: "clock"
        case .battery: "battery.75percent"
        case .calendar: "calendar"
        case .system: "cpu"
        case .github: "chevron.left.forwardslash.chevron.right"
        case .music: "music.note"
        case .photo1, .photo2, .photo3: "photo"
        }
    }
}

enum FloatingSize: String, Codable, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }
    var label: String { self == .small ? "Petit" : self == .medium ? "Moyen" : "Grand" }

    var photoFormat: PhotoFormat {
        switch self {
        case .small: .small
        case .medium: .medium
        case .large: .large
        }
    }

    var family: WidgetFamily {
        switch self {
        case .small: .systemSmall
        case .medium: .systemMedium
        case .large: .systemLarge
        }
    }

    /// Mêmes dimensions que les widgets macOS.
    var size: CGSize {
        switch self {
        case .small: CGSize(width: 170, height: 170)
        case .medium: CGSize(width: 364, height: 170)
        case .large: CGSize(width: 364, height: 382)
        }
    }
}

struct FloatingItem: Codable, Hashable, Identifiable {
    var kind: FloatingKind
    var enabled = false
    var size = FloatingSize.medium
    var id: String { kind.rawValue }
}

@MainActor
final class FloatingWidgets: ObservableObject {
    /// Interrupteur général de la fonction.
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "floatingEnabled")
            if !isEnabled { editing = false }
            apply()
        }
    }
    @Published var items: [FloatingItem] { didSet { save(); apply() } }
    @Published var editing = false { didSet { apply() } }

    let data = FloatingData()
    private let battery: BatteryMonitor
    private let github: GitHubSync
    private let appearance: AppearanceStore
    private let photos: PhotoLibrary
    private let music: MusicController
    private var panels: [FloatingKind: NSPanel] = [:]
    /// Ancien format (coordonnées absolues), lu seulement pour convertir la config existante.
    private var legacyOrigins: [String: [Double]]
    private var placements: [String: FloatingPlacement]
    private var isPlacing = false
    private var observers = Set<AnyCancellable>()

    init(battery: BatteryMonitor, github: GitHubSync, appearance: AppearanceStore, photos: PhotoLibrary,
         music: MusicController) {
        self.music = music
        self.battery = battery
        self.github = github
        self.appearance = appearance
        self.photos = photos
        isEnabled = UserDefaults.standard.bool(forKey: "floatingEnabled")
        let saved = (UserDefaults.standard.data(forKey: "floatingItems"))
            .flatMap { try? JSONDecoder().decode([FloatingItem].self, from: $0) } ?? []
        items = FloatingKind.allCases.map { kind in
            saved.first { $0.kind == kind } ?? FloatingItem(kind: kind, size: kind == .clock || kind.photoSlot != nil ? .medium : .small)
        }
        legacyOrigins = UserDefaults.standard.dictionary(forKey: "floatingOrigins") as? [String: [Double]] ?? [:]
        placements = UserDefaults.standard.data(forKey: "floatingPlacements")
            .flatMap { try? JSONDecoder().decode([String: FloatingPlacement].self, from: $0) } ?? [:]
    }

    func start() {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            // macOS déplace d'abord les fenêtres lui-même : on replace une fois l'écran stabilisé.
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.apply() }
            .store(in: &observers)
        apply()
    }

    /// Au moins un widget flottant réellement affiché.
    var anyShown: Bool { isEnabled && items.contains { $0.enabled } }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: "floatingItems") }
    }

    // MARK: Fenêtres

    private func apply() {
        data.needsSystemStats = isEnabled && items.contains { $0.enabled && $0.kind == .system }
        data.isActive = anyShown
        for item in items {
            if isEnabled && item.enabled {
                show(item)
            } else if let panel = panels.removeValue(forKey: item.kind) {
                panel.orderOut(nil)
            }
        }
    }

    private func show(_ item: FloatingItem) {
        let size = item.size.size
        let panel = panels[item.kind] ?? makePanel(item.kind)
        panels[item.kind] = panel

        let root = FloatingRoot(kind: item.kind, size: item.size, editing: editing, data: data,
                                battery: battery, github: github, appearance: appearance, photos: photos, music: music)
        if let host = panel.contentView as? NSHostingView<FloatingRoot> {
            host.rootView = root
        } else {
            panel.contentView = NSHostingView(rootView: root)
        }

        isPlacing = true
        panel.setFrame(frame(for: item.kind, size: size), display: true)
        isPlacing = false
        // Lecteur et widgets qui ouvrent une app restent cliquables ; les autres laissent passer les clics.
        panel.ignoresMouseEvents = !editing && item.kind != .music && item.kind.link == nil
        panel.orderFrontRegardless()
    }

    private func makePanel(_ kind: FloatingKind) -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        // Juste au-dessus des icônes du bureau, sous toutes les fenêtres d'apps.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none

        NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: panel)
            .sink { [weak self, weak panel] _ in
                // Seuls les déplacements faits à la main comptent, pas ceux de macOS au changement d'écran.
                guard let self, let panel, self.editing, !self.isPlacing else { return }
                self.placements[kind.rawValue] = FloatingPlacement(frame: panel.frame)
                self.savePlacements()
            }
            .store(in: &observers)
        return panel
    }

    // MARK: Placement

    /// Position du widget : en % de son écran s'il est branché, sinon de l'écran principal,
    /// toujours ramenée entièrement dans la zone visible (hors barre des menus et Dock).
    private func frame(for kind: FloatingKind, size: CGSize) -> CGRect {
        let screens = NSScreen.screens
        var topLeft: CGPoint
        var screen: NSScreen?
        if let placement = placements[kind.rawValue] {
            screen = screens.first { $0.displayID == placement.display } ?? screens.first
            topLeft = placement.topLeft(in: screen?.visibleFrame ?? .zero)
        } else if let legacy = legacyOrigins[kind.rawValue], legacy.count == 2 {
            topLeft = CGPoint(x: legacy[0], y: legacy[1])
            screen = screens.first { $0.frame.insetBy(dx: -2, dy: -2).contains(topLeft) }
            if let screen {
                // Conversion unique de l'ancienne position, sur l'écran où elle se trouve.
                placements[kind.rawValue] = FloatingPlacement(topLeft: topLeft, screen: screen)
                savePlacements()
            } else {
                screen = screens.first
            }
        } else {
            screen = NSScreen.main ?? screens.first
            topLeft = defaultTopLeft(kind, in: screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900))
        }
        guard let visible = screen?.visibleFrame else {
            return CGRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height)
        }
        let x = min(max(topLeft.x, visible.minX), visible.maxX - size.width)
        let top = min(max(topLeft.y, visible.minY + size.height), visible.maxY)
        return CGRect(x: x, y: top - size.height, width: size.width, height: size.height)
    }

    private func savePlacements() {
        if let data = try? JSONEncoder().encode(placements) { UserDefaults.standard.set(data, forKey: "floatingPlacements") }
    }

    /// Placement initial : empilés en colonne en haut à droite de l'écran, sans chevauchement.
    private func defaultTopLeft(_ kind: FloatingKind, in screen: CGRect) -> CGPoint {
        let above = items.prefix { $0.kind != kind }.filter(\.enabled)
        let offset = above.reduce(CGFloat(0)) { $0 + $1.size.size.height + 16 }
        return CGPoint(x: screen.maxX - 384, y: screen.maxY - 20 - offset)
    }
}

/// Coin haut-gauche d'un widget flottant, en fraction de la zone visible de son écran
/// (0 = bord gauche / haut, 1 = bord droit / bas) : il garde sa place relative d'un écran à l'autre.
struct FloatingPlacement: Codable {
    var display: UInt32
    var x: Double
    var y: Double

    init(topLeft: CGPoint, screen: NSScreen) {
        let visible = screen.visibleFrame
        display = screen.displayID
        x = min(max((topLeft.x - visible.minX) / max(visible.width, 1), 0), 1)
        y = min(max((visible.maxY - topLeft.y) / max(visible.height, 1), 0), 1)
    }

    init(frame: CGRect) {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(center) }
            ?? NSScreen.screens.max { $0.frame.intersection(frame).area < $1.frame.intersection(frame).area }
        self.init(topLeft: CGPoint(x: frame.minX, y: frame.maxY), screen: screen ?? NSScreen.main!)
    }

    func topLeft(in visible: CGRect) -> CGPoint {
        CGPoint(x: visible.minX + x * visible.width, y: visible.maxY - y * visible.height)
    }
}

private extension NSScreen {
    var displayID: UInt32 {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}

/// Données des widgets flottants, rafraîchies une fois par minute, calée sur le changement de minute.
@MainActor
final class FloatingData: ObservableObject {
    @Published private(set) var now = Date()
    @Published private(set) var system = SystemStats.placeholder
    @Published private(set) var calendar = SharedStore.read(CalendarSnapshot.self, from: SharedStore.calendarFile)

    var needsSystemStats = false { didSet { if needsSystemStats && !oldValue { sampleSystem() } } }
    var isActive = false { didSet { if isActive != oldValue { schedule() } } }

    private var timer: Timer?

    private func schedule() {
        timer?.invalidate()
        timer = nil
        guard isActive else { return }
        tick()
        let next = Calendar.current.dateInterval(of: .minute, for: Date())?.end ?? Date().addingTimeInterval(60)
        let timer = Timer(fire: next, interval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        now = Date()
        calendar = SharedStore.read(CalendarSnapshot.self, from: SharedStore.calendarFile)
        if needsSystemStats { sampleSystem() }
    }

    private func sampleSystem() {
        DispatchQueue.global(qos: .utility).async {
            let stats = SystemStats.sample()
            DispatchQueue.main.async { [weak self] in self?.system = stats }
        }
    }
}

struct FloatingRoot: View {
    let kind: FloatingKind
    let size: FloatingSize
    let editing: Bool
    @ObservedObject var data: FloatingData
    @ObservedObject var battery: BatteryMonitor
    @ObservedObject var github: GitHubSync
    @ObservedObject var appearance: AppearanceStore
    @ObservedObject var photos: PhotoLibrary
    @ObservedObject var music: MusicController

    var body: some View {
        content
            .contentShape(Rectangle())
            .onTapGesture {
                guard !editing, let link = kind.link else { return }
                NSWorkspace.shared.open(link.url) // repasse par le gestionnaire d'URL de l'app
            }
            .environment(\.floatingFamily, size.family)
            .frame(width: size.size.width, height: size.size.height)
            .overlay {
                if editing {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.06))
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        WindowDragArea()
                    }
                }
            }
    }

    @ViewBuilder private var content: some View {
        let a = appearance.value
        switch kind {
        case .clock:
            ClockView(entry: ClockEntry(date: data.now, appearance: a))
        case .battery:
            BatteryView(entry: BatteryEntry(date: data.now, devices: battery.devices, style: a.battery))
        case .calendar:
            let snapshot = data.calendar
            CalendarView(entry: CalendarEntry(date: data.now, authorized: snapshot?.authorized ?? false,
                                              events: (snapshot?.events ?? []).filter { $0.end > data.now },
                                              style: a.calendar))
        case .system:
            SystemView(entry: SystemEntry(date: data.now, stats: data.system, battery: MacBattery.read(), style: a.system))
        case .github:
            GitHubView(entry: GitHubEntry(date: data.now, snapshot: github.snapshot, style: a.github))
        case .music:
            MusicView(entry: MusicEntry(date: data.now, nowPlaying: music.nowPlaying, style: a.music))
                .environment(\.musicAction) { [music] in music.send($0) }
        case .photo1, .photo2, .photo3:
            FloatingPhoto(slot: kind.photoSlot ?? 0, size: size, now: data.now, library: photos)
        }
    }
}

/// Cadre photo flottant : mêmes images pré-recadrées et même diaporama que le widget de la galerie.
/// Un PNG dont le fond est à 0 % reste réellement transparent sur le bureau.
private struct FloatingPhoto: View {
    let slot: Int
    let size: FloatingSize
    let now: Date
    @ObservedObject var library: PhotoLibrary

    private var current: PhotoItem? {
        let slot = library.state.slots[slot]
        guard !slot.photos.isEmpty else { return nil }
        guard slot.interval > 0, slot.photos.count > 1 else { return slot.photos[0] }
        let period = Int(now.timeIntervalSince1970 / Double(slot.interval))
        return slot.photos[period % slot.photos.count]
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        if let item = current, let image = PhotoFileCache.shared.image(SharedStore.photoRender(item, size.photoFormat)) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size.size.width, height: size.size.height)
                .clipShape(shape)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle.angled").font(.system(size: 26, weight: .light))
                Text("Ajoute des photos\nau cadre \(slot + 1)")
                    .font(.system(size: 12, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.secondary)
            }
            .foregroundStyle(Theme.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.6), in: shape)
        }
    }
}

/// Évite de relire le JPEG à chaque minute ; la date de modification invalide l'entrée
/// quand l'éditeur réécrit le rendu après un recadrage.
@MainActor
private final class PhotoFileCache {
    static let shared = PhotoFileCache()
    private var entries: [String: (date: Date, image: NSImage)] = [:]

    func image(_ url: URL) -> NSImage? {
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        if let entry = entries[url.path], entry.date == date { return entry.image }
        guard let image = NSImage(contentsOf: url) else { return nil }
        entries[url.path] = (date, image)
        return image
    }
}

/// En mode « Déplacer », toute la surface du widget sert de poignée.
private struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
