import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import '../../services/marketplace_models.dart';
import '../../services/store_service.dart';
import '../../services/vehicule.dart';
import '../../services/vehicule_service.dart';
import '../../theme/app_theme.dart';
import '../sos/tel_picker_dialog.dart';
import '../sos/wilaya_picker_dialog.dart';
import '../sos/sos_alert_sent_screen.dart';
import '../../services/sos_service.dart';
import '../role_router.dart';
import '../vehicles_screen.dart';
import 'store_dashboard_screen.dart';
import 'store_login_screen.dart';
import 'subscription_screen.dart';

/// Portail Magasin avec navigation :
/// Demandes · Rappels (véhicule perso : assurance/CT) · Profil + SOS discret.
class MagasinShellScreen extends StatefulWidget {
  final AppConfig config;
  final bool isAr;

  const MagasinShellScreen({
    super.key,
    required this.config,
    this.isAr = false,
  });

  @override
  State<MagasinShellScreen> createState() => _MagasinShellScreenState();
}

class _MagasinShellScreenState extends State<MagasinShellScreen> {
  int _index = 0;
  bool _sosEnCours = false;

  @override
  void initState() {
    super.initState();
    // Si pas connecté (ou seulement session anonyme SOS/pièces) → login.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Attend que Firebase Auth ait fini de restaurer une éventuelle
      // session persistée (utile juste après un redémarrage de l'app,
      // ex: process tué en arrière-plan par l'OS puis relancé), sinon
      // isLoggedIn pourrait répondre "non" à tort pendant l'instant où
      // currentUser vaut encore null.
      await StoreService.waitForAuthReady();
      await StoreService.loadPhoneAsId();

      // Une session anonyme (demande de pièces / SOS) ne doit pas ouvrir
      // l'Espace Pro : on la ignore et on affiche la connexion magasin.
      final user = StoreService.currentUser;
      if (user != null && user.isAnonymous) {
        await StoreService.signOut();
      }

      if (!StoreService.isLoggedIn && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => StoreLoginScreen(config: widget.config),
          ),
        );
      }
    });
  }

  Future<void> _envoyerSos() async {
    if (_sosEnCours) return;
    final isAr = widget.isAr;
    final confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isAr ? 'نداء استغاثة' : 'Alerte SOS'),
        content: Text(
          isAr
              ? 'إرسال نداء استغاثة إلى سائقي سطحات المساعدة في ولايتك؟'
              : 'Envoyer une alerte de panne aux dépanneuses de ta wilaya ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isAr ? 'إلغاء' : 'Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: widget.config.sosColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isAr ? 'إرسال' : 'Envoyer'),
          ),
        ],
      ),
    );
    if (confirme != true || !mounted) return;

    String? wilaya = SettingsService.wilaya;
    if (wilaya == null) {
      wilaya = await showWilayaPickerDialog(
        context,
        accentColor: widget.config.sosColor,
      );
      if (wilaya == null || !mounted) return;
      await SettingsService.setWilaya(wilaya);
    }
    final wilayaOk = wilaya;

    String? tel = SettingsService.userTel;
    if (tel == null) {
      tel = await showTelPickerDialog(
        context,
        accentColor: widget.config.sosColor,
      );
      if (tel == null || !mounted) return;
      await SettingsService.setUserTel(tel);
    }
    final telOk = tel;

    setState(() => _sosEnCours = true);
    try {
      final alertId = await SosService.sendAlert(
        wilaya: wilayaOk,
        telephone: telOk,
      );
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SosAlertSentScreen(
            config: widget.config,
            alertId: alertId,
            wilaya: wilayaOk,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sosEnCours = false);
    }
  }

  Future<void> _logout() async {
    await StoreService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => StoreLoginScreen(config: widget.config),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!StoreService.isLoggedIn) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final screens = [
      // Demandes = dashboard magasin existant
      StoreDashboardScreen(config: widget.config),
      // Rappels = le véhicule perso du magasin (assurance/CT), même écran
      // que côté conducteur — utile pour la camionnette/voiture du magasin.
      VehiclesScreen(
        config: widget.config,
        isAr: widget.isAr,
        types: const [
          TypeVehicule.voiture,
          TypeVehicule.moto,
          TypeVehicule.scooter,
        ],
        titre: 'Mon véhicule',
        titreAr: 'مركبتي',
        sousTitre: 'Assurance et contrôle technique de ton véhicule.',
        sousTitreAr: 'التأمين والفحص التقني لمركبتك.',
        labelAjout: 'Ajouter mon véhicule',
        labelAjoutAr: 'إضافة مركبتي',
        labelVide: 'Aucun véhicule enregistré pour le moment',
        labelVideAr: 'لا توجد مركبة مسجلة حتى الآن',
      ),
      _MagasinProfilTab(
        config: widget.config,
        isAr: widget.isAr,
        onLogout: _logout,
        onSos: _envoyerSos,
        sosEnCours: _sosEnCours,
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: 'Demandes',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_none),
            selectedIcon: Icon(Icons.notifications),
            label: 'Rappels',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}

class _MagasinProfilTab extends StatelessWidget {
  final AppConfig config;
  final bool isAr;
  final VoidCallback onLogout;
  final VoidCallback onSos;
  final bool sosEnCours;

  const _MagasinProfilTab({
    required this.config,
    required this.isAr,
    required this.onLogout,
    required this.onSos,
    required this.sosEnCours,
  });

  Widget _profilTile({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    Widget? trailing,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.3,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              trailing ??
                  Icon(Icons.chevron_right_rounded,
                      color: Colors.grey.shade400, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = (String fr, String ar) => isAr ? ar : fr;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            // En-tête magasin
            Container(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    config.primaryColor,
                    config.primaryColor.withValues(alpha: 0.82),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: config.primaryColor.withValues(alpha: 0.28),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.storefront_rounded,
                        color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t('Profil magasin', 'ملف المحل'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          t(
                            'Abonnement, SOS et changement de rôle',
                            'الاشتراك، الاستغاثة وتغيير الدور',
                          ),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.88),
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _profilTile(
              icon: Icons.sos,
              iconBg: config.sosColor.withValues(alpha: 0.12),
              iconColor: config.sosColor,
              title: t('Alerte SOS', 'تنبيه استغاثة'),
              subtitle: t(
                'Si ton propre véhicule tombe en panne',
                'إذا تعطلت مركبتك الخاصة',
              ),
              onTap: sosEnCours ? null : onSos,
              trailing: sosEnCours
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
            ),
            const SizedBox(height: 10),
            StreamBuilder<StoreProfile?>(
              stream: StoreService.myProfileStream(),
              builder: (context, snap) {
                final profile = snap.data;
                final loading = snap.connectionState == ConnectionState.waiting;
                return _profilTile(
                  icon: Icons.workspace_premium_outlined,
                  iconBg: config.enchereColor.withValues(alpha: 0.15),
                  iconColor: config.enchereColor,
                  title: t('Abonnement & forfaits', 'الاشتراك والباقات'),
                  subtitle: loading
                      ? t('Chargement…', 'جارٍ التحميل…')
                      : profile == null
                          ? t(
                              'Complète d’abord ta fiche magasin',
                              'أكمل أولاً ملف المحل',
                            )
                          : t(
                              'Paiements, forfait en cours et renouvellement',
                              'المدفوعات والباقة الحالية والتجديد',
                            ),
                  onTap: profile == null
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SubscriptionScreen(
                                  config: config, profile: profile),
                            ),
                          ),
                );
              },
            ),
            const SizedBox(height: 10),
            _profilTile(
              icon: Icons.swap_horiz_rounded,
              iconBg: Colors.grey.shade100,
              iconColor: Colors.black54,
              title: t('Changer de profil', 'تغيير الملف الشخصي'),
              subtitle: t(
                'Conducteur, magasin ou dépanneuse',
                'سائق، متجر أو سطحة',
              ),
              onTap: () => RoleRouter.changerDeProfil(
                context,
                config: config,
                isAr: ValueNotifier<bool>(isAr),
              ),
            ),
            const SizedBox(height: 28),
            OutlinedButton.icon(
              onPressed: onLogout,
              icon: const Icon(Icons.logout),
              label: Text(t('Se déconnecter', 'تسجيل الخروج')),
              style: OutlinedButton.styleFrom(
                foregroundColor: config.sosColor,
                side: BorderSide(color: config.sosColor.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
