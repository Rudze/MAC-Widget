# MacWidget

App de barre des menus ultra légère + widgets natifs macOS (WidgetKit), tout en blanc.

| Widget | Tailles | Source |
|---|---|---|
| Horloge | S M L XL | sans fond, police / épaisseur / couleur façon écran verrouillé iPhone |
| Ressources | S M L | processeur, mémoire, stockage, batterie, température (relevé par l'extension ~5 min) |
| GitHub | S M L | graphe de contributions + derniers commits (jeton facultatif dans le trousseau) |
| Batteries | S M L | Mac (IOKit), Magic Keyboard/Mouse/Trackpad (IORegistry), AirPods/casques (IOBluetooth, repli `system_profiler`) |
| Calendrier | S M L | EventKit, 14 jours, sélection des calendriers |
| Cadre photo 1–3 | S M L XL | photos recadrées par taille, diaporama, fond réglable derrière les PNG transparents |

Plus un **fond d'écran** : image fixe (JPG, PNG, HEIC… appliquée par macOS lui-même), vidéo (MP4/MOV/HEVC) ou image animée (GIF/WebP/APNG convertie une fois en H.264).

## Compiler / installer

Pas besoin de Xcode, les Command Line Tools suffisent :

```bash
./build.sh               # compile, signe (certificat local), installe dans /Applications, lance
./build.sh --no-install  # juste le bundle, dans ~/Library/Caches/MacWidget-build
SIGN_IDENTITY="Apple Development: toi@… (TEAMID)" ./build.sh   # signature avec ton identifiant Apple
```

Par défaut, `tools/signing-identity.sh` crée une fois un certificat local auto-signé dans un trousseau dédié
(`~/Library/Application Support/MacWidget-Signing`). La signature reste identique d'un build à l'autre,
donc les autorisations macOS (calendrier, Bluetooth) sont conservées. Le bundle est assemblé dans
`~/Library/Caches/MacWidget-build` car la synchro iCloud de Documents ajoute des attributs que codesign refuse.

Ajouter un widget : clic droit sur le bureau → **Modifier les widgets…** → **MacWidget**.

## Pourquoi c'est léger

- L'app (agent sans Dock) ne tourne que sur notifications : changement de source d'alimentation,
  connexion Bluetooth, modification du calendrier. Timer de secours toutes les 2 min (tolérance 30 s).
- Rechargement des widgets limité (budget WidgetKit) : immédiat seulement si un appareil apparaît
  ou change d'état de charge.
- Les photos sont pré-rendues en petits JPEG à la taille exacte du widget : l'extension ne fait que les afficher.
- Fond animé : un seul `AVPlayer` partagé par tous les écrans, décodage par la puce média,
  pause automatique si le bureau est recouvert, écran en veille / verrouillé, mode économie d'énergie
  (et en option sur batterie). La fenêtre de réglages est détruite à la fermeture.

## Architecture

```
App/        agent barre des menus (non sandboxé) : collecte + fond animé + réglages SwiftUI
Widgets/    extension WidgetKit (sandboxée, lecture seule de ~/Library/Application Support/MacWidget)
Shared/     modèles, chemins partagés, lecture batterie du Mac
```

Note : le SDK macOS 27 transforme `@State` en macro dont le plugin n'est livré qu'avec Xcode ;
`build.sh` utilise donc le SDK 26.x des Command Line Tools s'il est présent.

Limite : l'iPhone, l'iPad et l'Apple Watch ne partagent leur batterie qu'avec les widgets d'Apple (API privée).
