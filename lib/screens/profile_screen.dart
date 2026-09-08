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
      path: 'contact@elbouni-pieces-auto.dz',
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
                // ── HERO HEADER ──────────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isPremium
                          ? const [
                              Color(0xFF0F172A),
                              Color(0xFF1E293B),
                              Color(0xFF334155),
                            ]
                          : [
                              widget.config.primaryColor,
                              widget.config.primaryColor.withOpacity(0.82),
                              const Color(0xFF0F766E),
                            ],
                    ),
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: [
                      BoxShadow(
                        color: (isPremium
                                ? Colors.black
                                : widget.config.primaryColor)
                            .withOpacity(0.28),
                        blurRadius: 22,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          // Avatar cliquable
                          GestureDetector(
                            onTap: _pickAvatar,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white.withOpacity(0.35),
                                        width: 2.5),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.2),
                                        blurRadius: 12,
                                      ),
                                    ],
                                  ),
                                  child: CircleAvatar(
                                    backgroundColor:
                                        Colors.white.withOpacity(0.2),
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
                                            size: 32,
                                          )
                                        : null,
                                  ),
                                ),
                                Positioned(
                                  right: -2,
                                  bottom: -2,
                                  child: Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.15),
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      Icons.camera_alt,
                                      size: 13,
                                      color: widget.config.primaryColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (SettingsService.userName?.isNotEmpty ?? false)
                                      ? SettingsService.userName!
                                      : widget.config.appName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 20,
                                    letterSpacing: -0.3,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 11, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isPremium
                                            ? const Color(0xFFFBBF24)
                                            : Colors.white.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        isPremium
                                            ? t('Compte Premium', 'حساب Premium')
                                            : t('Compte gratuit', 'حساب مجاني'),
                                        style: TextStyle(
                                          color: isPremium
                                              ? const Color(0xFF78350F)
                                              : Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: () =>
                                          _showLoginSheet(context, t),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.22),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          border: Border.all(
                                              color: Colors.white
                                                  .withOpacity(0.35)),
                                        ),
                                        child: Text(
                                          (SettingsService.userName
                                                      ?.isNotEmpty ??
                                                  false)
                                              ? t('Modifier', 'تعديل')
                                              : t('Se connecter',
                                                  'تسجيل الدخول'),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: Colors.white.withOpacity(0.18)),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    '$vehicleCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 22,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    vehicleCount <= 1
                                        ? t('véhicule', 'مركبة')
                                        : t('véhicules', 'مركبات'),
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.8),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: Colors.white.withOpacity(0.18)),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    isPremium
                                        ? Icons.all_inclusive
                                        : Icons.lock_outline,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    isPremium
                                        ? t('Illimité', 'غير محدود')
                                        : t('1 gratuit', '1 مجاني'),
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.85),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── ACTIONS RAPIDES ──────────────────────────────────────
                _sectionLabel(t('Accès rapide', 'وصول سريع')),
                Row(
                  children: [
                    Expanded(
                      child: _quickAction(
                        icon: Icons.storefront_rounded,
                        label: t('Espace Pro', 'مساحة برو'),
                        color: widget.config.primaryColor,
                        onTap: () => RoleRouter.changerDeProfil(
                          context,
                          config: widget.config,
                          isAr: widget.isAr,
                          afficherConducteur: false,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _quickAction(
                        icon: Icons.language,
                        label: isAr ? 'العربية' : 'Français',
                        color: const Color(0xFF2563EB),
                        onTap: () => widget.isAr.value = !isAr,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _quickAction(
                        icon: Icons.tune_rounded,
                        label: _vehicleProfileLabel(t),
                        color: const Color(0xFF7C3AED),
                        onTap: () => _showVehicleProfilePicker(context, t),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),

                // ── RÉGLAGES ─────────────────────────────────────────────
                _sectionLabel(t('Réglages', 'الإعدادات')),
                _settingTile(
                  icon: Icons.language,
                  iconBg: const Color(0xFFEFF6FF),
                  iconColor: const Color(0xFF2563EB),
                  title: t('Langue', 'اللغة'),
                  subtitle: isAr ? 'العربية' : 'Français',
                  trailing: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('FR')),
                      ButtonSegment(value: true, label: Text('AR')),
                    ],
                    selected: {isAr},
                    onSelectionChanged: (s) => widget.isAr.value = s.first,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _settingTile(
                  icon: Icons.directions_car_filled_outlined,
                  iconBg: AppColors.primaryLight,
                  iconColor: widget.config.primaryColor,
                  title: t('Type de véhicule', 'نوع المركبة'),
                  subtitle: _vehicleProfileLabel(t),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () => _showVehicleProfilePicker(context, t),
                ),
                if (isPremium) ...[
                  const SizedBox(height: 8),
                  _settingTile(
                    icon: Icons.notifications_active_outlined,
                    iconBg: const Color(0xFFFEF3C7),
                    iconColor: const Color(0xFFD97706),
                    title: t('Rappels SMS / Appel', 'تذكيرات SMS / مكالمة'),
                    subtitle: SettingsService.smsRemindersEnabled
                        ? t('Activés', 'مفعّلة')
                        : t('Désactivés', 'معطّلة'),
                    trailing: Switch(
                      value: SettingsService.smsRemindersEnabled,
                      activeColor: widget.config.primaryColor,
                      onChanged: (val) async {
                        await SettingsService.setSmsRemindersEnabled(val);
                        setState(() {});
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 22),

                // ── PREMIUM ──────────────────────────────────────────────
                if (!isPremium) ...[
                  _sectionLabel(t('Premium', 'بريميوم')),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF0F172A),
                          Color(0xFF1E293B),
                          Color(0xFF422006),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: () => _showPremiumSheet(context, t),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 46,
                                    height: 46,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFFFDE68A),
                                          Color(0xFFFBBF24),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: const Icon(Icons.workspace_premium,
                                        color: Color(0xFF78350F), size: 24),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          t('Passer en Premium',
                                              'الترقية إلى Premium'),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 16.5,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          t(
                                            'Débloque tout le potentiel',
                                            'افتح كامل الإمكانيات',
                                          ),
                                          style: TextStyle(
                                            color: Colors.grey.shade400,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.arrow_forward_ios,
                                      color: Color(0xFFFBBF24), size: 16),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  _premiumTag(t('Véhicules illimités',
                                      'مركبات غير محدودة')),
                                  _premiumTag(
                                      t('Rappels SMS', 'تذكيرات SMS')),
                                  _premiumTag(t(
                                      'Support prioritaire', 'دعم أولوية')),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                ],

                // ── SUPPORT ──────────────────────────────────────────────
                _sectionLabel(t('Support', 'الدعم')),
                Row(
                  children: [
                    Expanded(
                      child: _supportButton(
                        icon: Icons.chat_rounded,
                        label: 'WhatsApp',
                        color: const Color(0xFF25D366),
                        onTap: _contactWhatsApp,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _supportButton(
                        icon: Icons.mail_outline_rounded,
                        label: 'Email',
                        color: const Color(0xFF2563EB),
                        onTap: _contactEmail,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onLongPress: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          AdminLoginScreen(config: widget.config),
                    ),
                  ),
                  child: _settingTile(
                    icon: Icons.info_outline_rounded,
                    iconBg: const Color(0xFFEFF6FF),
                    iconColor: const Color(0xFF2563EB),
                    title: t('À propos', 'حول التطبيق'),
                    subtitle: t(
                      '${widget.config.appName} — véhicules & pièces',
                      '${widget.config.appName} — مركبات وقطع غيار',
                    ),
                    trailing:
                        const Icon(Icons.chevron_right, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
