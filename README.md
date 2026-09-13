# El Bouni Pièces Auto

Application Flutter (rouge, package `com.elbouni.ajalaks`) — assurance OCR +
identification de pièces auto pour la région d'El Bouni, Annaba.

> Cette version ne contient plus que la variante rouge "El Bouni".
> L'ancienne variante bleue "AJALAK Annaba Edition" (v1) a été retirée.

## Structure du repo

```
el_bouni_pieces_auto/
├── lib/
│   ├── config/app_config.dart      # couleurs, nom de l'app
│   ├── screens/                    # Assurance, Pièces, Carte
│   ├── services/                   # OCR, Gemini/Firebase AI
│   └── main.dart
├── android/
├── pubspec.yaml
└── .github/workflows/build.yml     # build APK automatique
```

## Mise en place (première fois)

Si le dossier `android/` n'est pas complet, scaffold-le avec Flutter :

```bash
flutter create . --org com.elbouni.ajalaks --project-name el_bouni_pieces_auto --platforms android
# remets ensuite le lib/ et android/app/src/main/AndroidManifest.xml fournis ici
```

Vérifie que `android/app/build.gradle.kts` a bien :
`applicationId = "com.elbouni.ajalaks.el_bouni_pieces_auto"`
(org + nom du projet — c'est aussi ce que contient `google-services.json`, ne pas changer l'un sans l'autre)

## Clé API Gemini — sécurité

Le code lit la clé dans cet ordre :
1. `--dart-define=GEMINI_API_KEY=...` (utilisé par le workflow GitHub Actions)
2. à défaut, la constante dans `lib/config/app_config.dart`

**Pour GitHub Actions** : ajoute un secret de repo nommé `GEMINI_API_KEY`
(Settings → Secrets and variables → Actions → New repository secret) avec
ta clé. Le workflow fourni l'utilise déjà.

**Si le repo est public**, ne laisse jamais la clé en dur dans
`app_config.dart` — retire la ligne `_fallbackGeminiKey` ou remplace-la par
une chaîne vide, et régénère une clé sur Google AI Studio si l'ancienne a pu
fuiter.

## Build local rapide

```bash
flutter pub get
flutter build apk --debug --dart-define=GEMINI_API_KEY=TA_CLE
```

## Build automatique (GitHub Actions)

Chaque push sur `main` déclenche `.github/workflows/build.yml`, qui build
l'APK et le publie comme artefact téléchargeable : `EL-BOUNI-PIECES-AUTO`.

## Fonctionnement des 3 onglets

1. **Assurance** — Photo carte jaune → OCR local (ML Kit, sans internet)
   extrait les dates → la plus récente = date d'expiration → calcul auto
   des jours restants (vert / orange / rouge). Gemini vient en complément
   pour afficher compagnie, nom, marque, police.
2. **Pièces détachées** — Photo de la pièce → Gemini identifie nom,
   référence, compatibilité, prix, et propose 3 magasins avec boutons
   Appeler / WhatsApp / Itinéraire.
3. **Carte** — Repères fixes des magasins d'El Bouni + bouton Google Maps.

## Ce qui a été volontairement exclu

- Pas de `flutter_map` (source d'instabilité de build) — remplacé par un
  lien direct vers Google Maps.
- Pas de dépendances lourdes superflues.
- Pas de variante bleue "Annaba Edition" (v1) — retirée à la demande.
