import 'package:flutter/material.dart';

/// Catégorie d'image de fond selon le contenu de l'écran.
enum BackgroundCategory { voiture, moto, pieces, magasin, generique }

/// Habille un écran avec une photo de fond thématique (voiture derrière
/// l'onglet Véhicules, moto derrière l'onglet Motos, etc.). Un voile
/// dégradé est posé entre la photo et le contenu (plus marqué en haut,
/// là où le titre n'a pas de carte derrière lui) pour garder le texte
/// lisible quelle que soit la luminosité de la photo, tout en laissant
/// la photo reconnaissable.
///
/// Les photos ne sont PAS embarquées ici (droits d'auteur, fiabilité) :
/// elles doivent être ajoutées par toi dans `assets/images/` — voir
/// `assets/images/README.md` pour les 4 fichiers attendus et des sources
/// gratuites. Tant qu'un fichier n'existe pas, l'écran affiche un fond
/// dégradé + une icône en filigrane à la place, donc rien ne casse.
class ScreenBackground extends StatelessWidget {
  final BackgroundCategory category;
  final Widget child;
  final Color accentColor;

  const ScreenBackground({
    super.key,
    required this.category,
    required this.child,
    this.accentColor = const Color(0xFF22C55E),
  });

  String get _assetPath {
    switch (category) {
      case BackgroundCategory.voiture:
        return 'assets/images/bg_voiture.jpg';
      case BackgroundCategory.moto:
        return 'assets/images/bg_moto.jpg';
      case BackgroundCategory.pieces:
        return 'assets/images/bg_pieces.jpg';
      case BackgroundCategory.magasin:
        return 'assets/images/bg_magasin.jpg';
      case BackgroundCategory.generique:
        return 'assets/images/bg_generique.jpg';
    }
  }

  IconData get _fallbackIcon {
    switch (category) {
      case BackgroundCategory.voiture:
        return Icons.directions_car;
      case BackgroundCategory.moto:
        return Icons.two_wheeler;
      case BackgroundCategory.pieces:
        return Icons.build;
      case BackgroundCategory.magasin:
        return Icons.storefront;
      case BackgroundCategory.generique:
        return Icons.directions_car_filled;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Fond uni / léger dégradé — plus de photo voiture / moto / magasin
    // (demande produit : interface plus sobre, moins de bruit visuel).
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final top = isDark
        ? const Color(0xFF0B1220)
        : Color.lerp(Colors.white, accentColor, 0.06)!;
    final bottom = isDark ? const Color(0xFF0B1220) : Colors.white;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, bottom],
        ),
      ),
      child: child,
    );
  }
}
