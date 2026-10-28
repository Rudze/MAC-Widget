import Foundation
import CoreGraphics

enum WidgetKinds {
    static let battery = "com.rudy.macwidget.battery"
    static let clock = "com.rudy.macwidget.clock"
    static let calendar = "com.rudy.macwidget.calendar"
    static let github = "com.rudy.macwidget.github"
    static let system = "com.rudy.macwidget.system"
    static let music = "com.rudy.macwidget.music"
    static let photoSlotCount = 3
    static func photo(_ slot: Int) -> String { "com.rudy.macwidget.photo\(slot + 1)" }
}

// MARK: - Batteries

enum DeviceKind: String, Codable {
    case mac, keyboard, mouse, trackpad, headphones, earbuds, earbudsCase, speaker, controller, other

    var symbol: String {
        switch self {
        case .mac: "laptopcomputer"
        case .keyboard: "keyboard"
        case .mouse: "magicmouse.fill"
        case .trackpad: "hand.point.up.left.fill"
        case .headphones: "headphones"
        case .earbuds: "airpodspro"
        case .earbudsCase: "airpodspro.chargingcase.wireless"
        case .speaker: "hifispeaker.fill"
        case .controller: "gamecontroller.fill"
        case .other: "battery.100percent"
        }
    }

    var sortOrder: Int {
        switch self {
        case .mac: 0
        case .earbuds: 1
        case .earbudsCase: 2
        case .headphones: 3
        case .keyboard: 4
        case .mouse: 5
        case .trackpad: 6
        default: 7
        }
    }
}

struct BatteryDevice: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var kind: DeviceKind
    var level: Int
    var isCharging: Bool
}

struct BatterySnapshot: Codable {
    var devices: [BatteryDevice]
    var updated: Date
}

// MARK: - Calendrier

struct CalendarEvent: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String?
}

struct CalendarSnapshot: Codable {
    var authorized: Bool
    var events: [CalendarEvent]
    var updated: Date
}

// MARK: - Photos

enum PhotoFormat: String, Codable, CaseIterable, Identifiable {
    case small, medium, large, extraLarge

    var id: String { rawValue }

    /// Taille en pixels (@2x) des widgets macOS.
    var pixelSize: CGSize {
        switch self {
        case .small: CGSize(width: 340, height: 340)
        case .medium: CGSize(width: 728, height: 340)
        case .large: CGSize(width: 728, height: 764)
        case .extraLarge: CGSize(width: 1538, height: 764)
        }
    }

    var aspect: CGFloat { pixelSize.width / pixelSize.height }

    var label: String {
        switch self {
        case .small: "Petit"
        case .medium: "Moyen"
        case .large: "Grand"
        case .extraLarge: "Très grand"
        }
    }
}

/// Cadrage d'une photo : zoom (1 = remplit le widget, < 1 possible pour un PNG détouré) et décalage
/// exprimé en fraction de la taille du widget.
struct PhotoFraming: Codable, Hashable {
    var zoom: Double = 1
    var offsetX: Double = 0
    var offsetY: Double = 0
}

struct PhotoItem: Codable, Identifiable, Hashable {
    var id: String
    var pixelWidth: Int
    var pixelHeight: Int
    var framings: [String: PhotoFraming] = [:]
    /// Image avec transparence (PNG détouré…) : stockée en PNG, fond réglable.
    var hasAlpha = false
    var fillHex = "#000000"
    var fillOpacity = 0.0

    var fileExtension: String { hasAlpha ? "png" : "jpg" }
    /// Zoom arrière autorisé seulement quand le vide autour reste transparent / coloré.
    var minZoom: Double { hasAlpha ? 0.3 : 1 }

    func framing(for format: PhotoFormat) -> PhotoFraming { framings[format.rawValue] ?? PhotoFraming() }

    init(id: String, pixelWidth: Int, pixelHeight: Int, hasAlpha: Bool) {
        self.id = id
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.hasAlpha = hasAlpha
    }

    // Clés absentes tolérées : les photos importées avant cette version restent lisibles.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        pixelWidth = try c.decode(Int.self, forKey: .pixelWidth)
        pixelHeight = try c.decode(Int.self, forKey: .pixelHeight)
        framings = try c.decodeIfPresent([String: PhotoFraming].self, forKey: .framings) ?? [:]
        hasAlpha = try c.decodeIfPresent(Bool.self, forKey: .hasAlpha) ?? false
        fillHex = try c.decodeIfPresent(String.self, forKey: .fillHex) ?? "#000000"
        fillOpacity = try c.decodeIfPresent(Double.self, forKey: .fillOpacity) ?? 0
    }
}

struct PhotoSlot: Codable, Hashable {
    var photos: [PhotoItem] = []
    /// Secondes entre deux photos, 0 = fixe.
    var interval: Int = 1800
}

struct PhotoLibraryState: Codable {
    var slots: [PhotoSlot] = Array(repeating: PhotoSlot(), count: WidgetKinds.photoSlotCount)
}

/// Calcul partagé entre l'éditeur (points) et le rendu final (pixels).
enum PhotoGeometry {
    static func drawnSize(image: CGSize, frame: CGSize, zoom: Double) -> CGSize {
        let base = max(frame.width / image.width, frame.height / image.height)
        let s = base * CGFloat(zoom)
        return CGSize(width: image.width * s, height: image.height * s)
    }

    /// Image plus grande que le cadre : elle doit le couvrir. Plus petite : elle doit y rester.
    static func clamped(_ f: PhotoFraming, image: CGSize, frame: CGSize, minZoom: Double = 1) -> PhotoFraming {
        var f = f
        f.zoom = min(max(f.zoom, minZoom), 5)
        let d = drawnSize(image: image, frame: frame, zoom: f.zoom)
        let maxX = Double(abs(d.width - frame.width) / 2 / frame.width)
        let maxY = Double(abs(d.height - frame.height) / 2 / frame.height)
        f.offsetX = min(max(f.offsetX, -maxX), maxX)
        f.offsetY = min(max(f.offsetY, -maxY), maxY)
        return f
    }
}

// MARK: - GitHub

struct ContributionDay: Codable, Hashable {
    /// "yyyy-MM-dd", tel que fourni par GitHub.
    var date: String
    var count: Int
    /// 0 (rien) à 4 (le plus actif), comme les nuances du graphe GitHub.
    var level: Int
}

struct GitHubCommit: Codable, Hashable, Identifiable {
    var id: String
    var repo: String
    var message: String
    var date: Date
}

struct GitHubSnapshot: Codable {
    var username: String
    var days: [ContributionDay]
    var commits: [GitHubCommit]
    var updated: Date

    var total: Int { days.reduce(0) { $0 + $1.count } }
    var today: Int { days.last?.count ?? 0 }

    /// Jours consécutifs avec au moins une contribution ; aujourd'hui vide ne casse pas la série.
    var streak: Int {
        var days = self.days[...]
        if days.last?.count == 0 { days = days.dropLast() }
        var n = 0
        for day in days.reversed() {
            guard day.count > 0 else { break }
            n += 1
        }
        return n
    }
}

// MARK: - Musique

struct NowPlaying: Codable, Hashable {
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    var duration: Double
    /// Position au moment `positionDate` : le widget en déduit la progression en direct.
    var position: Double
    var positionDate: Date
    var artworkFile: String?

    var startDate: Date { positionDate.addingTimeInterval(-position) }
    var endDate: Date { startDate.addingTimeInterval(max(duration, 1)) }
    var progress: Double { duration > 0 ? min(max(position / duration, 0), 1) : 0 }
}

enum MusicCommand: String {
    case playpause, next, previous
}

// MARK: - Clic sur un widget

/// App ou page ouverte par un clic sur un widget (`macwidget://open/<cible>`).
enum WidgetLink: String {
    case calendar, activity, github

    var url: URL { URL(string: "macwidget://open/\(rawValue)")! }
}
