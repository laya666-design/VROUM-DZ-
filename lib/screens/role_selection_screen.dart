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
                    const SizedBox(height: 28),
                    Text(
                      t('Qui es-tu ?', 'من أنت؟'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t(
                        'Choisis ton profil pour continuer.\nTu pourras créer un autre compte plus tard.',
                        'اختر ملفك الشخصي للمتابعة.\nيمكنك إنشاء حساب آخر لاحقاً.',
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 32),
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
                                'Gérer mes véhicules, pièces, rappels et envoyer une alerte SOS',
                                'إدارة مركباتي، القطع، التذكيرات وإرسال تنبيه استغاثة',
                              ),
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
                              'Recevoir les demandes, gérer les commandes et mon profil magasin',
                              'استقبال الطلبات وإدارة الطلبات وملفي كمحل',
                            ),
                            accent: config.enchereColor,
                            onTap: () => _selectRole(context, UserRole.magasin),
                          ),
                          const SizedBox(height: 14),
                          _RoleCard(
                            iconImage: 'assets/images/icon_depanneuse.png',
                            iconBg: const Color(0xFFFEE2E2),
                            title: t('Dépanneuse', 'سطحّة'),
                            subtitle: t(
                              'Recevoir les alertes SOS et gérer mes interventions',
                              'استقبال تنبيهات الاستغاثة وإدارة تدخّلاتي',
                            ),
                            accent: config.sosColor,
                            onTap: () => _selectRole(context, UserRole.depanneuse),
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
  final Color accent;
  final VoidCallback onTap;

  const _RoleCard({
    this.icon,
    this.iconImage,
    required this.iconBg,
    this.iconColor,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  }) : assert(icon != null || iconImage != null);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                padding: iconImage != null ? const EdgeInsets.all(9) : null,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: iconImage != null
                    ? Image.asset(iconImage!, fit: BoxFit.contain)
                    : Icon(icon, color: iconColor, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: accent, size: 28),
            ],
          ),
        ),
      ),
    );
  }
}
