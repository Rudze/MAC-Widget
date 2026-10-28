import SwiftUI
import UniformTypeIdentifiers

struct PhotosPane: View {
    @EnvironmentObject private var library: PhotoLibrary
    @EnvironmentObject private var navigation: Navigation
    @State private var selectedID: String?
    @State private var format: PhotoFormat = .medium
    @State private var dropTargeted = false

    private let intervals: [(String, Int)] = [
        ("Fixe", 0), ("5 min", 300), ("15 min", 900), ("30 min", 1800),
        ("1 h", 3600), ("3 h", 10_800), ("1 jour", 86_400),
    ]

    private var slot: Int { navigation.photoSlot }
    private var photos: [PhotoItem] { library.state.slots[slot].photos }
    private var selected: PhotoItem? { photos.first { $0.id == selectedID } ?? photos.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                PaneHeader(title: "Cadres photo",
                           subtitle: "Chaque cadre correspond au widget « Cadre photo » du même numéro.")
                Picker("", selection: $navigation.photoSlot) {
                    ForEach(0..<WidgetKinds.photoSlotCount, id: \.self) { Text("Cadre \($0 + 1)").tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            HStack(spacing: 20) {
                strip
                    .frame(width: 210)
                editor
            }
        }
        .padding(24)
        .onChange(of: navigation.photoSlot) { selectedID = nil }
    }

    // MARK: Liste des photos

    private var strip: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                    ForEach(photos) { item in
                        thumbnail(item)
                    }
                    Button(action: pickPhotos) {
                        VStack(spacing: 4) {
                            Image(systemName: library.importing ? "hourglass" : "plus")
                                .font(.title2)
                            Text("Ajouter").font(.caption)
                        }
                        .frame(width: 92, height: 92)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(library.importing)
                }
                .padding(4)
            }
            .background(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(dropTargeted ? Color.accentColor : .clear, lineWidth: 2))
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted, perform: handleDrop)

            Picker("Changer de photo", selection: Binding(
                get: { library.state.slots[slot].interval },
                set: { library.setInterval($0, slot: slot) })) {
                ForEach(intervals, id: \.1) { Text($0.0).tag($0.1) }
            }
            Text("Glisse des photos ici depuis le Finder ou Photos.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func thumbnail(_ item: PhotoItem) -> some View {
        let isSelected = item.id == selected?.id
        return Group {
            if let image = library.thumbnail(item) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Color.gray.opacity(0.2)
            }
        }
        .frame(width: 92, height: 92)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3))
        .contentShape(Rectangle())
        .onTapGesture { selectedID = item.id }
        .contextMenu {
            Button("Déplacer avant") { library.move(item, in: slot, by: -1) }
            Button("Déplacer après") { library.move(item, in: slot, by: 1) }
            Divider()
            Button("Retirer du cadre", role: .destructive) { library.remove(item, from: slot) }
        }
    }

    // MARK: Éditeur de cadrage

    @ViewBuilder private var editor: some View {
        if let item = selected, let image = library.source(item) {
            VStack(spacing: 14) {
                Picker("", selection: $format) {
                    ForEach(PhotoFormat.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                FramingEditor(image: image,
                              imageSize: CGSize(width: item.pixelWidth, height: item.pixelHeight),
                              aspect: format.aspect,
                              framing: item.framing(for: format),
                              minZoom: item.minZoom,
                              fill: item.hasAlpha ? fillColor(item) : nil) { framing in
                    library.setFraming(framing, for: item.id, format: format, slot: slot)
                }
                .id("\(item.id)-\(format.rawValue)")

                if item.hasAlpha { fillControls(item) }

                HStack {
                    Text("Glisse pour déplacer · pince ou défile pour zoomer")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Recentrer") {
                        library.setFraming(PhotoFraming(), for: item.id, format: format, slot: slot)
                    }
                    Button("Retirer", role: .destructive) {
                        library.remove(item, from: slot)
                        selectedID = nil
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "photo.badge.plus").font(.system(size: 40, weight: .light))
                Text("Ajoute des photos à ce cadre").font(.headline)
                Button("Choisir des photos…", action: pickPhotos)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Fond des PNG transparents

    private func fillColor(_ item: PhotoItem) -> Color {
        let c = HexColor.components(item.fillHex)
        return Color(red: c.red, green: c.green, blue: c.blue).opacity(item.fillOpacity)
    }

    private func fillControls(_ item: PhotoItem) -> some View {
        let color = Binding<Color>(
            get: {
                let c = HexColor.components(item.fillHex)
                return Color(red: c.red, green: c.green, blue: c.blue)
            },
            set: { newValue in
                let ns = NSColor(newValue).usingColorSpace(.sRGB) ?? .black
                let hex = HexColor.string(red: Double(ns.redComponent), green: Double(ns.greenComponent),
                                          blue: Double(ns.blueComponent))
                // Choisir une couleur alors que le fond est invisible : on le rend opaque.
                library.setFill(hex: hex, opacity: item.fillOpacity == 0 ? 1 : item.fillOpacity, for: item.id, slot: slot)
            })
        let opacity = Binding<Double>(
            get: { item.fillOpacity },
            set: { library.setFill(hex: item.fillHex, opacity: $0, for: item.id, slot: slot) })

        return HStack(spacing: 12) {
            Image(systemName: "square.dashed").foregroundStyle(.secondary)
            ColorPicker("Fond transparent", selection: color, supportsOpacity: false)
            Slider(value: opacity, in: 0...1)
                .frame(width: 160)
            Text(item.fillOpacity == 0 ? "Transparent" : "\(Int(item.fillOpacity * 100)) %")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
        }
        .font(.callout)
    }

    // MARK: Import

    private func pickPhotos() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image]
        panel.message = "Choisis les photos du cadre \(slot + 1)"
        if panel.runModal() == .OK { library.add(panel.urls, to: slot) }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let slot = self.slot
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                DispatchQueue.main.async {
                    if let url { urls.append(url) }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) { library.add(urls, to: slot) }
        return true
    }
}

/// Aperçu à la forme exacte du widget : on déplace et on zoome la photo dedans.
/// Le rendu final est calculé avec la même géométrie (PhotoGeometry).
struct FramingEditor: View {
    let image: NSImage
    let imageSize: CGSize
    let aspect: CGFloat
    let minZoom: Double
    /// Couleur derrière un PNG transparent (nil pour une photo classique).
    let fill: Color?
    @State var framing: PhotoFraming
    let onCommit: (PhotoFraming) -> Void

    @State private var dragStart: PhotoFraming?
    @State private var zoomStart: Double?
    @State private var commitWork: DispatchWorkItem?

    init(image: NSImage, imageSize: CGSize, aspect: CGFloat, framing: PhotoFraming,
         minZoom: Double = 1, fill: Color? = nil, onCommit: @escaping (PhotoFraming) -> Void) {
        self.image = image
        self.imageSize = imageSize
        self.aspect = aspect
        self.minZoom = minZoom
        self.fill = fill
        _framing = State(initialValue: framing)
        self.onCommit = onCommit
    }

    var body: some View {
        GeometryReader { geo in
            let frame = fit(in: geo.size)
            let drawn = PhotoGeometry.drawnSize(image: imageSize, frame: frame, zoom: framing.zoom)
            ZStack {
                if let fill {
                    Checkerboard()
                    fill
                }
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: drawn.width, height: drawn.height)
                    .offset(x: framing.offsetX * frame.width, y: framing.offsetY * frame.height)
            }
            .frame(width: frame.width, height: frame.height)
            .clipShape(RoundedRectangle(cornerRadius: min(frame.width, frame.height) * 0.13, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
            .contentShape(Rectangle())
            .gesture(drag(frame))
            .simultaneousGesture(magnify(frame))
            .background(ScrollZoom { delta in
                update(frame) { $0.zoom *= 1 + delta * 0.01 }
            })
            .position(x: geo.size.width / 2, y: geo.size.height / 2)

            VStack {
                Spacer()
                Slider(value: Binding(get: { framing.zoom },
                                      set: { z in update(frame) { $0.zoom = z } }),
                       in: minZoom...5) {
                    Image(systemName: "plus.magnifyingglass")
                }
                .frame(width: 240)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func fit(in size: CGSize) -> CGSize {
        let available = CGSize(width: size.width - 20, height: size.height - 60)
        let width = min(available.width, available.height * aspect)
        return CGSize(width: max(width, 50), height: max(width / aspect, 50))
    }

    private func update(_ frame: CGSize, _ change: (inout PhotoFraming) -> Void) {
        var f = framing
        change(&f)
        framing = PhotoGeometry.clamped(f, image: imageSize, frame: frame, minZoom: minZoom)
        scheduleCommit()
    }

    /// Le rendu JPEG est relancé 0,3 s après le dernier mouvement, pas à chaque pixel.
    private func scheduleCommit() {
        commitWork?.cancel()
        let value = framing
        let work = DispatchWorkItem { onCommit(value) }
        commitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func drag(_ frame: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = dragStart ?? framing
                dragStart = start
                update(frame) {
                    $0.offsetX = start.offsetX + value.translation.width / frame.width
                    $0.offsetY = start.offsetY + value.translation.height / frame.height
                }
            }
            .onEnded { _ in dragStart = nil }
    }

    private func magnify(_ frame: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                let start = zoomStart ?? framing.zoom
                zoomStart = start
                update(frame) { $0.zoom = start * scale }
            }
            .onEnded { _ in zoomStart = nil }
    }
}

/// Zoom à la molette / deux doigts sur le trackpad.
private struct ScrollZoom: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView { ScrollView(onScroll: onScroll) }
    func updateNSView(_ view: NSView, context: Context) { (view as? ScrollView)?.onScroll = onScroll }

    final class ScrollView: NSView {
        var onScroll: (CGFloat) -> Void
        private var monitor: Any?

        init(onScroll: @escaping (CGFloat) -> Void) {
            self.onScroll = onScroll
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return event }
                self.onScroll(event.scrollingDeltaY)
                return nil
            }
        }
    }
}

/// Damier gris, la convention pour montrer qu'une zone est transparente.
private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 10
            for row in 0..<Int(ceil(size.height / cell)) {
                for col in 0..<Int(ceil(size.width / cell)) where (row + col) % 2 == 0 {
                    context.fill(Path(CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)),
                                 with: .color(.gray.opacity(0.35)))
                }
            }
        }
        .background(Color.gray.opacity(0.12))
    }
}
