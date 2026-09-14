import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Déverrouillage par empreinte digitale / reconnaissance faciale.
///
/// Ne remplace PAS la connexion email/téléphone+mot de passe : sert
/// seulement, une fois qu'un admin s'est déjà connecté une première fois
/// avec ses identifiants et a activé l'option, à reconfirmer son identité
/// plus rapidement à la prochaine ouverture de l'écran Admin (la session
/// Firebase reste valide entre-temps, la biométrie n'est qu'une porte
/// supplémentaire avant d'afficher le tableau de bord).
class BiometricService {
  static const _prefsKeyEnabled = 'admin_biometric_enabled';

  static final LocalAuthentication _auth = LocalAuthentication();

  /// true si le matériel supporte la biométrie ET qu'au moins une
  /// empreinte/visage est déjà enregistré au niveau du système
  /// (sinon inutile de proposer l'option).
  static Future<bool> isAvailable() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final deviceSupported = await _auth.isDeviceSupported();
      if (!canCheck || !deviceSupported) return false;
      final available = await _auth.getAvailableBiometrics();
      return available.isNotEmpty;
    } catch (_) {
      // Certains émulateurs / appareils sans capteur lèvent une exception
      // plutôt que de renvoyer false proprement : on traite ça comme
      // "biométrie indisponible" sans planter l'écran de connexion.
      return false;
    }
  }

  /// Déclenche le prompt biométrique natif de l'appareil.
  /// Retourne true seulement si l'utilisateur s'est authentifié avec
  /// succès (un simple "annuler" ou un échec renvoie false, jamais
  /// d'exception qui remonterait jusqu'à l'écran de connexion).
  static Future<bool> authenticate({
    String reason = 'Confirme ton identité pour accéder à l\'espace Admin',
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKeyEnabled) ?? false;
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyEnabled, enabled);
  }
}
