import 'package:flutter/material.dart';

/// VROUM DZ — Annaba Auto Parts Marketplace (ex "El Bouni Pièces Auto", ex
/// "VROUM23"). Rebrand nom/couleurs uniquement — package/applicationId
/// Android inchangé pour ne pas casser la config Firebase/keystore existante.
class AppConfig {
  final String appName;
  final Color primaryColor; // vert VROUM DZ
  final Color primaryDark;
  final Color enchereColor; // orange — enchères / offres magasins
  final Color sosColor; // rouge — alertes/SOS
  final String baridimobPhone;

  const AppConfig._({
    required this.appName,
    required this.primaryColor,
    required this.primaryDark,
    required this.enchereColor,
    required this.sosColor,
    required this.baridimobPhone,
  });

  static const _instance = AppConfig._(
    appName: 'VROUM DZ',
    primaryColor: Color(0xFF22C55E), // vert
    primaryDark: Color(0xFF16A34A),
    enchereColor: Color(0xFFF97316), // orange
    sosColor: Color(0xFFEF4444), // rouge
    // Numéro BaridiMob où les magasins envoient leur paiement manuel
    // d'abonnement (repli quand ils n'ont pas de carte CIB/Edahabia).
    baridimobPhone: '0556653220',
  );

  static AppConfig current() => _instance;
}
