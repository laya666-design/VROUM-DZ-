import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
import '../services/vehicule_service.dart';

/// Onglet Profil : remplace l'ancien onglet Carte (statique, peu utile).
/// Regroupe le statut du compte, les réglages (langue, rappels) et le
/// support — tout ce dont l'utilisateur a besoin en dehors des rubriques
/// véhicules/pièces.
class ProfileScreen extends StatefulWidget {
  final AppConfig config;
  final ValueNotifier<bool> isAr;

  const ProfileScreen({super.key, required this.config, required this.isAr});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Future<void> _contactSupport() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'contact@elbouni-pieces-auto.dz',
      query: 'subject=${Uri.encodeComponent("Support - El Bouni Pièces Auto")}',
    );
    await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.isAr,
      builder: (context, isAr, _) {
        String t(String fr, String ar) => isAr ? ar : fr;
        final isPremium = SettingsService.isPremium;

        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(t('Profil', 'الملف الشخصي'),
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),

              // Carte statut du compte
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: widget.config.primaryColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: widget.config.primaryColor,
                      child: const Icon(Icons.person, color: Colors.white),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.config.appName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 2),
                          Text(
                            isPremium
                                ? t('Compte Premium', 'حساب Premium')
                                : t('Compte gratuit', 'حساب مجاني'),
                            style: TextStyle(
                                color: isPremium
                                    ? const Color(0xFF166534)
                                    : Colors.black54,
                                fontWeight: FontWeight.w600,
                                fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    if (!isPremium)
                      Chip(
                        label: const Text('Premium',
                            style:
                                TextStyle(fontSize: 11, color: Colors.white)),
                        backgroundColor: widget.config.primaryColor,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              Text(t('Réglages', 'الإعدادات'),
                  style:
                      const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 8),

              // Langue
              Card(
                child: ListTile(
                  leading: const Icon(Icons.language),
                  title: Text(t('Langue', 'اللغة')),
                  subtitle: Text(isAr ? 'العربية' : 'Français'),
                  trailing: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('FR')),
                      ButtonSegment(value: true, label: Text('AR')),
                    ],
                    selected: {isAr},
                    onSelectionChanged: (s) =>
                        widget.isAr.value = s.first,
                  ),
                ),
              ),

              // Rappels SMS/Appel
              Card(
                child: SwitchListTile(
                  secondary: const Icon(Icons.notifications_active_outlined),
                  title: Text(t('Rappels par SMS / Appel', 'تذكيرات عبر SMS / مكالمة')),
                  subtitle: Text(
                    isPremium
                        ? t('Bientôt disponible', 'قريباً')
                        : t('Réservé aux comptes Premium',
                            'حصري لحسابات Premium'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  value: SettingsService.smsRemindersEnabled,
                  onChanged: isPremium
                      ? (val) async {
                          await SettingsService.setSmsRemindersEnabled(val);
                          setState(() {});
                        }
                      : null,
                ),
              ),

              if (!isPremium)
                Card(
                  child: ListTile(
                    leading: Icon(Icons.workspace_premium,
                        color: widget.config.primaryColor),
                    title: Text(t('Passer en Premium', 'الترقية إلى Premium')),
                    subtitle: Text(t(
                        'Véhicules illimités et rappels SMS/appel',
                        'مركبات غير محدودة وتذكيرات SMS/مكالمة')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content:
                                Text(t('Bientôt disponible', 'قريباً'))),
                      );
                    },
                  ),
                ),

              const SizedBox(height: 24),
              Text(t('Support', 'الدعم'),
                  style:
                      const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 8),

              Card(
                child: ListTile(
                  leading: const Icon(Icons.mail_outline),
                  title: Text(t('Contacter le support', 'التواصل مع الدعم')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _contactSupport,
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(t('À propos', 'حول التطبيق')),
                  subtitle: Text(t(
                      'El Bouni Pièces Auto — gestion véhicules & pièces détachées',
                      'El Bouni Pièces Auto — إدارة المركبات وقطع الغيار')),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
