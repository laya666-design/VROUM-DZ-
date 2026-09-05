import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../models/user_role.dart';
import '../services/vehicule_service.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';
import 'onboarding_profile_screen.dart';
import 'marketplace/magasin_shell_screen.dart';
import 'sos/depanneuse_shell_screen.dart';

/// Écran de choix de rôle — Architecture VROUM Native.
///
/// N'est plus obligatoire au premier lancement.
/// Accessible depuis Profil → « Espace Pro ».
/// - Conducteur → Accueil (mode invité / normal)
/// - Magasin / Dépanneuse → shell pro
class RoleSelectionScreen extends StatelessWidget {
  final AppConfig config;
  final ValueNotifier<bool> isAr;

  const RoleSelectionScreen({
    super.key,
    required this.config,
    required this.isAr,
  });

  Future<void> _selectRole(BuildContext context, UserRole role) async {
    await SettingsService.setUserRole(role);
    if (!context.mounted) return;

    final Widget next;
    switch (role) {
      case UserRole.conducteur:
        // Plus d'onboarding forcé
        next = HomeScreen(config: config, isAr: isAr);
        break;
      case UserRole.magasin:
        next = MagasinShellScreen(config: config, isAr: isAr.value);
        break;
      case UserRole.depanneuse:
        next = DepanneuseShellScreen(config: config, isAr: isAr.value);
        break;
    }

    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => next,
        transitionDuration: const Duration(milliseconds: 350),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
      (route) => false,
    );
  }
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
                      children: [
                        Text(
                          config.appName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.3,
                          ),
                        ),
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
                            onTap: () => _selectRole(context, UserRole.conducteur),
                          ),
                          const SizedBox(height: 14),
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
                            icon: Icons.local_shipping_rounded,
                            iconBg: const Color(0xFFFEE2E2),
                            iconColor: config.sosColor,
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
                    const SizedBox(height: 12),
                    Text(
                      t(
                        'Ce choix est définitif pour ce compte',
                        'هذا الاختيار نهائي لهذا الحساب',
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
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
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

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
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: iconColor, size: 28),
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
