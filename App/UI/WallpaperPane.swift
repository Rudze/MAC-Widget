import SwiftUI
import UniformTypeIdentifiers

struct WallpaperPane: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var wallpaper: WallpaperController
    @State private var dropTargeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PaneHeader(title: "Fond d'écran",
                           subtitle: "Image (JPG, PNG, HEIC…), vidéo (MP4, MOV, HEVC) ou image animée (GIF, WebP, APNG).")

                preview

                HStack {
                    Toggle("Activer", isOn: $settings.wallpaperEnabled)
                        .toggleStyle(.switch)
                        .disabled(settings.wallpaperPath == nil)
                    Spacer()
                    Button("Choisir un fichier…", action: pick)
                }

                if wallpaper.status == .still {
                    Label {
                        Text("Une image fixe est affichée directement par macOS, comme un fond d'écran normal : aucune ressource utilisée. Ton fond d'origine est remis quand tu désactives.")
                    } icon: {
                        Image(systemName: "bolt.badge.checkmark")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                } else {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Mettre en pause sur batterie", isOn: $settings.pauseOnBattery)
                            Toggle("Mettre en pause en mode économie d'énergie", isOn: $settings.pauseInLowPower)
                            Toggle("Utiliser la première image comme fond d'écran système", isOn: $settings.syncSystemWallpaper)
                            Text("Visible sur l'écran verrouillé et dans Mission Control. Ton fond d'origine est remis quand tu désactives.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                    }

                    Label {
                        Text("Les GIF sont convertis une fois en vidéo, décodée par la puce média du Mac. La lecture s'arrête toute seule quand le bureau est caché par des fenêtres, en plein écran, écran éteint ou verrouillé.")
                    } icon: {
                        Image(systemName: "bolt.badge.checkmark")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
    }

    private var preview: some View {
        ZStack {
            if let poster = wallpaper.poster {
                Image(nsImage: poster).resizable().scaledToFill()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "play.rectangle.on.rectangle").font(.system(size: 34, weight: .light))
                    Text("Glisse une image, une vidéo ou un GIF ici")
                }
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 6) {
                Circle().fill(statusColor).frame(width: 7, height: 7)
                Text(statusLine).lineLimit(1)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(10)
        }
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(dropTargeted ? Color.accentColor : .clear, lineWidth: 2))
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            _ = providers.first?.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { wallpaper.choose(url) }
            }
            return true
        }
    }

    private var statusLine: String {
        let name = settings.wallpaperPath.map { URL(fileURLWithPath: $0).lastPathComponent }
        return [name, wallpaper.status.text].compactMap { $0 }.joined(separator: " — ")
    }

    private var statusColor: Color {
        switch wallpaper.status {
        case .playing, .still: .green
        case .preparing, .paused: .orange
        case .failed: .red
        case .off: .gray
        }
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = WallpaperController.supportedTypes
        panel.message = "Choisis une image, une vidéo ou une image animée"
        if panel.runModal() == .OK, let url = panel.url { wallpaper.choose(url) }
    }
}
