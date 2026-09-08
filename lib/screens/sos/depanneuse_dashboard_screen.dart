import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_config.dart';
import '../../config/wilayas.dart';
import '../../services/sos_models.dart';
import '../../services/sos_service.dart';
import '../../services/store_service.dart';
import '../role_selection_screen.dart';
import 'depanneuse_alert_accepted_screen.dart';
import 'depanneuse_auth_screen.dart';

/// Tableau de bord dépanneuse : liste des alertes SOS ouvertes dans sa
/// wilaya, avec bouton "J'y vais" pour accepter (affiche alors le
/// téléphone de la dépanneuse côté utilisateur).
class DepanneuseDashboardScreen extends StatefulWidget {
  final AppConfig config;
  const DepanneuseDashboardScreen({super.key, required this.config});

  @override
  State<DepanneuseDashboardScreen> createState() =>
      _DepanneuseDashboardScreenState();
}

class _DepanneuseDashboardScreenState
    extends State<DepanneuseDashboardScreen> {
  late final Stream<DepanneuseProfile?> _profileStream =
      SosService.myProfileStream();

  // Cache du flux d'alertes par wilaya : sans ça, chaque nouvelle valeur
  // émise par _profileStream (ex: écriture du fcmToken juste après
  // l'ouverture de l'écran) recréait un tout nouveau flux Firestore ici,
  // qui repartait de zéro (même bug que l'onglet Commandes du portail
  // magasin, corrigé en hoistant le flux au lieu de le recréer à chaque
  // build).
  String? _wilayaEnCours;
  Stream<List<SosAlert>>? _alertesStream;

  Stream<List<SosAlert>> _alertesStreamPour(String wilaya) {
    if (_wilayaEnCours != wilaya) {
      _wilayaEnCours = wilaya;
      _alertesStream = SosService.openAlertsForMyWilaya(wilaya);
    }
    return _alertesStream!;
  }

  @override
  void initState() {
    super.initState();
    SosService.saveFcmToken();
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

  // Alertes en cours d'acceptation : désactive le bouton pendant l'appel
  // réseau, pour qu'un appui affiche tout de suite un retour visuel (au
  // lieu de sembler ne rien faire pendant l'attente Firestore).
  final Set<String> _enCoursAcceptation = {};

  Future<void> _accepter(SosAlert alerte) async {
    if (_enCoursAcceptation.contains(alerte.id)) return;
    setState(() => _enCoursAcceptation.add(alerte.id));
    try {
      await SosService.acceptAlert(alerte.id);
      if (!mounted) return;
      // Emmène directement la dépanneuse sur le numéro du client et la
      // position du véhicule, au lieu d'un simple SnackBar qui pouvait
      // passer inaperçu.
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DepanneuseAlertAcceptedScreen(
            config: widget.config,
            alerte: alerte,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SosService.friendlyError(e))),
      );
    } finally {
      if (mounted) setState(() => _enCoursAcceptation.remove(alerte.id));
    }
  }

  Future<void> _completerProfil(DepanneuseProfile profile) async {
    final telCtrl = TextEditingController(text: profile.tel);
    String? wilayaChoisie;
    String? erreurTel;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) => AlertDialog(
            title: const Text('Compléter mon profil'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: telCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: 'Téléphone',
                    hintText: '0556 65 32 20',
                    errorText: erreurTel,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: wilayaChoisie,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Wilaya',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: kWilayasAlgerie
                      .map((w) => DropdownMenuItem(value: w, child: Text(w)))
                      .toList(),
                  onChanged: (v) => setStateDialog(() => wilayaChoisie = v),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () async {
                  final numero =
                      StoreService.normaliserNumeroLocal(telCtrl.text);
                  if (numero == null) {
                    setStateDialog(() =>
                        erreurTel = 'Numéro invalide. Ex : 0556 65 32 20.');
                    return;
                  }
                  if (wilayaChoisie == null) return;
                  try {
                    await SosService.updateMyProfile(
                      telephone: numero,
                      wilaya: wilayaChoisie!,
                    );
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text(SosService.friendlyError(e))),
                      );
                    }
                  }
                },
                child: const Text('Valider'),
              ),
            ],
          ),
        );
      },
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil mis à jour.')),
      );
    }
  }

  Future<void> _ouvrirCarte(String lien) async {
    final uri = Uri.parse(lien);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sos = widget.config.sosColor;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: sos,
        foregroundColor: Colors.white,
        title: const Text('Alertes SOS'),
        actions: [
          IconButton(
            tooltip: 'Déconnexion',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: StreamBuilder<DepanneuseProfile?>(
        stream: _profileStream,
        builder: (context, profileSnap) {
          if (profileSnap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      SosService.friendlyError(profileSnap.error!),
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                            builder: (_) => DepanneuseAuthScreen(
                              config: widget.config,
                            ),
                          ),
                          (_) => false,
                        );
                      },
                      icon: const Icon(Icons.login),
                      label: const Text('Se reconnecter'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                            builder: (_) => RoleSelectionScreen(
                              config: widget.config,
                              isAr: ValueNotifier<bool>(false),
                            ),
                          ),
                          (_) => false,
                        );
                      },
                      child: const Text('Menu principal'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!profileSnap.hasData) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Chargement du profil…'),
                ],
              ),
            );
          }
          final profile = profileSnap.data;
          if (profile == null) {
            return const Center(child: Text('Profil introuvable.'));
          }
          if (!profile.actif) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.hourglass_top, size: 48, color: Colors.orange.shade400),
                    const SizedBox(height: 16),
                    const Text(
                      'Compte en attente de validation',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${profile.nom} — ${profile.wilaya}\nTon compte sera activé manuellement avant de recevoir les alertes.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
            );
          }

          // Auto-réparation : compte créé (ex: via Google, avant ce
          // correctif) ou modifié à la main sans wilaya renseignée — sans
          // ça la requête ci-dessous cherche 'wilaya == ""' et ne trouve
          // jamais aucune alerte réelle, silencieusement ("Aucune alerte
          // en attente"), sans jamais expliquer pourquoi.
          if (profile.wilaya.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.location_off, size: 48, color: sos),
                    const SizedBox(height: 16),
                    const Text(
                      'Profil incomplet',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Ta wilaya n\'est pas renseignée : tu ne peux recevoir '
                      'aucune alerte tant qu\'elle n\'est pas complétée.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: sos),
                      onPressed: () => _completerProfil(profile),
                      icon: const Icon(Icons.edit),
                      label: const Text('Compléter mon profil'),
                    ),
                  ],
                ),
              ),
            );
          }

          return StreamBuilder<List<SosAlert>>(
            stream: _alertesStreamPour(profile.wilaya),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      SosService.friendlyError(snap.error!),
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              if (!snap.hasData) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text('Recherche des alertes pour "${profile.wilaya}"…'),
                    ],
                  ),
                );
              }
              final alertes = snap.data!;
              return Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: sos.withOpacity(0.08),
                    child: Text(
                      '${profile.nom} — Wilaya de ${profile.wilaya}',
                      style: TextStyle(fontWeight: FontWeight.w600, color: sos),
                    ),
                  ),
                  if (alertes.isEmpty)
                    Expanded(
                      child: Center(
                        child: Text(
                          'Aucune alerte en attente dans ta wilaya.',
                          style: const TextStyle(color: Colors.black87),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: alertes.length,
                        itemBuilder: (context, i) {
                          final a = alertes[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    backgroundColor: sos.withOpacity(0.12),
                                    child: Icon(Icons.warning_amber_rounded, color: sos),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Panne — ${a.wilaya}',
                                          style: const TextStyle(fontWeight: FontWeight.w600),
                                        ),
                                        const SizedBox(height: 4),
                                        if (a.aUnePosition)
                                          InkWell(
                                            onTap: () => _ouvrirCarte(a.lienMapsPosition!),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.location_on, size: 15, color: sos),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Voir la position du véhicule',
                                                  style: TextStyle(
                                                    color: sos,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                    decoration: TextDecoration.underline,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          )
                                        else
                                          const Text(
                                            'Sans position GPS',
                                            style: TextStyle(color: Colors.black54, fontSize: 13),
                                          ),
                                        Text(
                                          '${a.dateCreation.hour.toString().padLeft(2, '0')}:${a.dateCreation.minute.toString().padLeft(2, '0')}',
                                          style: const TextStyle(color: Colors.black54, fontSize: 13),
                                        ),
                                        const SizedBox(height: 10),
                                        SizedBox(
                                          width: double.infinity,
                                          child: FilledButton(
                                            onPressed: _enCoursAcceptation.contains(a.id)
                                                ? null
                                                : () => _accepter(a),
                                            style: FilledButton.styleFrom(backgroundColor: sos),
                                            child: _enCoursAcceptation.contains(a.id)
                                                ? const SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.white,
                                                    ),
                                                  )
                                                : const Text("J'y vais"),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
