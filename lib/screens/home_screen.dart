import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../services/sos_service.dart';
import '../services/vehicule.dart';
import '../services/vehicule_service.dart';
import 'parts_portal_screen.dart';
import 'profile_screen.dart';
import 'sos/sos_alert_sent_screen.dart';
import 'sos/tel_picker_dialog.dart';
import 'sos/wilaya_picker_dialog.dart';
import 'vehicles_screen.dart';

class HomeScreen extends StatefulWidget {
  final AppConfig config;
  final ValueNotifier<bool> isAr;

  const HomeScreen({super.key, required this.config, required this.isAr});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  bool _sosEnvoiEnCours = false;

  // Appui simple sur le bouton SOS : diffuse une alerte de panne aux
  // dépanneuses de la wilaya de l'utilisateur, après confirmation (pour
  // éviter un envoi accidentel).
  Future<void> _envoyerAlerteSos(bool isAr) async {
    if (_sosEnvoiEnCours) return;

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

    var wilaya = SettingsService.wilaya;
    if (wilaya == null) {
      wilaya = await showWilayaPickerDialog(context, accentColor: widget.config.sosColor);
      if (wilaya == null || !mounted) return;
      await SettingsService.setWilaya(wilaya);
    }

    var tel = SettingsService.userTel;
    if (tel == null) {
      tel = await showTelPickerDialog(context, accentColor: widget.config.sosColor);
      if (tel == null || !mounted) return;
      await SettingsService.setUserTel(tel);
    }

    setState(() => _sosEnvoiEnCours = true);
    try {
      final alertId = await SosService.sendAlert(wilaya: wilaya, telephone: tel);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SosAlertSentScreen(
            config: widget.config,
            alertId: alertId,
            wilaya: wilaya!,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
    } finally {
      if (mounted) setState(() => _sosEnvoiEnCours = false);
    }
  }

  // Onglet Pièces désactivé pour le moment (aucun magasin inscrit sur la
  // marketplace) : au lieu de basculer sur PartsPortalScreen, on affiche
  // juste un message "bientôt disponible".
  void _onPiecesTapBloque(bool isAr) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isAr
              ? 'قريباً — سوق القطع غير متاح حالياً'
              : 'Bientôt disponible — la marketplace pièces arrive prochainement',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.isAr,
      builder: (context, isAr, _) {
        // Profil choisi à l'onboarding (voiture / moto / les deux) :
        // pilote quels onglets sont affichés. 'both' par défaut si
        // jamais absent (ne devrait pas arriver, l'onboarding est
        // obligatoire avant d'atteindre cet écran).
        final profile = SettingsService.vehicleProfile ?? 'both';
        final showVoiture = profile == 'voiture' || profile == 'both';
        final showMoto = profile == 'moto' || profile == 'both';

        // Clés uniques obligatoires pour IndexedStack : sans elles, Flutter
        // peut réutiliser les éléments Material/Ink entre onglets et déclencher
        // l'erreur "A GlobalKey was used multiple times ... ink renderer".
        final screens = <Widget>[
          if (showVoiture)
            VehiclesScreen(
              key: const ValueKey('tab_voitures'),
              config: widget.config,
              isAr: isAr,
            ),
          if (showMoto)
            VehiclesScreen(
              key: const ValueKey('tab_motos'),
              config: widget.config,
              isAr: isAr,
              types: const [TypeVehicule.moto, TypeVehicule.scooter],
              titre: 'Motos & scooters',
              titreAr: 'الدراجات النارية',
              sousTitre: 'Scanne assurance & CT — rappels avant expiration.',
              sousTitreAr: 'امسح التأمين والفحص — تذكيرات قبل الانتهاء.',
              iconePrincipale: Icons.two_wheeler,
              labelAjout: 'Ajouter une moto / un scooter',
              labelAjoutAr: 'إضافة دراجة نارية / سكوتر',
              labelVide: 'Aucune moto ni scooter pour le moment',
              labelVideAr: 'لا توجد دراجة حتى الآن',
            ),
          PartsPortalScreen(
            key: const ValueKey('tab_pieces'),
            config: widget.config,
            isAr: isAr,
          ),
          ProfileScreen(
            key: const ValueKey('tab_profil'),
            config: widget.config,
            isAr: widget.isAr,
            onVehicleProfileChanged: () => setState(() {}),
          ),
        ];

        // Index de l'onglet "Pièces" dans la liste finale des destinations
        // (dépend du nombre d'onglets véhicules affichés avant lui).
        final piecesIndex = (showVoiture ? 1 : 0) + (showMoto ? 1 : 0);

        final destinations = <NavigationDestination>[
          if (showVoiture)
            NavigationDestination(
              icon: const Icon(Icons.directions_car),
              label: isAr ? 'سياراتي' : 'Véhicules',
            ),
          if (showMoto)
            NavigationDestination(
              icon: const Icon(Icons.two_wheeler),
              label: isAr ? 'دراجاتي' : 'Motos',
            ),
          NavigationDestination(
            // Icône et libellé grisés pour indiquer que l'onglet est
            // désactivé temporairement (pas encore de magasin inscrit).
            icon: Icon(Icons.build, color: Colors.grey.shade400),
            label: isAr ? 'القطع (قريباً)' : 'Pièces (bientôt)',
          ),
          NavigationDestination(
            icon: const Icon(Icons.person),
            label: isAr ? 'حسابي' : 'Profil',
          ),
        ];

        // Filet de sécurité si le nombre d'onglets change (ex: profil
        // modifié depuis l'onglet Profil) pendant qu'un onglet au-delà
        // de la nouvelle liste était sélectionné.
        final safeIndex = _index >= screens.length ? 0 : _index;

        return Directionality(
          textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            appBar: AppBar(
              backgroundColor: widget.config.primaryColor,
              foregroundColor: Colors.white,
              toolbarHeight: 96,
              titleSpacing: 0,
              flexibleSpace: ClipRect(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      'assets/images/logo_header.png',
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      errorBuilder: (context, error, stack) => Container(
                        color: widget.config.primaryColor,
                        alignment: Alignment.center,
                        child: Text(widget.config.appName,
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                    // Bouton langue fixé tout en bas à gauche du bandeau (cercle rouge)
                    // : bascule uniquement le label AR/FR, sans déplacement.
                    Positioned(
                      bottom: 4,
                      left: 12,
                      child: Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        elevation: 3,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => widget.isAr.value = !isAr,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            child: Text(
                              isAr ? 'FR' : 'AR',
                              style: TextStyle(
                                  color: widget.config.primaryColor,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            body: IndexedStack(index: safeIndex, children: screens),
            floatingActionButton: FloatingActionButton(
                backgroundColor: widget.config.sosColor,
                onPressed: _sosEnvoiEnCours ? null : () => _envoyerAlerteSos(isAr),
                child: _sosEnvoiEnCours
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Text(
                        'SOS',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13),
                      ),
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: safeIndex,
              onDestinationSelected: (i) {
                if (i == piecesIndex) {
                  // Onglet désactivé : on affiche juste le message, on ne
                  // change pas d'onglet.
                  _onPiecesTapBloque(isAr);
                  return;
                }
                setState(() => _index = i);
              },
              destinations: destinations,
            ),
          ),
        );
      },
    );
  }
}
