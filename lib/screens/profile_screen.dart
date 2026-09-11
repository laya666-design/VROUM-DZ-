import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
import '../services/google_auth_helper.dart';
import '../services/vehicule_service.dart';
import '../theme/app_theme.dart';
import '../widgets/screen_background.dart';
import 'admin/admin_login_screen.dart';
import 'role_router.dart';
import 'sos/tel_picker_dialog.dart';
import 'sos/wilaya_picker_dialog.dart';

/// Onglet Profil amélioré :
/// - Carte compte claire (badge + nombre de véhicules)
/// - Réglages (langue, type véhicule, rappels)
/// - Carte Premium vendeuse + bottom sheet détaillé
/// - Support (WhatsApp + Email + À propos)
class ProfileScreen extends StatefulWidget {
  final AppConfig config;
  final ValueNotifier<bool> isAr;
  final VoidCallback? onVehicleProfileChanged;

  const ProfileScreen({
    super.key,
    required this.config,
    required this.isAr,
    this.onVehicleProfileChanged,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // ─── Support ─────────────────────────────────────────────────────────────

  Future<void> _contactEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'vroumdz.support@gmail.com',
      query:
          'subject=${Uri.encodeComponent("Support - ${widget.config.appName}")}',
    );
    await launchUrl(uri);
  }

  Future<void> _contactWhatsApp() async {
    // Numéro support VROUM DZ (à adapter si besoin)
    const phone = '213556653220'; // format international sans +
    final uri = Uri.parse('https://wa.me/$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WhatsApp non disponible')),
      );
    }
  }

  void _showAboutDialog(String Function(String, String) t) {
    final green = widget.config.primaryColor;
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.85,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 12, 0),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: green.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.directions_car_filled_rounded,
                            size: 26, color: green),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.config.appName,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w800),
                            ),
                            Text(
                              t('Roulez tranquille. On s\'occupe du reste.',
                                  'سوق مرتاح. حنا نتكفلو بالباقي.'),
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 20),
                // Scrollable body
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t(
                            'VROUM DZ est né d\'un constat simple : on a tous déjà stressé au barrage pour une assurance ou un contrôle technique oublié.\n\nOn a créé la première app algérienne qui vous évite les amendes.',
                            'VROUM DZ جاء من ملاحظة بسيطة: كاملنا توترنا مرة في الحاجز على تأمين أو مراقبة تقنية منسيّة.\n\nدرنا أول تطبيق جزائري يبعدك على الغرامات.',
                          ),
                          style: TextStyle(
                              fontSize: 13.5,
                              height: 1.45,
                              color: Colors.grey.shade800),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          t('Que fait VROUM DZ pour vous ?',
                              'ماذا يفعل VROUM DZ من أجلك؟'),
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 12),
                        _aboutFeature(
                          emoji: '📸',
                          title: t('SCAN INTELLIGENT — Zéro saisie',
                              'مسح ذكي — بدون إدخال يدوي'),
                          body: t(
                            'Prenez en photo votre carte grise, assurance et contrôle technique. L\'app extrait les dates automatiquement. 3 secondes, c\'est fait.',
                            'صوّر البطاقة الرمادية، التأمين والمراقبة التقنية. التطبيق يستخرج التواريخ تلقائياً. 3 ثواني وبرك.',
                          ),
                        ),
                        _aboutFeature(
                          emoji: '🔔',
                          title: t('RAPPEL ANTI-AMENDE', 'تذكير ضد الغرامات'),
                          body: t(
                            'On vous alerte 7 jours, 3 jours et 1 jour avant la fin de validité. Plus jamais d\'amende pour papier expiré.',
                            'ننبّهوك قبل 7 أيام، 3 أيام ويوم واحد من انتهاء الصلاحية. عمرك ما تعاود تدفع غرامة على وثيقة منتهية.',
                          ),
                        ),
                        _aboutFeature(
                          emoji: '🔧',
                          title: t('PIÈCES & SOS', 'قطع الغيار والطوارئ'),
                          body: t(
                            'Pièce cassée ? Photographiez-la, VROUM vous dit ce que c\'est.\nEn panne ? Le bouton SOS trouve la dépanneuse ou le magasin de pièces le plus proche de vous.',
                            'قطعة تكسرت؟ صوّرها، VROUM يقولك وش هي.\nطحت في عطب؟ زر SOS يلقى أقرب ونش أو محل قطع غيار ليك.',
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t(
                            'Pour voiture et moto. Conçu par des conducteurs algériens, pour les conducteurs algériens.',
                            'للسيارة والدراجة النارية. مصمم من سائقين جزائريين، للسائقين الجزائريين.',
                          ),
                          style: TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              fontStyle: FontStyle.italic,
                              color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          t('Notre promesse', 'وعدنا'),
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          t(
                            'Vos données restent privées et sécurisées sur votre téléphone. VROUM DZ est gratuit pour 1 véhicule. Passez en Premium pour les véhicules illimités et les rappels par SMS.',
                            'بياناتك تبقى خاصة وآمنة على هاتفك. VROUM DZ مجاني لمركبة واحدة. انتقل إلى Premium للمركبات غير المحدودة والتذكيرات عبر SMS.',
                          ),
                          style: TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              color: Colors.grey.shade800),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          t(
                            'Une question ? Une idée ? On répond vite.',
                            'عندك سؤال؟ فكرة؟ نجاوبوك بسرعة.',
                          ),
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: Column(
                            children: [
                              Text(
                                'VROUM DZ v1.0',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.grey.shade600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                t('Fait avec ❤️ en Algérie',
                                    'صُنع بـ ❤️ في الجزائر'),
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade600),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'vroumdz.support@gmail.com',
                                style: TextStyle(
                                    fontSize: 12, color: green),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Close button
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: TextButton.styleFrom(
                        backgroundColor: green.withOpacity(0.1),
                        foregroundColor: green,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        t('Fermer', 'إغلاق'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _aboutFeature({
    required String emoji,
    required String title,
    required String body,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(body,
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: Colors.grey.shade700)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Labels véhicule ─────────────────────────────────────────────────────

  String _vehicleProfileLabel(String Function(String, String) t) {
    switch (SettingsService.vehicleProfile) {
      case 'voiture':
        return t('Voiture', 'سيارة');
      case 'moto':
        return t('Moto / Scooter', 'دراجة نارية / سكوتر');
      default:
        return t('Les deux', 'كلاهما');
    }
  }

  // ─── Bottom sheet Type de véhicule ───────────────────────────────────────

  Future<void> _showVehicleProfilePicker(
      BuildContext context, String Function(String, String) t) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  t('Type de véhicule', 'نوع المركبة'),
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  t(
                    'Cela détermine les onglets affichés dans l\'application',
                    'يحدد هذا التبويبات المعروضة في التطبيق',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                _vehicleOption(
                  ctx: ctx,
                  value: 'voiture',
                  icon: Icons.directions_car,
                  title: t('Voiture', 'سيارة'),
                  subtitle: t(
                    'Assurance, contrôle technique, carte grise…',
                    'تأمين، مراقبة تقنية، بطاقة رمادية…',
                  ),
                  selected: SettingsService.vehicleProfile == 'voiture',
                ),
                _vehicleOption(
                  ctx: ctx,
                  value: 'moto',
                  icon: Icons.two_wheeler,
                  title: t('Moto / Scooter', 'دراجة نارية / سكوتر'),
                  subtitle: t(
                    'Documents et pièces adaptés aux 2-roues',
                    'وثائق وقطع مخصصة للدراجات',
                  ),
                  selected: SettingsService.vehicleProfile == 'moto',
                ),
                _vehicleOption(
                  ctx: ctx,
                  value: 'both',
                  icon: Icons.sync_alt,
                  title: t('Les deux', 'كلاهما'),
                  subtitle: t(
                    'Accès complet à toutes les fonctionnalités',
                    'وصول كامل لجميع الميزات',
                  ),
                  selected: SettingsService.vehicleProfile == 'both' ||
                      SettingsService.vehicleProfile == null,
                ),
              ],
            ),
          ),
        );
      },
    );

    if (chosen == null) return;
    await SettingsService.setVehicleProfile(chosen);
    setState(() {});
    widget.onVehicleProfileChanged?.call();
  }

  void _openSettingsSheet(
    BuildContext context,
    String Function(String, String) t,
    bool isAr,
  ) {
    final isPremium = SettingsService.isPremium;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.85,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFF0F172A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                      child: Row(
                        children: [
                          Text(
                            t('Paramètres', 'الإعدادات'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                        children: [
                          _darkSettingsCard(
                            children: [
                              _darkSettingTile(
                                icon: Icons.dark_mode_outlined,
                                title: t('Affichage sombre', 'الوضع الداكن'),
                                subtitle: SettingsService.isDarkMode
                                    ? t('Activé', 'مفعّل')
                                    : t('Désactivé', 'معطّل'),
                                trailing: Switch(
                                  value: SettingsService.isDarkMode,
                                  activeColor: widget.config.primaryColor,
                                  onChanged: (val) async {
                                    await SettingsService.setDarkMode(val);
                                    setSheet(() {});
                                    if (mounted) setState(() {});
                                  },
                                ),
                              ),
                              _darkDivider(),
                              _darkSettingTile(
                                icon: Icons.language,
                                title: t('Langue', 'اللغة'),
                                subtitle: isAr ? 'العربية' : 'Français',
                                trailing: _darkLangToggle(
                                  isAr: isAr,
                                  onChanged: (v) {
                                    widget.isAr.value = v;
                                    setSheet(() {});
                                    if (mounted) setState(() {});
                                  },
                                ),
                              ),
                              _darkDivider(),
                              _darkSettingTile(
                                icon: Icons.directions_car_filled_outlined,
                                title: t('Type de véhicule', 'نوع المركبة'),
                                subtitle: _vehicleProfileLabel(t),
                                onTap: () async {
                                  Navigator.pop(ctx);
                                  await _showVehicleProfilePicker(context, t);
                                },
                              ),
                              _darkDivider(),
                              _darkSettingTile(
                                icon: Icons.location_city_outlined,
                                title: t('Wilaya', 'الولاية'),
                                subtitle:
                                    SettingsService.wilaya?.isNotEmpty == true
                                        ? SettingsService.wilaya!
                                        : t('Non renseignée', 'غير محددة'),
                                onTap: () async {
                                  final w = await showWilayaPickerDialog(
                                    context,
                                    accentColor: widget.config.primaryColor,
                                  );
                                  if (w != null && w.isNotEmpty) {
                                    await SettingsService.setWilaya(w);
                                    setSheet(() {});
                                    if (mounted) setState(() {});
                                  }
                                },
                              ),
                              _darkDivider(),
                              _darkSettingTile(
                                icon: Icons.phone_outlined,
                                title: t('Téléphone', 'الهاتف'),
                                subtitle: SettingsService.userTel
                                            ?.isNotEmpty ==
                                        true
                                    ? SettingsService.userTel!
                                    : t('Pour le SOS', 'لنداء الاستغاثة'),
                                onTap: () async {
                                  final tel = await showTelPickerDialog(
                                    context,
                                    accentColor: widget.config.primaryColor,
                                    valeurInitiale: SettingsService.userTel,
                                  );
                                  if (tel != null && tel.isNotEmpty) {
                                    await SettingsService.setUserTel(tel);
                                    setSheet(() {});
                                    if (mounted) setState(() {});
                                  }
                                },
                              ),
                              if (isPremium) ...[
                                _darkDivider(),
                                _darkSettingTile(
                                  icon: Icons.notifications_active_outlined,
                                  title: t('Rappels SMS / Appel',
                                      'تذكيرات SMS / مكالمة'),
                                  subtitle: SettingsService.smsRemindersEnabled
                                      ? t('Activés', 'مفعّلة')
                                      : t('Désactivés', 'معطّلة'),
                                  trailing: Switch(
                                    value: SettingsService.smsRemindersEnabled,
                                    activeColor: widget.config.primaryColor,
                                    onChanged: (val) async {
                                      await SettingsService
                                          .setSmsRemindersEnabled(val);
                                      setSheet(() {});
                                      if (mounted) setState(() {});
                                    },
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _vehicleOption({
    required BuildContext ctx,
    required String value,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool selected,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.pop(ctx, value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryLight : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: selected
                    ? widget.config.primaryColor
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: selected ? Colors.white : Colors.grey.shade700,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle,
                  color: widget.config.primaryColor, size: 22),
          ],
        ),
      ),
    );
  }

  // ─── Bottom sheet Premium ────────────────────────────────────────────────

  void _showPremiumSheet(
      BuildContext context, String Function(String, String) t) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'VROUM Premium',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  t(
                    'Tout ce dont vous avez besoin pour gérer vos véhicules sans limite.',
                    'كل ما تحتاجه لإدارة مركباتك بلا حدود.',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 20),
                _benefitRow(
                  t('Véhicules illimités', 'مركبات غير محدودة'),
                  t(
                    'Ajoutez autant de voitures ou motos que vous voulez',
                    'أضف أكبر عدد من السيارات أو الدراجات',
                  ),
                ),
                _benefitRow(
                  t('Rappels SMS & Appel', 'تذكيرات SMS ومكالمات'),
                  t(
                    'Ne ratez plus jamais une échéance d\'assurance ou de contrôle',
                    'لن تفوت أبداً موعد تأمين أو مراقبة',
                  ),
                ),
                _benefitRow(
                  t('Support prioritaire', 'دعم ذو أولوية'),
                  t(
                    'Réponse en moins de 2h via WhatsApp',
                    'رد في أقل من ساعتين عبر واتساب',
                  ),
                ),
                _benefitRow(
                  t('Accès anticipé', 'وصول مبكر'),
                  t(
                    'Nouvelles fonctionnalités en avant-première',
                    'ميزات جديدة قبل الجميع',
                  ),
                ),
                const SizedBox(height: 16),
                // Prix
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFECFDF5), Color(0xFFD1FAE5)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: Column(
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '490 DA',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: widget.config.primaryDark,
                              ),
                            ),
                            TextSpan(
                              text: ' / mois',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: widget.config.primaryDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t(
                          'ou 4 900 DA / an (économisez 2 mois)',
                          'أو 4900 دج / سنة (وفّر شهرين)',
                        ),
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      await SettingsService.setPremium(true);
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(t(
                            '🎉 Bienvenue en Premium !',
                            '🎉 مرحباً بك في Premium !',
                          )),
                          backgroundColor: widget.config.primaryColor,
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.config.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      t('Passer en Premium', 'الترقية إلى Premium'),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    t('Plus tard', 'لاحقاً'),
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _benefitRow(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check,
                size: 14, color: widget.config.primaryColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey.shade600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10, top: 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 11.5,
          color: Colors.grey.shade500,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _settingTile({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: iconColor, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12.5, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      ),
    );
  }

  // ─── Avatar + connexion ─────────────────────────────────────────────────

  ImageProvider? _avatarImage(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return NetworkImage(path);
    }
    final file = File(path);
    if (file.existsSync()) return FileImage(file);
    return null;
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 512,
    );
    if (picked == null) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dest = File('${dir.path}/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await File(picked.path).copy(dest.path);
      await SettingsService.setAvatarPath(dest.path);
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible d\'enregistrer la photo : $e')),
      );
    }
  }

  Future<void> _showLoginSheet(
      BuildContext context, String Function(String, String) t) async {
    final nameCtrl = TextEditingController(text: SettingsService.userName ?? '');
    var loading = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                child: SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        t('Se connecter', 'تسجيل الدخول'),
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        t(
                          'Choisis un nom affiché et optionnellement connecte-toi avec Google.',
                          'اختر اسمًا للعرض ويمكنك الاتصال بحساب Google.',
                        ),
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: nameCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: t('Nom affiché', 'الاسم المعروض'),
                          prefixIcon: const Icon(Icons.person_outline),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: loading
                            ? null
                            : () async {
                                final name = nameCtrl.text.trim();
                                if (name.isEmpty) return;
                                await SettingsService.setUserName(name);
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (mounted) setState(() {});
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.config.primaryColor,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(t('Enregistrer le nom', 'حفظ الاسم')),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: loading
                            ? null
                            : () async {
                                setModal(() => loading = true);
                                try {
                                  final cred = await GoogleAuthHelper.signIn();
                                  final user = cred.user;
                                  final name = user?.displayName?.trim();
                                  final photo = user?.photoURL;
                                  if (name != null && name.isNotEmpty) {
                                    await SettingsService.setUserName(name);
                                    nameCtrl.text = name;
                                  }
                                  if (photo != null && photo.isNotEmpty) {
                                    await SettingsService.setAvatarPath(photo);
                                  }
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  if (mounted) setState(() {});
                                } catch (e) {
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(content: Text('$e')),
                                    );
                                  }
                                } finally {
                                  if (ctx.mounted) {
                                    setModal(() => loading = false);
                                  }
                                }
                              },
                        icon: loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.g_mobiledata, size: 28),
                        label: Text(t(
                          'Continuer avec Google',
                          'المتابعة مع Google',
                        )),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      if (FirebaseAuth.instance.currentUser != null ||
                          (SettingsService.userName?.isNotEmpty ?? false)) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: loading
                              ? null
                              : () async {
                                  try {
                                    await FirebaseAuth.instance.signOut();
                                  } catch (_) {}
                                  await SettingsService.setUserName('');
                                  await SettingsService.setAvatarPath(null);
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  if (mounted) setState(() {});
                                },
                          child: Text(
                            t('Se déconnecter', 'تسجيل الخروج'),
                            style: TextStyle(color: Colors.red.shade600),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.isAr,
      builder: (context, isAr, _) {
        String t(String fr, String ar) => isAr ? ar : fr;
        final isPremium = SettingsService.isPremium;
        final vehicleCount = VehiculeService.getAll().length;

        return ScreenBackground(
          category: BackgroundCategory.generique,
          accentColor: widget.config.primaryColor,
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
              children: [
                // ── HEADER SOMBRE (A+D) ──────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF0F172A),
                        Color(0xFF1E293B),
                        Color(0xFF334155),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.22),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          GestureDetector(
                            onTap: _pickAvatar,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  width: 58,
                                  height: 58,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isPremium
                                          ? const Color(0xFFFBBF24)
                                          : widget.config.primaryColor
                                              .withOpacity(0.7),
                                      width: 2.5,
                                    ),
                                  ),
                                  child: CircleAvatar(
                                    backgroundColor:
                                        Colors.white.withOpacity(0.12),
                                    backgroundImage: _avatarImage(
                                        SettingsService.avatarPath),
                                    child: _avatarImage(
                                                SettingsService.avatarPath) ==
                                            null
                                        ? Icon(
                                            isPremium
                                                ? Icons.workspace_premium
                                                : Icons.person,
                                            color: Colors.white,
                                            size: 28,
                                          )
                                        : null,
                                  ),
                                ),
                                Positioned(
                                  right: -2,
                                  bottom: -2,
                                  child: Container(
                                    width: 22,
                                    height: 22,
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.camera_alt,
                                      size: 12,
                                      color: widget.config.primaryColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (SettingsService.userName?.isNotEmpty ??
                                          false)
                                      ? SettingsService.userName!
                                      : t('Invité', 'زائر'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                GestureDetector(
                                  onTap: () => _showLoginSheet(context, t),
                                  child: Text(
                                    (SettingsService.userName?.isNotEmpty ??
                                            false)
                                        ? t('Modifier le profil',
                                            'تعديل الملف')
                                        : t('Se connecter', 'تسجيل الدخول'),
                                    style: TextStyle(
                                      color: widget.config.primaryColor
                                          .withOpacity(0.95),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isPremium)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFBBF24),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                t('Premium', 'Premium'),
                                style: const TextStyle(
                                  color: Color(0xFF78350F),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          // Roue dentée → paramètres (plus de carte PARAMÈTRES en bas).
                          const SizedBox(width: 6),
                          Material(
                            color: Colors.white.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _openSettingsSheet(context, t, isAr),
                              child: const Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(Icons.settings_rounded,
                                    color: Colors.white, size: 22),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // Stats dashboard (C)
                      Row(
                        children: [
                          Expanded(
                            child: _statPill(
                              value: '$vehicleCount',
                              label: vehicleCount <= 1
                                  ? t('Véhicule', 'مركبة')
                                  : t('Véhicules', 'مركبات'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _statPill(
                              value: _vehicleProfileLabel(t),
                              label: t('Profil', 'الملف'),
                              isText: true,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _statPill(
                              value: isPremium
                                  ? t('∞', '∞')
                                  : '1',
                              label: isPremium
                                  ? t('Illimité', 'غير محدود')
                                  : t('Limite', 'الحد'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // ── RACCOURCI PRO ────────────────────────────────────────
                Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => RoleRouter.changerDeProfil(
                      context,
                      config: widget.config,
                      isAr: widget.isAr,
                      afficherConducteur: false,
                    ),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: widget.config.primaryColor
                              .withOpacity(0.25),
                        ),
                        gradient: LinearGradient(
                          colors: [
                            widget.config.primaryColor.withOpacity(0.06),
                            Colors.white,
                          ],
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: widget.config.primaryColor
                                  .withOpacity(0.14),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              Icons.storefront_rounded,
                              color: widget.config.primaryColor,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t('Espace Pro', 'مساحة برو'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  t(
                                    'Magasin de pièces ou dépanneuse',
                                    'محل قطع غيار أو سطحّة',
                                  ),
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 14,
                            color: widget.config.primaryColor,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Paramètres accessibles via ⚙ en haut à droite du header.

                // ── PREMIUM BANNIÈRE FINE (A) ─────────────────────────────
                if (!isPremium) ...[
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _showPremiumSheet(context, t),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF0F172A),
                              Color(0xFF1E293B),
                              Color(0xFF422006),
                            ],
                          ),
                          border: Border.all(
                            color: const Color(0xFFFBBF24).withOpacity(0.35),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.workspace_premium,
                                color: Color(0xFFFBBF24), size: 26),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t('Passer en Premium',
                                        'الترقية إلى Premium'),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                  Text(
                                    t(
                                      'Véhicules illimités · Rappels SMS',
                                      'مركبات غير محدودة · تذكيرات SMS',
                                    ),
                                    style: TextStyle(
                                      color: Colors.grey.shade400,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios,
                                color: Color(0xFFFBBF24), size: 14),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // ── AIDE (D) ─────────────────────────────────────────────
                _sectionLabel(t('Aide', 'المساعدة')),
                _groupCard(
                  children: [
                    _groupTile(
                      icon: Icons.chat_rounded,
                      title: 'WhatsApp',
                      subtitle: t('Support rapide', 'دعم سريع'),
                      iconColor: const Color(0xFF25D366),
                      onTap: _contactWhatsApp,
                    ),
                    _groupDivider(),
                    _groupTile(
                      icon: Icons.mail_outline_rounded,
                      title: 'Email',
                      subtitle: 'vroumdz.support@gmail.com',
                      onTap: _contactEmail,
                    ),
                    _groupDivider(),
                    GestureDetector(
                      onLongPress: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              AdminLoginScreen(config: widget.config),
                        ),
                      ),
                      child: _groupTile(
                        icon: Icons.info_outline_rounded,
                        title: t('À propos', 'حول التطبيق'),
                        subtitle: widget.config.appName,
                        onTap: () => _showAboutDialog(t),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statPill({
    required String value,
    required String label,
    bool isText = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: isText ? 12 : 18,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withOpacity(0.65),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _darkSettingsCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0F172A),
            Color(0xFF1E293B),
            Color(0xFF334155),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _darkDivider() {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 56,
      color: Colors.white.withOpacity(0.08),
    );
  }

  Widget _darkLangToggle({
    required bool isAr,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _langChip(
            label: 'FR',
            selected: !isAr,
            onTap: () => onChanged(false),
          ),
          _langChip(
            label: 'AR',
            selected: isAr,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }

  Widget _langChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? widget.config.primaryColor
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _darkSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.white.withOpacity(0.55),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              trailing ??
                  (onTap != null
                      ? Icon(Icons.chevron_right,
                          color: Colors.white.withOpacity(0.45), size: 20)
                      : const SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _groupDivider() {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 56,
      color: Colors.grey.shade100,
    );
  }

  Widget _groupTile({
    required IconData icon,
    required String title,
    required String subtitle,
    Color? iconColor,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final color = iconColor ?? widget.config.primaryColor;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              trailing ??
                  (onTap != null
                      ? const Icon(Icons.chevron_right,
                          color: Colors.grey, size: 20)
                      : const SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _premiumTag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0x26FBBF24),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFFBBF24),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _supportButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
