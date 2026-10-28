import AppKit
import SwiftUI
import WidgetKit

struct PhotoEntry: TimelineEntry {
    let date: Date
    let imagePath: String?
    /// PNG détouré : le fond du widget reste transparent, l'image porte sa propre couleur de fond.
    var transparent = false
}

struct PhotoProvider: TimelineProvider {
    let slot: Int

    func placeholder(in context: Context) -> PhotoEntry { PhotoEntry(date: .now, imagePath: nil) }

    func getSnapshot(in context: Context, completion: @escaping (PhotoEntry) -> Void) {
        let photos = self.photos()
        completion(photos.first.map { entry(.now, $0, context.family) } ?? PhotoEntry(date: .now, imagePath: nil))
    }

    /// Les photos sont déjà recadrées à la bonne taille par l'app :
    /// l'extension ne fait que lire un petit JPEG.
    func getTimeline(in context: Context, completion: @escaping (Timeline<PhotoEntry>) -> Void) {
        let state = SharedStore.read(PhotoLibraryState.self, from: SharedStore.photosFile)
        let slot = state?.slots[safe: self.slot] ?? PhotoSlot()
        let photos = slot.photos
        guard !photos.isEmpty else {
            completion(Timeline(entries: [PhotoEntry(date: .now, imagePath: nil)], policy: .never)); return
        }
        guard slot.interval > 0, photos.count > 1 else {
            completion(Timeline(entries: [entry(.now, photos[0], context.family)], policy: .never))
            return
        }
        let interval = Double(slot.interval)
        let period = floor(Date().timeIntervalSince1970 / interval)
        let entries = (0..<48).map { i -> PhotoEntry in
            let p = period + Double(i)
            let photo = photos[Int(p.truncatingRemainder(dividingBy: Double(photos.count)))]
            let date = i == 0 ? Date() : Date(timeIntervalSince1970: p * interval)
            return entry(date, photo, context.family)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func photos() -> [PhotoItem] {
        SharedStore.read(PhotoLibraryState.self, from: SharedStore.photosFile)?.slots[safe: slot]?.photos ?? []
    }

    private func entry(_ date: Date, _ item: PhotoItem, _ family: WidgetFamily) -> PhotoEntry {
        PhotoEntry(date: date, imagePath: path(item, family), transparent: item.hasAlpha)
    }

    private func path(_ item: PhotoItem, _ family: WidgetFamily) -> String {
        let format: PhotoFormat = switch family {
        case .systemSmall: .small
        case .systemLarge: .large
        case .systemExtraLarge: .extraLarge
        default: .medium
        }
        let render = SharedStore.photoRender(item, format)
        return FileManager.default.fileExists(atPath: render.path) ? render.path : SharedStore.photoSource(item).path
    }
}

struct PhotoView: View {
    let entry: PhotoEntry
    let slot: Int

    var body: some View {
        Group {
            if let path = entry.imagePath, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .fullColorResizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 26, weight: .light))
                    Text("Ajoute des photos\ndans MacWidget")
                        .font(.system(size: 12, weight: .medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.secondary)
                }
                .foregroundStyle(Theme.primary)
            }
        }
        .containerBackground(for: .widget) { entry.transparent && entry.imagePath != nil ? Color.clear : Color.black }
        .widgetURL(URL(string: "macwidget://photos/\(slot)"))
    }
}

private func photoConfiguration(slot: Int) -> some WidgetConfiguration {
    StaticConfiguration(kind: WidgetKinds.photo(slot), provider: PhotoProvider(slot: slot)) { entry in
        PhotoView(entry: entry, slot: slot)
    }
    // Chaînes déjà construites : WidgetKit refuse un Text localisé avec interpolation.
    .configurationDisplayName(String("Cadre photo \(slot + 1)"))
    .description(String("Les photos du cadre \(slot + 1), placées comme tu veux dans MacWidget."))
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    .contentMarginsDisabled()
}

struct PhotoWidget1: Widget { var body: some WidgetConfiguration { photoConfiguration(slot: 0) } }
struct PhotoWidget2: Widget { var body: some WidgetConfiguration { photoConfiguration(slot: 1) } }
struct PhotoWidget3: Widget { var body: some WidgetConfiguration { photoConfiguration(slot: 2) } }

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
