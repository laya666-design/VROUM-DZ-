import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_config.dart';
import '../../services/sos_models.dart';
import '../../services/sos_service.dart';
import '../../services/vehicule.dart';
import '../../theme/app_theme.dart';
import '../role_router.dart';
import '../vehicles_screen.dart';
import 'depanneuse_auth_screen.dart';
import 'depanneuse_dashboard_screen.dart';

/// Portail Dépanneuse :
/// Alertes · Historique · Rappels (véhicule de dépannage : assurance/CT) ·
/// Profil — pas de bouton SOS.
class DepanneuseShellScreen extends StatefulWidget {
  final AppConfig config;
  final bool isAr;

  const DepanneuseShellScreen({
    super.key,
    required this.config,
    this.isAr = false,
  });

  @override
  State<DepanneuseShellScreen> createState() => _DepanneuseShellScreenState();
}

class _DepanneuseShellScreenState extends State<DepanneuseShellScreen> {
  int _index = 0;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _ensureAuth();
  }

  Future<void> _ensureAuth() async {
    await SosService.loadPhoneAsId();
    // Même précaution que côté magasin : attendre que Firebase Auth ait
    // fini de restaurer une éventuelle session persistée avant de
    // conclure à une déconnexion (évite un aller-retour vers l'écran de
    // connexion juste après un redémarrage de l'app).
    await SosService.waitForAuthReady();
    if (!mounted) return;
    if (!SosService.isDepanneuseLoggedIn) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DepanneuseAuthScreen(config: widget.config),
        ),
      );
      return;
    }
    setState(() => _checking = false);
  }

  Future<void> _logout() async {
    await SosService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => DepanneuseAuthScreen(config: widget.config),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: widget.config.sosColor),
        ),
      );
    }

    final screens = [
      DepanneuseDashboardScreen(config: widget.config),
      _HistoriqueTab(config: widget.config, isAr: widget.isAr),
      // Rappels = le véhicule de dépannage (assurance/CT), même écran
      // que côté conducteur.
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
      _DepanneuseProfilTab(
        config: widget.config,
        isAr: widget.isAr,
        onLogout: _logout,
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.warning_amber_outlined),
            selectedIcon: Icon(Icons.warning_amber),
            label: 'Alertes',
          ),
          NavigationDestination(
            icon: Icon(Icons.history),
            selectedIcon: Icon(Icons.history),
            label: 'Historique',
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

class _HistoriqueTab extends StatelessWidget {
  final AppConfig config;
  final bool isAr;

  const _HistoriqueTab({required this.config, required this.isAr});

  @override
  Widget build(BuildContext context) {
    final t = (String fr, String ar) => isAr ? ar : fr;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(t('Historique', 'السجل')),
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: t('Menu principal', 'القائمة الرئيسية'),
          icon: const Icon(Icons.home_outlined),
          onPressed: () =>
              Navigator.of(context).popUntil((route) => route.isFirst),
        ),
      ),
      body: StreamBuilder<List<SosAlert>>(
        stream: SosService.myAcceptedAlertsStream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: config.sosColor),
            );
          }
          final list = snap.data ?? [];
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.history, size: 56, color: AppColors.textMuted),
                    const SizedBox(height: 12),
                    Text(
                      t('Aucune intervention pour le moment', 'لا توجد تدخّلات بعد'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final a = list[i];
              final date = a.dateAcceptation ?? a.dateCreation;
              final hh = date.hour.toString().padLeft(2, '0');
              final mm = date.minute.toString().padLeft(2, '0');
              final jour =
                  '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: a.estArrivee
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFFEE2E2),
                    child: Icon(
                      a.estArrivee ? Icons.check : Icons.local_shipping,
                      color: a.estArrivee ? config.primaryDark : config.sosColor,
                    ),
                  ),
                  title: Text(
                    'Panne — ${a.wilaya}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '$jour $hh:$mm · ${a.statut}'
                    '${a.clientTel.isNotEmpty ? ' · ${a.clientTel}' : ''}',
                  ),
                  trailing: a.aUnePosition
                      ? IconButton(
                          icon: Icon(Icons.map, color: config.sosColor),
                          onPressed: () {
                            final url = a.lienMapsPosition;
                            if (url != null) {
                              launchUrl(
                                Uri.parse(url),
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          },
                        )
                      : null,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _DepanneuseProfilTab extends StatelessWidget {
  final AppConfig config;
  final bool isAr;
  final VoidCallback onLogout;

  const _DepanneuseProfilTab({
    required this.config,
    required this.isAr,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final t = (String fr, String ar) => isAr ? ar : fr;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(t('Profil dépanneuse', 'ملف السطحّة')),
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: t('Menu principal', 'القائمة الرئيسية'),
          icon: const Icon(Icons.home_outlined),
          onPressed: () =>
              Navigator.of(context).popUntil((route) => route.isFirst),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Abonnement / paiements — pas encore de modèle payant défini
          // pour les dépanneuses (contrairement au magasin qui a déjà
          // son système). Carte visible mais désactivée en attendant.
          Card(
            child: ListTile(
              enabled: false,
              leading: CircleAvatar(
                backgroundColor: Colors.grey.shade100,
                child: const Icon(Icons.workspace_premium_outlined,
                    color: Colors.black38),
              ),
              title: Text(
                t('Abonnement & forfaits', 'الاشتراك والباقات'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                t('Bientôt disponible', 'قريباً'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.grey.shade100,
                child: const Icon(Icons.swap_horiz, color: Colors.black54),
              ),
              title: Text(
                t('Changer de profil', 'تغيير الملف الشخصي'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                t('Conducteur, magasin ou dépanneuse', 'سائق، متجر أو سطحة'),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => RoleRouter.changerDeProfil(
                context,
                config: config,
                isAr: ValueNotifier<bool>(isAr),
              ),
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: onLogout,
            icon: const Icon(Icons.logout),
            label: Text(t('Se déconnecter', 'تسجيل الخروج')),
            style: OutlinedButton.styleFrom(
              foregroundColor: config.sosColor,
              side: BorderSide(color: config.sosColor.withValues(alpha: 0.4)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}
