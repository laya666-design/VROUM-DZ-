import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../../config/app_config.dart';
import '../../services/marketplace_models.dart';
import '../../services/notification_service.dart';
import '../../services/part_categories.dart';
import '../../services/store_service.dart';
import '../../widgets/screen_background.dart';
import '../role_router.dart';
import 'store_complete_profile_screen.dart';
import 'store_phone_login_screen.dart';
import 'subscription_screen.dart';

class StoreDashboardScreen extends StatefulWidget {
  final AppConfig config;
  const StoreDashboardScreen({super.key, required this.config});

  @override
  State<StoreDashboardScreen> createState() => _StoreDashboardScreenState();
}

class _StoreDashboardScreenState extends State<StoreDashboardScreen> {
  final _player = AudioPlayer();
  String? _noteVocaleEnCours; // url en cours de lecture, pour l'icône

  // IMPORTANT : ces flux sont créés une seule fois ici (et non pas
  // directement dans `build()`). Un StreamBuilder qui reçoit une NOUVELLE
  // instance de Stream à chaque reconstruction repart en ConnectionState
  // .waiting et ré-abonne une toute nouvelle requête Firestore. Comme le
  // profil magasin (_profileStream) peut se réémettre (ex: écriture du
  // fcmToken juste après connexion), tout l'écran se reconstruisait et
  // relançait _openRequestsStream en boucle — c'était la cause probable
  // du dashboard qui restait vide/figé sans jamais afficher la liste, le
  // spinner ou "Aucune commande".
  late final Stream<StoreProfile?> _profileStream =
      StoreService.myProfileStream();
  late final Stream<List<PartRequest>> _openRequestsStream =
      StoreService.openRequests();

  // Sélection multiple + masquage local des commandes
  bool _selectionMode = false;
  final Set<String> _selected = {};
  Set<String> _hiddenIds = {};
  Set<String> _seenIds = {};
  List<String> _storeCategories = [];
  StreamSubscription<List<PartRequest>>? _requestsSub;
  StreamSubscription<StoreProfile?>? _profileSub;
  int _lastKnownCount = -1; // total visible (pour détecter nouvelles arrivées)
  int _unreadCount = 0; // badge = non consultées
  bool _specialtyPromptShown = false;

  @override
  void initState() {
    super.initState();
    _loadHiddenAndSeen();
    // Garde les catégories à jour pour le badge / notif locales.
    // Juste après connexion : si aucune spécialité, force le dialogue
    // (le magasin ne doit pas pouvoir rester sans catégories).
    _profileSub = StoreService.myProfileStream().listen((p) {
      if (!mounted) return;
      setState(() => _storeCategories = p?.categories ?? const []);
      if (p != null &&
          !p.aDesCategories &&
          !_specialtyPromptShown) {
        _specialtyPromptShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _editCategories(p, force: true);
        });
      }
    });
    // Écoute dédiée pour badge + notification à l'arrivée d'une nouvelle demande
    // (déjà filtrée par les catégories du magasin).
    _requestsSub = StoreService.openRequests().listen((all) async {
      final hidden = await StoreService.hiddenRequestIds();
      final seen = await StoreService.seenRequestIds();
      final filtered =
          StoreService.filtrerParCategories(all, _storeCategories);
      final visible =
          filtered.where((r) => !hidden.contains(r.id)).toList();
      final count = visible.length;
      final unread = visible.where((r) => !seen.contains(r.id)).length;
      if (_lastKnownCount >= 0 && count > _lastKnownCount) {
        final delta = count - _lastKnownCount;
        HapticFeedback.mediumImpact();
        SystemSound.play(SystemSoundType.alert);
        await NotificationService.showNow(
          title: 'Nouvelle demande',
          body: delta == 1
              ? '1 nouvelle demande reçue'
              : '$delta nouvelles demandes reçues',
          id: 1001,
        );
      }
      if (mounted) {
        setState(() {
          _hiddenIds = hidden;
          _seenIds = seen;
          _lastKnownCount = count;
          _unreadCount = unread;
        });
      } else {
        _lastKnownCount = count;
        _unreadCount = unread;
        _hiddenIds = hidden;
        _seenIds = seen;
      }
    });
  }

  Future<void> _loadHiddenAndSeen() async {
    final hidden = await StoreService.hiddenRequestIds();
    final seen = await StoreService.seenRequestIds();
    if (mounted) {
      setState(() {
        _hiddenIds = hidden;
        _seenIds = seen;
      });
    }
  }

  Future<void> _marquerVue(String requestId) async {
    if (_seenIds.contains(requestId)) return;
    await StoreService.markRequestsSeen([requestId]);
    if (!mounted) return;
    setState(() {
      _seenIds = {..._seenIds, requestId};
      _unreadCount = (_unreadCount - 1).clamp(0, 9999);
    });
  }

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      if (!_selectionMode) _selected.clear();
    });
  }

  void _toggleSelected(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  Future<void> _hideSelected() async {
    if (_selected.isEmpty) return;
    final count = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retirer les commandes'),
        content: Text(
          'Retirer $count commande${count > 1 ? 's' : ''} de ta liste ? '
          'Les données de l\'acheteur ne sont pas modifiées.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Retirer')),
        ],
      ),
    );
    if (ok != true) return;
    await StoreService.hideRequests(_selected.toList());
    final ids = await StoreService.hiddenRequestIds();
    if (!mounted) return;
    setState(() {
      _hiddenIds = ids;
      _selected.clear();
      _selectionMode = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              '$count commande${count > 1 ? 's' : ''} retirée${count > 1 ? 's' : ''}')),
    );
  }

  Future<void> _hideOne(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retirer cette commande'),
        content: const Text(
          'Retirer cette commande de ta liste ? '
          'Les données de l\'acheteur ne sont pas modifiées.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Retirer')),
        ],
      ),
    );
    if (ok != true) return;
    await StoreService.hideRequests([id]);
    final ids = await StoreService.hiddenRequestIds();
    if (!mounted) return;
    setState(() => _hiddenIds = ids);
  }

  @override
  void dispose() {
    _requestsSub?.cancel();
    _profileSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _ecouterNoteVocale(String url) async {
    if (_noteVocaleEnCours == url) {
      await _player.stop();
      setState(() => _noteVocaleEnCours = null);
      return;
    }
    setState(() => _noteVocaleEnCours = url);
    await _player.play(UrlSource(url));
    _player.onPlayerComplete.first.then((_) {
      if (mounted) setState(() => _noteVocaleEnCours = null);
    });
  }

  Future<void> _logout() async {
    await StoreService.signOut();
    if (!mounted) return;
    // Vide toute la pile pour empêcher le retour vers le dashboard.
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
          builder: (_) => StorePhoneLoginScreen(config: widget.config)),
      (route) => false,
    );
  }

  Future<void> _mettreAJourPosition() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Localisation en cours...')),
    );
    try {
      await StoreService.updateLocation();
      messenger.showSnackBar(
        const SnackBar(content: Text('Position du magasin mise à jour.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  Future<void> _editCategories(StoreProfile profile, {bool force = false}) async {
    final selected = Set<String>.from(profile.categories);
    final autreCtrl =
        TextEditingController(text: profile.categorieAutre ?? '');
    String? error;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: !force,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return PopScope(
              canPop: !force,
              child: AlertDialog(
                title: const Text('Mes spécialités'),
                content: SizedBox(
                  width: double.maxFinite,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          force
                              ? 'Choisis au moins une spécialité pour recevoir des demandes. Obligatoire après connexion.'
                              : 'Coche les types de pièces que tu vends. Tu ne verras que les demandes correspondantes.',
                          style: const TextStyle(fontSize: 13, color: Colors.black54),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final cat in kPartCategories)
                              FilterChip(
                                label: Text(cat.labelFr),
                                selected: selected.contains(cat.id),
                                onSelected: (_) {
                                  setLocal(() {
                                    if (selected.contains(cat.id)) {
                                      selected.remove(cat.id);
                                    } else {
                                      selected.add(cat.id);
                                    }
                                    error = null;
                                  });
                                },
                                selectedColor:
                                    widget.config.primaryColor.withOpacity(0.2),
                                checkmarkColor: widget.config.primaryColor,
                              ),
                          ],
                        ),
                        if (selected.contains(kCategorieAutre)) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: autreCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Précise ta spécialité *',
                              hintText:
                                  'Ex. pièces poids lourds, climatisation…',
                            ),
                          ),
                        ],
                        if (error != null) ...[
                          const SizedBox(height: 8),
                          Text(error!,
                              style: const TextStyle(color: Colors.red, fontSize: 13)),
                        ],
                      ],
                    ),
                  ),
                ),
                actions: [
                  if (!force)
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Annuler'),
                    ),
                  FilledButton(
                    onPressed: () {
                      if (selected.isEmpty) {
                        setLocal(() =>
                            error = 'Choisis au moins une catégorie.');
                        return;
                      }
                      if (selected.contains(kCategorieAutre) &&
                          autreCtrl.text.trim().isEmpty) {
                        setLocal(() => error =
                            'Précise ta spécialité dans le champ « Autre ».');
                        return;
                      }
                      Navigator.pop(ctx, true);
                    },
                    child: const Text('Enregistrer'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (ok != true || !mounted) {
      // Si forcé et non enregistré, permettre de re-proposer au prochain
      // rebuild / écoute profil.
      if (force) _specialtyPromptShown = false;
      autreCtrl.dispose();
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      await StoreService.updateCategories(
        categories: selected.toList(),
        categorieAutre: selected.contains(kCategorieAutre)
            ? autreCtrl.text.trim()
            : null,
      );
      if (mounted) {
        setState(() => _storeCategories = selected.toList());
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Spécialités mises à jour.')),
      );
    } catch (e) {
      if (force) _specialtyPromptShown = false;
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      autreCtrl.dispose();
    }
  }

  Future<void> _repondre(PartRequest r) async {
    final prixController = TextEditingController();
    final stockController = TextEditingController();
    final messageController = TextEditingController();

    final recorder = AudioRecorder();
    // Holder mutable pour éviter les soucis de closure avec StatefulBuilder
    final hold = _NoteHold();
    bool enregistrement = false;
    int duree = 0;
    DateTime? debut;
    bool envoiEnCours = false;
    String? cheminEnCours; // path du fichier en cours d'enregistrement

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> arreterEtCapturer() async {
              if (!enregistrement) return;
              final path = await recorder.stop();
              final file = (path != null && path.isNotEmpty) ? File(path) : null;
              // Vérifie que le fichier existe vraiment sur disque
              final okFile = file != null && await file.exists();
              setLocal(() {
                enregistrement = false;
                hold.file = okFile ? file : null;
                if (okFile && duree == 0 && debut != null) {
                  duree = DateTime.now().difference(debut!).inSeconds;
                }
              });
            }

            Future<void> basculerEnregistrement() async {
              if (enregistrement) {
                await arreterEtCapturer();
                return;
              }
              final autorise = await recorder.hasPermission();
              if (!autorise) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                      content: Text('Autorisation microphone refusée.')),
                );
                return;
              }
              final dir = await getTemporaryDirectory();
              final path =
                  '${dir.path}/offre_note_${DateTime.now().millisecondsSinceEpoch}.m4a';
              cheminEnCours = path;
              await recorder.start(const RecordConfig(), path: path);
              debut = DateTime.now();
              setLocal(() {
                enregistrement = true;
                duree = 0;
                hold.file = null;
              });
              while (enregistrement && ctx.mounted) {
                await Future.delayed(const Duration(seconds: 1));
                if (!enregistrement || !ctx.mounted) return;
                final ecoule = debut == null
                    ? 0
                    : DateTime.now().difference(debut!).inSeconds;
                setLocal(() => duree = ecoule);
                if (ecoule >= 30) {
                  await arreterEtCapturer();
                  return;
                }
              }
            }

            return AlertDialog(
              title: Text(
                'Répondre — ${r.pieceNom}',
                style: const TextStyle(fontSize: 17),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Note vocale EN HAUT
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: hold.file != null
                            ? widget.config.primaryColor.withOpacity(0.08)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: hold.file != null
                              ? widget.config.primaryColor.withOpacity(0.4)
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed:
                                envoiEnCours ? null : basculerEnregistrement,
                            icon: Icon(
                              enregistrement
                                  ? Icons.stop_circle
                                  : Icons.mic,
                              color: enregistrement
                                  ? Colors.red
                                  : widget.config.primaryColor,
                              size: 28,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              enregistrement
                                  ? 'Enregistrement… ${duree}s — appuie sur stop'
                                  : (hold.file != null
                                      ? '✓ Note vocale prête (${duree}s)'
                                      : 'Note vocale (optionnel)'),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: hold.file != null
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: enregistrement
                                    ? Colors.red
                                    : (hold.file != null
                                        ? widget.config.primaryColor
                                        : Colors.black54),
                              ),
                            ),
                          ),
                          if (hold.file != null && !enregistrement)
                            IconButton(
                              onPressed: envoiEnCours
                                  ? null
                                  : () => setLocal(() {
                                        hold.file = null;
                                        duree = 0;
                                      }),
                              icon: const Icon(Icons.delete_outline,
                                  size: 20, color: Colors.black45),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: prixController,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Prix (DA)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: stockController,
                      decoration: const InputDecoration(
                          labelText: 'Disponibilité (ex: En stock)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: messageController,
                      decoration: const InputDecoration(
                        labelText: 'Localisation',
                        hintText: 'Ex: El Bouni, près de la gare',
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: envoiEnCours
                      ? null
                      : () async {
                          if (enregistrement) {
                            try {
                              await recorder.stop();
                            } catch (_) {}
                          }
                          if (ctx.mounted) Navigator.pop(ctx, false);
                        },
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: envoiEnCours
                      ? null
                      : () async {
                          final prix =
                              num.tryParse(prixController.text.trim());
                          if (prix == null) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                  content: Text('Indique un prix valide.')),
                            );
                            return;
                          }
                          // TOUJOURS stopper et capturer avant l'envoi
                          if (enregistrement) {
                            await arreterEtCapturer();
                          }
                          // Fallback : si le stop n'a pas rempli hold.file
                          // mais qu'un chemin était connu
                          if (hold.file == null &&
                              cheminEnCours != null) {
                            final f = File(cheminEnCours!);
                            if (await f.exists()) hold.file = f;
                          }

                          setLocal(() => envoiEnCours = true);
                          try {
                            await StoreService.respondToRequest(
                              requestId: r.id,
                              prix: prix,
                              stock: stockController.text.trim(),
                              message: messageController.text.trim(),
                              noteVocale: hold.file,
                            );
                            if (ctx.mounted) Navigator.pop(ctx, true);
                          } catch (e) {
                            setLocal(() => envoiEnCours = false);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        e.toString().replaceFirst(
                                            'Exception: ', ''))),
                              );
                            }
                          }
                        },
                  child: envoiEnCours
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Envoyer'),
                ),
              ],
            );
          },
        );
      },
    );

    await recorder.dispose();
    if (ok != true) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(hold.file != null
            ? 'Réponse + note vocale envoyées au client.'
            : 'Réponse envoyée au client.'),
      ),
    );
  }

  void _voirPhoto(String url) {
    if (url.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              child: Image.network(url, fit: BoxFit.contain),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  /// Affiche le détail complet d'une commande (photo + infos + note vocale + Répondre).
  /// Avant, un simple tap sur la carte n'ouvrait que la photo.
  void _afficherDetailCommande(PartRequest r) {
    // Consulter = marquer comme lu → le badge diminue
    _marquerVue(r.id);

    final sousTitre = r.reference.isNotEmpty
        ? 'Réf: ${r.reference}'
        : (r.compatibilite.isNotEmpty
            ? r.compatibilite.join(', ')
            : 'Sans référence');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.88,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Poignée
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // En-tête
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            r.pieceNom.isEmpty ? 'Pièce non nommée' : r.pieceNom,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Photo (tap → plein écran)
                          if (r.photoUrl.isNotEmpty) ...[
                            GestureDetector(
                              onTap: () => _voirPhoto(r.photoUrl),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: AspectRatio(
                                  aspectRatio: 4 / 3,
                                  child: Image.network(
                                    r.photoUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: Colors.grey.shade200,
                                      child: const Icon(Icons.broken_image,
                                          size: 48, color: Colors.grey),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Appuyer pour agrandir',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade600),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Infos
                          _detailLigne(
                            Icons.qr_code_2,
                            'Référence / Compatibilité',
                            sousTitre,
                          ),
                          if (r.compatibilite.isNotEmpty &&
                              r.reference.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _detailLigne(
                              Icons.directions_car_outlined,
                              'Compatibilité',
                              r.compatibilite.join(', '),
                            ),
                          ],
                          const SizedBox(height: 8),
                          _detailLigne(
                            Icons.schedule,
                            'Date de la demande',
                            _formatDate(r.dateCreation),
                          ),

                          // Note vocale du client
                          if (r.aUneNoteVocale) ...[
                            const SizedBox(height: 16),
                            const Text(
                              'Message vocal du client',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            const SizedBox(height: 8),
                            Material(
                              color: widget.config.primaryColor
                                  .withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () async {
                                  await _ecouterNoteVocale(r.noteVocaleUrl!);
                                  setSheet(() {});
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 12),
                                  child: Row(
                                    children: [
                                      Icon(
                                        _noteVocaleEnCours == r.noteVocaleUrl
                                            ? Icons.pause_circle_filled
                                            : Icons.play_circle_filled,
                                        color: widget.config.primaryColor,
                                        size: 36,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          _noteVocaleEnCours == r.noteVocaleUrl
                                              ? 'Lecture en cours…'
                                              : 'Écouter le message vocal',
                                          style: TextStyle(
                                            color: widget.config.primaryColor,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],

                          const SizedBox(height: 24),
                          // Bouton Répondre
                          FilledButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _repondre(r);
                            },
                            icon: const Icon(Icons.reply),
                            label: const Text('Répondre à cette demande'),
                            style: FilledButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              textStyle: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _detailLigne(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey.shade700),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours} h';
    if (diff.inDays < 7) return 'Il y a ${diff.inDays} j';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<StoreProfile?>(
      stream: _profileStream,
      builder: (context, profileSnap) {
        if (profileSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        // DEBUG TEMPORAIRE : avant, une erreur de lecture du profil
        // (permission-denied si l'ID du document ne correspond pas
        // exactement à l'UID connecté, etc.) était confondue avec un
        // profil simplement inexistant et affichait "Profil introuvable"
        // sans aucune indication. On distingue maintenant les deux cas.
        if (profileSnap.hasError) {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: widget.config.primaryColor,
              foregroundColor: Colors.white,
              title: const Text('Espace Pro'),
              leading: IconButton(
                tooltip: 'Changer de profil',
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  RoleRouter.changerDeProfil(
                    context,
                    config: widget.config,
                    isAr: ValueNotifier<bool>(false),
                  );
                },
              ),
              actions: [IconButton(onPressed: _logout, icon: const Icon(Icons.logout))],
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 36),
                    const SizedBox(height: 12),
                    const Text(
                      'Erreur en chargeant ton profil.',
                      style: TextStyle(fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      '${profileSnap.error}',
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: () {
                        RoleRouter.changerDeProfil(
                          context,
                          config: widget.config,
                          isAr: ValueNotifier<bool>(false),
                        );
                      },
                      icon: const Icon(Icons.swap_horiz),
                      label: const Text('Changer de profil'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        final profile = profileSnap.data;

        return Scaffold(
          appBar: AppBar(
            backgroundColor: widget.config.primaryColor,
            foregroundColor: Colors.white,
            title: _selectionMode
                ? Text('${_selected.length} sélectionnée${_selected.length > 1 ? 's' : ''}')
                : Text(profile?.nom.isNotEmpty == true ? profile!.nom : 'Espace Pro'),
            // Toujours une flèche de sortie visible :
            // - en mode sélection : ferme la sélection
            // - sinon : retour au choix de profil (évite d'être coincé
            //   quand le profil Firestore est absent / "Profil introuvable")
            leading: _selectionMode
                ? IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _toggleSelectionMode,
                  )
                : IconButton(
                    tooltip: 'Changer de profil',
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () {
                      RoleRouter.changerDeProfil(
                        context,
                        config: widget.config,
                        isAr: ValueNotifier<bool>(false),
                      );
                    },
                  ),
            actions: [
              if (_selectionMode) ...[
                IconButton(
                  tooltip: 'Tout sélectionner',
                  icon: const Icon(Icons.select_all),
                  onPressed: () {
                    // Sélection gérée dans le StreamBuilder via callback
                    // On force un rebuild ; la liste visible est dans le builder.
                    setState(() {});
                  },
                ),
                IconButton(
                  tooltip: 'Retirer la sélection',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _selected.isEmpty ? null : _hideSelected,
                ),
              ] else ...[
                if (profile != null)
                  IconButton(
                    tooltip: profile.aDesCategories
                        ? 'Mes spécialités'
                        : 'Spécialités manquantes — appuie pour les renseigner',
                    onPressed: () => _editCategories(profile),
                    icon: Icon(
                      Icons.category_outlined,
                      color: profile.aDesCategories ? null : Colors.amber,
                    ),
                  ),
                if (profile != null)
                  IconButton(
                    tooltip: profile.aUnePosition
                        ? 'Mettre à jour ma position'
                        : 'Position manquante — appuie pour la renseigner',
                    onPressed: _mettreAJourPosition,
                    icon: Icon(
                      profile.aUnePosition
                          ? Icons.location_on
                          : Icons.location_off,
                      color: profile.aUnePosition ? null : Colors.amber,
                    ),
                  ),
                if (profile != null && profile.actif)
                  IconButton(
                    tooltip: 'Mon abonnement',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SubscriptionScreen(
                            config: widget.config, profile: profile),
                      ),
                    ),
                    icon: const Icon(Icons.workspace_premium_outlined),
                  ),
                if (profile != null)
                  IconButton(
                    tooltip: 'Sélection multiple',
                    icon: const Icon(Icons.checklist),
                    onPressed: _toggleSelectionMode,
                  ),
                IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
              ],
            ],
          ),
          body: ScreenBackground(
            category: BackgroundCategory.magasin,
            accentColor: widget.config.primaryColor,
            child: profile == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.storefront_outlined,
                            size: 48, color: widget.config.primaryColor),
                        const SizedBox(height: 16),
                        const Text(
                          'Profil introuvable',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Ton compte est connecté, mais aucune fiche magasin '
                          'n\'a été trouvée. Complète ton profil ou change de rôle.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black54),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: widget.config.primaryColor,
                            minimumSize: const Size.fromHeight(48),
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => StoreCompleteProfileScreen(
                                    config: widget.config),
                              ),
                            );
                          },
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Compléter mon profil magasin'),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () {
                            RoleRouter.changerDeProfil(
                              context,
                              config: widget.config,
                              isAr: ValueNotifier<bool>(false),
                            );
                          },
                          icon: const Icon(Icons.swap_horiz),
                          label: const Text('Changer de profil'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _logout,
                          child: const Text('Se déconnecter'),
                        ),
                      ],
                    ),
                  ),
                )
              : !profile.actif
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Ton compte est en attente de validation.\n'
                          'Tu recevras les demandes une fois activé.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : !profile.accesDemandesAutorise
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.lock_clock, size: 48, color: widget.config.primaryColor),
                                const SizedBox(height: 16),
                                Text(
                                  profile.subscriptionStatus == SubscriptionStatus.enAttente
                                      ? 'Ton paiement est en cours de vérification.'
                                      : 'Ton essai gratuit ou ton abonnement est terminé.\n'
                                          'Choisis un forfait pour continuer à recevoir des commandes.',
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 20),
                                if (profile.subscriptionStatus != SubscriptionStatus.enAttente)
                                  FilledButton(
                                    style: FilledButton.styleFrom(backgroundColor: widget.config.primaryColor),
                                    onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => SubscriptionScreen(config: widget.config, profile: profile),
                                      ),
                                    ),
                                    child: const Text('Voir les forfaits'),
                                  ),
                              ],
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                              child: Row(
                                children: [
                                  Text('Commandes',
                                      style: Theme.of(context).textTheme.titleLarge),
                                  const SizedBox(width: 8),
                                  if (_unreadCount > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '$_unreadCount',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  const Spacer(),
                                  if (_selectionMode)
                                    TextButton.icon(
                                      onPressed: () {
                                        // sélectionné via builder plus bas
                                      },
                                      icon: const Icon(Icons.select_all, size: 18),
                                      label: const Text('Tout'),
                                    ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text('ID ${profile.idCourt}',
                                        style: const TextStyle(fontSize: 11, color: Colors.black54)),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: StreamBuilder<List<PartRequest>>(
                                stream: _openRequestsStream,
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState == ConnectionState.waiting) {
                                    return const Center(child: CircularProgressIndicator());
                                  }

                                  if (snapshot.hasError) {
                                    return Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(20),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.error_outline,
                                                color: Colors.red, size: 36),
                                            const SizedBox(height: 12),
                                            const Text(
                                              'Impossible de charger les commandes.',
                                              style: TextStyle(fontWeight: FontWeight.w600),
                                              textAlign: TextAlign.center,
                                            ),
                                            const SizedBox(height: 8),
                                            SelectableText(
                                              '${snapshot.error}',
                                              style: const TextStyle(
                                                  fontSize: 12, color: Colors.black54),
                                              textAlign: TextAlign.center,
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }

                                  final all = snapshot.data ?? [];
                                  // Filtre par spécialités du magasin, puis
                                  // masquage local.
                                  final filtered = StoreService.filtrerParCategories(
                                    all,
                                    profile?.categories ?? const [],
                                  );
                                  final requests = filtered
                                      .where((r) => !_hiddenIds.contains(r.id))
                                      .toList();

                                  if (requests.isEmpty) {
                                    final noCategories =
                                        (profile?.categories ?? const []).isEmpty;
                                    return Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(24),
                                        child: Container(
                                          padding: const EdgeInsets.all(20),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(16),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(0.08),
                                                blurRadius: 10,
                                                offset: const Offset(0, 3),
                                              ),
                                            ],
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                noCategories
                                                    ? Icons.category_outlined
                                                    : Icons.inbox_outlined,
                                                size: 36,
                                                color: Colors.black38,
                                              ),
                                              const SizedBox(height: 10),
                                              Text(
                                                noCategories
                                                    ? 'Renseigne tes spécialités pour recevoir des demandes.'
                                                    : 'Aucune commande pour le moment.',
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.black87),
                                              ),
                                              if (noCategories) ...[
                                                const SizedBox(height: 8),
                                                const Text(
                                                  'Sans catégories, aucune demande ne t\'est affichée.',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                      fontSize: 13,
                                                      color: Colors.black54),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  }

                                  return ColoredBox(
                                    color: const Color(0xF2FFFFFF),
                                    child: Column(
                                      children: [
                                        if (_selectionMode)
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                                            child: Row(
                                              children: [
                                                TextButton(
                                                  onPressed: () {
                                                    setState(() {
                                                      if (_selected.length ==
                                                          requests.length) {
                                                        _selected.clear();
                                                      } else {
                                                        _selected
                                                          ..clear()
                                                          ..addAll(
                                                              requests.map((r) => r.id));
                                                      }
                                                    });
                                                  },
                                                  child: Text(
                                                    _selected.length == requests.length
                                                        ? 'Tout désélectionner'
                                                        : 'Tout sélectionner',
                                                  ),
                                                ),
                                                const Spacer(),
                                                FilledButton.icon(
                                                  onPressed: _selected.isEmpty
                                                      ? null
                                                      : _hideSelected,
                                                  icon: const Icon(Icons.delete_outline,
                                                      size: 18),
                                                  label: Text(
                                                      'Retirer (${_selected.length})'),
                                                  style: FilledButton.styleFrom(
                                                    backgroundColor: Colors.red,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        Expanded(
                                          child: ListView.separated(
                                            padding: const EdgeInsets.fromLTRB(
                                                12, 8, 12, 16),
                                            itemCount: requests.length,
                                            separatorBuilder: (_, __) =>
                                                const SizedBox(height: 8),
                                            itemBuilder: (context, i) {
                                              return _carteCommande(requests[i]);
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
          ),
        );
      },
    );
  }

  Widget _carteCommande(PartRequest r) {
    final sousTitre = r.reference.isNotEmpty
        ? 'Réf: ${r.reference}'
        : (r.compatibilite.isNotEmpty
            ? r.compatibilite.join(', ')
            : 'Sans référence');
    final selected = _selected.contains(r.id);

    return Material(
      color: selected ? widget.config.primaryColor.withOpacity(0.08) : Colors.white,
      elevation: 2,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () {
          if (_selectionMode) {
            _toggleSelected(r.id);
          } else {
            // Ouvre le détail complet (photo + infos + message vocal + Répondre)
            // au lieu d'afficher uniquement la photo.
            _afficherDetailCommande(r);
          }
        },
        onLongPress: () {
          if (!_selectionMode) {
            setState(() {
              _selectionMode = true;
              _selected.add(r.id);
            });
          }
        },
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              if (_selectionMode) ...[
                Checkbox(
                  value: selected,
                  onChanged: (_) => _toggleSelected(r.id),
                  activeColor: widget.config.primaryColor,
                ),
                const SizedBox(width: 4),
              ],
              // Photo ou icône
              if (r.photoUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    r.photoUrl,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 48,
                      height: 48,
                      color: widget.config.primaryColor.withOpacity(0.12),
                      child: Icon(Icons.build,
                          color: widget.config.primaryColor, size: 22),
                    ),
                  ),
                )
              else
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: widget.config.primaryColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.build,
                      color: widget.config.primaryColor, size: 22),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.pieceNom.isEmpty ? 'Pièce non nommée' : r.pieceNom,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sousTitre,
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (!_selectionMode) ...[
                if (r.aUneNoteVocale) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: () => _ecouterNoteVocale(r.noteVocaleUrl!),
                    icon: Icon(
                      _noteVocaleEnCours == r.noteVocaleUrl
                          ? Icons.pause_circle
                          : Icons.play_circle_outline,
                      color: widget.config.primaryColor,
                    ),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                ],
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: () {
                    _marquerVue(r.id);
                    _repondre(r);
                  },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child:
                      const Text('Répondre', style: TextStyle(fontSize: 13)),
                ),
                IconButton(
                  tooltip: 'Retirer',
                  onPressed: () => _hideOne(r.id),
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: Colors.red.shade400,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Petit conteneur mutable pour le fichier audio (évite les pièges
/// de closure dans StatefulBuilder).
class _NoteHold {
  File? file;
}

