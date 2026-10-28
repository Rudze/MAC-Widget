import Foundation

/// Dossier partagé entre l'app et l'extension widgets.
/// L'extension (sandboxée) y a un accès en lecture seule via une exception d'entitlement,
/// d'où le chemin calculé depuis le vrai dossier utilisateur et non depuis le conteneur.
enum SharedStore {
    static let directory: URL = {
        var home = NSHomeDirectory()
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            home = String(cString: dir)
        }
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Library/Application Support/MacWidget", isDirectory: true)
    }()

    static let photosDirectory = directory.appendingPathComponent("Photos", isDirectory: true)

    static let batteryFile = "battery.json"
    static let calendarFile = "calendar.json"
    static let photosFile = "photos.json"
    static let githubFile = "github.json"
    static let musicFile = "music.json"

    static func photoFolder(_ id: String) -> URL { photosDirectory.appendingPathComponent(id, isDirectory: true) }
    static func photoSource(_ item: PhotoItem) -> URL {
        photoFolder(item.id).appendingPathComponent("source.\(item.fileExtension)")
    }
    static func photoRender(_ item: PhotoItem, _ format: PhotoFormat) -> URL {
        photoFolder(item.id).appendingPathComponent("\(format.rawValue).\(item.fileExtension)")
    }

    static func read<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(T.self, from: data)
    }

    static func write<T: Encodable>(_ value: T, to name: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }
}
