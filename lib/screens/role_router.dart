import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../models/user_role.dart';
import '../services/vehicule_service.dart';
import 'home_screen.dart';
import 'onboarding_profile_screen.dart';
import 'marketplace/magasin_shell_screen.dart';
import 'sos/depanneuse_shell_screen.dart';
import 'role_selection_screen.dart';

/// Centralise "étant donné le rôle choisi, quel écran ouvrir ?" — utilisé
/// au démarrage (SplashScreen) ET juste après un choix explicite
/// (RoleSelectionScreen), pour ne jamais dupliquer cette logique à deux
/// endroits différents.
class RoleRouter {
  /// Résout l'écran à afficher pour le rôle actuellement stocké.
  /// Aucun rôle choisi = mode invité conducteur par défaut (pas d'écran
  /// de choix imposé au lancement) ; Magasin/Dépanneuse restent
  /// accessibles à tout moment via Profil > "Changer de profil" (voir
  /// changerDeProfil ci-dessous).
  static Widget resolve({
    required AppConfig config,
    required ValueNotifier<bool> isAr,
  }) {
    final role = SettingsService.userRole ?? UserRole.conducteur;

    switch (role) {
      case UserRole.conducteur:
        return SettingsService.hasChosenVehicleProfile
            ? HomeScreen(config: config, isAr: isAr)
            : OnboardingProfileScreen(
                config: config,
                isAr: isAr,
                onChosen: (value) => SettingsService.setVehicleProfile(value),
              );

      case UserRole.magasin:
        return MagasinShellScreen(config: config, isAr: isAr.value);

      case UserRole.depanneuse:
        return DepanneuseShellScreen(config: config, isAr: isAr.value);
    }
  }

  /// Enregistre le rôle choisi puis navigue vers l'écran correspondant.
  static Future<void> selectRole(
    BuildContext context, {
    required UserRole role,
    required AppConfig config,
    required ValueNotifier<bool> isAr,
  }) async {
    await SettingsService.setUserRole(role);
    if (!context.mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => resolve(config: config, isAr: isAr),
        transitionDuration: const Duration(milliseconds: 350),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  /// Ouvre l'écran de choix de rôle (Conducteur / Magasin / Dépanneuse),
  /// accessible depuis Profil > "Changer de profil" sur les 3 rôles.
  /// Ne touche pas au rôle actuel tant que l'utilisateur n'a pas
  /// effectivement choisi une carte dans RoleSelectionScreen (voir
  /// selectRole ci-dessus) : quitter l'app avant de choisir ne fait
  /// perdre aucun profil existant. Stack entièrement vidée
  /// (pushAndRemoveUntil) pour qu'un retour arrière depuis le nouvel
  /// espace ne révèle jamais l'ancien rôle.
  static Future<void> changerDeProfil(
    BuildContext context, {
    required AppConfig config,
    required ValueNotifier<bool> isAr,
  }) async {
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => RoleSelectionScreen(config: config, isAr: isAr),
      ),
      (route) => false,
    );
  }
}
