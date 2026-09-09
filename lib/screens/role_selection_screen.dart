import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../models/user_role.dart';
import '../theme/app_theme.dart';
import 'admin/admin_login_screen.dart';
import 'role_router.dart';

/// Écran obligatoire au premier lancement.
/// L'utilisateur choisit son rôle une seule fois (1 compte = 1 rôle).
class RoleSelectionScreen extends StatelessWidget {
  final AppConfig config;
  final ValueNotifier<bool> isAr;
  // Masque la carte "Conducteur" quand cet écran est ouvert depuis
  // l'Espace Pro du Profil conducteur (on est déjà conducteur, l'option
  // n'a pas de sens là). Reste à true par défaut pour les autres accès
  // (magasin_shell, depanneuse_shell, store_login, depanneuse_auth) où
  // revenir à Conducteur doit rester possible.
  final bool afficherConducteur;

  const RoleSelectionScreen({
    super.key,
    required this.config,
    required this.isAr,
    this.afficherConducteur = true,
  });

  Future<void> _selectRole(BuildContext context, UserRole role) async {
    // Toute la logique "quel écran pour quel rôle" vit dans RoleRouter,
    // partagée avec SplashScreen — jamais dupliquée ici.
    await RoleRouter.selectRole(context, role: role, config: config, isAr: isAr);
  }

  void _openAdmin(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AdminLoginScreen(config: config)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isAr,
      builder: (context, ar, _) {
        final t = (String fr, String arText) => ar ? arText : fr;

        return Directionality(
          textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            backgroundColor: AppColors.background,
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Flèche retour : cet écran est toujours atteint via
                    // RoleRouter.changerDeProfil, qui vide entièrement la
                    // pile (pushAndRemoveUntil) pour qu'un retour arrière
                    // ne révèle jamais l'ancien rôle. Résultat :
                    // Navigator.canPop() est toujours false ici et il
                    // n'y avait aucun moyen d'annuler le changement de
                    // profil. On remplace donc explicitement l'écran par
                    // celui du rôle actuellement enregistré (annule
                    // l'action, sans rien changer côté SettingsService).
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Material(
                        color: Colors.transparent,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () {
                            Navigator.of(context).pushReplacement(
                              PageRouteBuilder(
                                pageBuilder: (_, __, ___) => RoleRouter
                                    .resolve(config: config, isAr: isAr),
                                transitionDuration:
                                    const Duration(milliseconds: 300),
                                transitionsBuilder: (_, animation, __, child) {
                                  return FadeTransition(
                                      opacity: animation, child: child);
                                },
                              ),
                            );
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.arrow_back, size: 22),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Logo VROUM DZ. Appui long sur la roue (centre du
                        // logo) = accès admin caché, avant même d'avoir
                        // choisi un profil.
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: AspectRatio(
                              aspectRatio: 1568 / 565,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.asset(
                                    'assets/images/logo_header.png',
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stack) =>
                                        Container(
                                      color: Colors.black,
                                      alignment: Alignment.center,
                                      child: Text(
                                        config.appName,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Zone invisible pile sur la roue du logo.
                                  Align(
                                    alignment: const Alignment(-0.06, 0.0),
                                    child: FractionallySizedBox(
                                      widthFactor: 0.24,
                                      heightFactor: 0.85,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onLongPress: () => _openAdmin(context),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: () => isAr.value = !isAr.value,
                          style: TextButton.styleFrom(
                            foregroundColor: config.primaryColor,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          child: Text(
                            ar ? 'FR' : 'AR',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      t('Qui es-tu ?', 'من أنت؟'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t(
                        'Choisis ton espace pour continuer.\nTu pourras changer de profil à tout moment.',
                        'اختر مساحتك للمتابعة.\nيمكنك تغيير الملف في أي وقت.',
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Expanded(
                      child: ListView(
                        children: [
                          if (afficherConducteur) ...[
                            _RoleCard(
                              icon: Icons.directions_car_rounded,
                              iconBg: const Color(0xFFDCFCE7),
                              iconColor: config.primaryDark,
                              title: t('Conducteur', 'سائق'),
                              subtitle: t(
                                'Véhicules, pièces, rappels assurance/CT et alerte SOS',
                                'المركبات، القطع، تذكيرات التأمين/الفحص وتنبيه الاستغاثة',
                              ),
                              badge: t('Le plus choisi', 'الأكثر اختياراً'),
                              accent: config.primaryColor,
                              onTap: () =>
                                  _selectRole(context, UserRole.conducteur),
                            ),
                            const SizedBox(height: 14),
                          ],
                          _RoleCard(
                            icon: Icons.storefront_rounded,
                            iconBg: const Color(0xFFFFEDD5),
                            iconColor: config.enchereColor,
                            title: t('Magasin de pièces', 'محل قطع غيار'),
                            subtitle: t(
                              'Reçois les demandes autour de toi et réponds avec ton prix',
                              'استقبل الطلبات من حولك وأجب بسعرك',
                            ),
                            badge: t('Espace Pro', 'مساحة برو'),
                            accent: config.enchereColor,
                            onTap: () => _selectRole(context, UserRole.magasin),
                          ),
                          const SizedBox(height: 14),
                          _RoleCard(
                            iconImage: 'assets/images/icon_depanneuse.png',
                            iconBg: const Color(0xFFFEE2E2),
                            title: t('Dépanneuse', 'سطحّة'),
                            subtitle: t(
                              'Alertes SOS en temps réel et suivi des interventions',
                              'تنبيهات الاستغاثة فورياً ومتابعة التدخلات',
                            ),
                            badge: t('Urgence', 'طوارئ'),
                            accent: config.sosColor,
                            onTap: () =>
                                _selectRole(context, UserRole.depanneuse),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData? icon;
  final String? iconImage;
  final Color iconBg;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final String? badge;
  final Color accent;
  final VoidCallback onTap;

  const _RoleCard({
    this.icon,
    this.iconImage,
    required this.iconBg,
    this.iconColor,
    required this.title,
    required this.subtitle,
    this.badge,
    required this.accent,
    required this.onTap,
  }) : assert(icon != null || iconImage != null);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border:
                Border.all(color: accent.withValues(alpha: 0.28), width: 1.5),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: 0.06),
                Colors.white,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.12),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                padding: iconImage != null ? const EdgeInsets.all(9) : null,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: iconImage != null
                    ? Image.asset(iconImage!, fit: BoxFit.contain)
                    : Icon(icon, color: iconColor, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w900,
                              color: AppColors.textPrimary,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              badge!,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: accent,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(Icons.arrow_forward_rounded,
                    color: Colors.white, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
