import AppKit
import ImageIO
import UniformTypeIdentifiers
import WidgetKit

/// Gère les cadres photo : import (réduit à 2400 px), cadrage, et pré-rendu
/// d'un JPEG par taille de widget pour que l'extension reste minuscule en mémoire.
@MainActor
final class PhotoLibrary: ObservableObject {
    @Published private(set) var state: PhotoLibraryState
    @Published private(set) var importing = false

    private var thumbnails: [String: NSImage] = [:]
    private var sources: [String: NSImage] = [:]
    private var pendingFills: [String: DispatchWorkItem] = [:]

    init() {
        var state = SharedStore.read(PhotoLibraryState.self, from: SharedStore.photosFile) ?? PhotoLibraryState()
        while state.slots.count < WidgetKinds.photoSlotCount { state.slots.append(PhotoSlot()) }
        self.state = state
    }

    // MARK: Lecture

    func thumbnail(_ item: PhotoItem) -> NSImage? {
        if let image = thumbnails[item.id] { return image }
        let image = Self.downsample(SharedStore.photoSource(item), maxPixel: 320).map {
            NSImage(cgImage: $0, size: .zero)
        }
        thumbnails[item.id] = image
        return image
    }

    func source(_ item: PhotoItem) -> NSImage? {
        if let image = sources[item.id] { return image }
        let image = NSImage(contentsOf: SharedStore.photoSource(item))
        sources = [item.id: image].compactMapValues { $0 } // une seule grande image en mémoire
        return image
    }

    // MARK: Modifications

    func add(_ urls: [URL], to slot: Int) {
        importing = true
        Task.detached(priority: .userInitiated) {
            var items: [PhotoItem] = []
            for url in urls {
                if let item = Self.importPhoto(url) { items.append(item) }
            }
            let imported = items
            await MainActor.run {
                self.state.slots[slot].photos += imported
                self.importing = false
                self.save(slot: slot)
            }
        }
    }

    func remove(_ item: PhotoItem, from slot: Int) {
        state.slots[slot].photos.removeAll { $0.id == item.id }
        thumbnails[item.id] = nil
        sources[item.id] = nil
        try? FileManager.default.removeItem(at: SharedStore.photoFolder(item.id))
        save(slot: slot)
    }

    func move(_ item: PhotoItem, in slot: Int, by delta: Int) {
        guard let i = state.slots[slot].photos.firstIndex(of: item) else { return }
        let j = min(max(i + delta, 0), state.slots[slot].photos.count - 1)
        state.slots[slot].photos.swapAt(i, j)
        save(slot: slot)
    }

    func setInterval(_ seconds: Int, slot: Int) {
        state.slots[slot].interval = seconds
        save(slot: slot)
    }

    func setFraming(_ framing: PhotoFraming, for itemID: String, format: PhotoFormat, slot: Int) {
        guard let i = state.slots[slot].photos.firstIndex(where: { $0.id == itemID }) else { return }
        state.slots[slot].photos[i].framings[format.rawValue] = framing
        let item = state.slots[slot].photos[i]
        Task.detached(priority: .userInitiated) {
            Self.render(item, format: format)
            await MainActor.run { self.save(slot: slot) }
        }
    }

    /// Fond appliqué derrière les zones transparentes d'un PNG ; rendu regroupé pendant le réglage.
    func setFill(hex: String, opacity: Double, for itemID: String, slot: Int) {
        guard let i = state.slots[slot].photos.firstIndex(where: { $0.id == itemID }) else { return }
        state.slots[slot].photos[i].fillHex = hex
        state.slots[slot].photos[i].fillOpacity = opacity
        let item = state.slots[slot].photos[i]

        pendingFills[itemID]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task.detached(priority: .userInitiated) {
                let source = Self.downsample(SharedStore.photoSource(item), maxPixel: 2400)
                for format in PhotoFormat.allCases { Self.render(item, format: format, source: source) }
                await MainActor.run { self?.save(slot: slot) }
            }
        }
        pendingFills[itemID] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func save(slot: Int) {
        SharedStore.write(state, to: SharedStore.photosFile)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.photo(slot))
    }

    // MARK: Traitement d'image (hors thread principal)

    nonisolated private static func importPhoto(_ url: URL) -> PhotoItem? {
        guard let image = downsample(url, maxPixel: 2400) else { return nil }
        let item = PhotoItem(id: UUID().uuidString, pixelWidth: image.width, pixelHeight: image.height,
                             hasAlpha: hasTransparency(url))
        try? FileManager.default.createDirectory(at: SharedStore.photoFolder(item.id), withIntermediateDirectories: true)
        guard write(image, to: SharedStore.photoSource(item), quality: 0.9) else { return nil }
        for format in PhotoFormat.allCases { render(item, format: format, source: image) }
        return item
    }

    nonisolated static func render(_ item: PhotoItem, format: PhotoFormat, source: CGImage? = nil) {
        guard let image = source ?? downsample(SharedStore.photoSource(item), maxPixel: 2400) else { return }
        let out = format.pixelSize
        let imageSize = CGSize(width: image.width, height: image.height)
        let framing = PhotoGeometry.clamped(item.framing(for: format), image: imageSize, frame: out,
                                            minZoom: item.minZoom)
        let drawn = PhotoGeometry.drawnSize(image: imageSize, frame: out, zoom: framing.zoom)
        let rect = CGRect(x: (out.width - drawn.width) / 2 + framing.offsetX * out.width,
                          y: (out.height - drawn.height) / 2 - framing.offsetY * out.height,
                          width: drawn.width, height: drawn.height)

        guard let ctx = CGContext(data: nil, width: Int(out.width), height: Int(out.height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: item.hasAlpha ? CGImageAlphaInfo.premultipliedLast.rawValue
                                                            : CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
        ctx.interpolationQuality = .high
        if item.hasAlpha {
            let c = HexColor.components(item.fillHex)
            ctx.setFillColor(CGColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: item.fillOpacity))
        } else {
            ctx.setFillColor(.black)
        }
        ctx.fill(CGRect(origin: .zero, size: out))
        ctx.draw(image, in: rect)
        if let rendered = ctx.makeImage() {
            _ = write(rendered, to: SharedStore.photoRender(item, format), quality: 0.85)
        }
    }

    nonisolated static func downsample(_ url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    nonisolated private static func hasTransparency(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return false }
        return properties[kCGImagePropertyHasAlpha] as? Bool ?? false
    }

    /// PNG si l'image garde sa transparence (extension .png), JPEG sinon.
    nonisolated private static func write(_ image: CGImage, to url: URL, quality: Double) -> Bool {
        let type = url.pathExtension == "png" ? UTType.png : UTType.jpeg
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }
}
