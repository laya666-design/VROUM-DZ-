import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_config.dart';
import '../../services/location_service.dart';
import '../../services/marketplace_models.dart';
import '../../services/marketplace_service.dart';
import '../../services/notification_service.dart';

class MesDemandesScreen extends StatefulWidget {
  final AppConfig config;
  const MesDemandesScreen({super.key, required this.config});

  @override
  State<MesDemandesScreen> createState() => _MesDemandesScreenState();
}

class _MesDemandesScreenState extends State<MesDemandesScreen> {
  final _player = AudioPlayer();
  String? _noteEnCours;
  /// IDs des demandes ouvertes — pour ne pas les refermer au setState (play).
  final Set<String> _ouvertes = {};

  // Position de l'acheteur, chargée une seule fois à l'ouverture de l'écran,
  // pour afficher "à X km" sous chaque réponse de magasin qui a une
  // position connue. Reste null si le GPS/permission n'est pas disponible
  // : la carte de la réponse s'affiche quand même, juste sans distance.
  LocationResult? _maPosition;

  // État local (remplace les StreamBuilder imbriqués pour la sélection
  // multiple + détection de nouvelles réponses).
  List<PartRequest> _requests = [];
  final Map<String, List<PartOffer>> _offersCache = {};
  final Map<String, int> _lastOfferCounts = {};
  StreamSubscription<List<PartRequest>>? _requestsSub;
  final Map<String, StreamSubscription<List<PartOffer>>> _offerSubs = {};
  bool _loading = true;
  String? _error;

  // Sélection multiple
  bool _selectionMode = false;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _chargerMaPosition();
    _subscribeRequests();
  }

  void _subscribeRequests() {
    _requestsSub?.cancel();
    _requestsSub = MarketplaceService.myRequests().listen(
      (list) {
        if (!mounted) return;
        setState(() {
          _requests = list;
          _loading = false;
          _error = null;
        });
        // Abonner les offres pour chaque demande ouverte
        final ids = list.map((r) => r.id).toSet();
        // Annuler les abonnements obsolètes
        for (final id in _offerSubs.keys.toList()) {
          if (!ids.contains(id)) {
            _offerSubs[id]?.cancel();
            _offerSubs.remove(id);
            _offersCache.remove(id);
            _lastOfferCounts.remove(id);
          }
        }
        for (final r in list) {
          if (!_offerSubs.containsKey(r.id)) {
            _offerSubs[r.id] = MarketplaceService.offersFor(r.id).listen(
              (offers) {
                if (!mounted) return;
                final prev = _lastOfferCounts[r.id] ?? -1;
                if (prev >= 0 && offers.length > prev) {
                  final delta = offers.length - prev;
                  HapticFeedback.mediumImpact();
                  SystemSound.play(SystemSoundType.alert);
                  NotificationService.showNow(
                    title: 'Nouvelle réponse',
                    body: delta == 1
                        ? '1 magasin a répondu à « ${r.pieceNom.isEmpty ? 'ta demande' : r.pieceNom} »'
                        : '$delta magasins ont répondu à « ${r.pieceNom.isEmpty ? 'ta demande' : r.pieceNom} »',
                    id: 2000 + (r.id.hashCode & 0xffff),
                  );
                }
                setState(() {
                  _offersCache[r.id] = offers;
                  _lastOfferCounts[r.id] = offers.length;
                });
              },
              onError: (_) {},
            );
          }
        }
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _error = '$e';
          _loading = false;
        });
      },
    );
  }

  Future<void> _chargerMaPosition() async {
    final position = await LocationService.getCurrentPosition();
    if (mounted && position.aUnePosition) {
      setState(() => _maPosition = position);
    }
  }

  @override
  void dispose() {
    _requestsSub?.cancel();
    for (final s in _offerSubs.values) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
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

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final count = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer les demandes'),
        content: Text(
          'Supprimer définitivement $count demande${count > 1 ? 's' : ''} '
          'et leurs réponses ? Action irréversible.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await MarketplaceService.deleteRequests(_selected.toList());
      if (!mounted) return;
      setState(() {
        _selected.clear();
        _selectionMode = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '$count demande${count > 1 ? 's' : ''} supprimée${count > 1 ? 's' : ''}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
    }
  }

  Future<void> _deleteOne(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la demande'),
        content: const Text(
          'Supprimer définitivement cette demande et ses réponses ? '
          'Action irréversible.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await MarketplaceService.deleteRequest(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Demande supprimée')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
    }
  }

  Future<void> _call(String tel) async {
    if (tel.isEmpty) return;
    await launchUrl(Uri(scheme: 'tel', path: tel));
  }

  Future<void> _voirSurLaCarte(double lat, double lng) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Distance en km entre l'acheteur (si connue) et le magasin, ou null.
  double? _distanceVers(PartOffer o) {
    if (_maPosition == null || !o.aUnePosition) return null;
    return LocationService.distanceKm(
      lat1: _maPosition!.latitude!,
      lng1: _maPosition!.longitude!,
      lat2: o.storeLat!,
      lng2: o.storeLng!,
    );
  }

  Future<void> _ecouterNote(String url) async {
    if (_noteEnCours == url) {
      await _player.stop();
      setState(() => _noteEnCours = null);
      return;
    }
    setState(() => _noteEnCours = url);
    await _player.play(UrlSource(url));
    _player.onPlayerComplete.first.then((_) {
      if (mounted) setState(() => _noteEnCours = null);
    });
  }

  Future<void> _marquerVendu(
      BuildContext context, PartRequest r, PartOffer o) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Marquer comme vendue'),
        content: Text(
          'Confirmer que "${r.pieceNom}" a été achetée chez '
          '${o.storeNom.isEmpty ? 'ce magasin' : o.storeNom} '
          '(${o.prix} DA) ?\n\nLa demande sera clôturée.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
    if (confirme != true) return;
    await MarketplaceService.markAsSold(requestId: r.id, offer: o);
  }

  String _statutLabel(PartRequest r) {
    switch (r.statut) {
      case 'open':
        final offers = _offersCache[r.id];
        if (offers != null && offers.isNotEmpty) {
          final n = offers.length;
          return n == 1 ? '1 réponse reçue' : '$n réponses reçues';
        }
        return 'En attente de réponses';
      case 'vendu':
        return 'Vendue chez ${r.soldToStoreNom ?? ''}';
      default:
        return 'Clôturée';
    }
  }

  Color _statutColor(PartRequest r) {
    switch (r.statut) {
      case 'open':
        final offers = _offersCache[r.id];
        if (offers != null && offers.isNotEmpty) {
          return widget.config.primaryColor;
        }
        return Colors.orange;
      case 'vendu':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Widget _bandeauNoteVocale(PartOffer o) {
    if (!o.aUneNoteVocale) return const SizedBox.shrink();
    final enCours = _noteEnCours == o.noteVocaleUrl;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Material(
        color: widget.config.primaryColor.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => _ecouterNote(o.noteVocaleUrl!),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  enCours ? Icons.pause_circle : Icons.play_circle_filled,
                  color: widget.config.primaryColor,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    enCours
                        ? 'Lecture en cours…'
                        : 'Note vocale du magasin — appuyer pour écouter',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: widget.config.primaryColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOffers(PartRequest r) {
    if (!r.estOuverte && !r.estVendue) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Demande clôturée.',
            style: TextStyle(fontSize: 13, color: Colors.black54)),
      );
    }
    final offers = _offersCache[r.id];
    if (offers == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (offers.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Pas encore de réponse. Les magasins sont '
          'notifiés, reviens un peu plus tard.',
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),
      );
    }
    return Column(
      children: offers.map((o) {
        final sousTitre = o.stock.isEmpty
            ? (o.message.isEmpty ? '' : o.message)
            : '${o.stock}${o.message.isNotEmpty ? ' — ${o.message}' : ''}';
        final distance = _distanceVers(o);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _bandeauNoteVocale(o),
            ListTile(
              title: Text(
                o.storeNom.isEmpty ? 'Magasin' : o.storeNom,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sousTitre.isEmpty ? 'Sans précision' : sousTitre,
                  ),
                  if (o.aUnePosition)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.location_on,
                              size: 14, color: widget.config.primaryColor),
                          const SizedBox(width: 4),
                          Text(
                            distance != null
                                ? 'à $distance km de toi'
                                : 'Position connue',
                            style: TextStyle(
                              fontSize: 12,
                              color: widget.config.primaryColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              isThreeLine: o.aUnePosition,
              // trailing compact pour éviter "BOTTOM OVERFLOWED BY 2.0 PIXELS"
              trailing: SizedBox(
                width: 108,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${o.prix} DA',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (o.aUnePosition)
                          InkWell(
                            onTap: () =>
                                _voirSurLaCarte(o.storeLat!, o.storeLng!),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.map_outlined, size: 20),
                            ),
                          ),
                        if (o.storeTel.isNotEmpty)
                          InkWell(
                            onTap: () => _call(o.storeTel),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.call, size: 20),
                            ),
                          ),
                        if (r.estOuverte)
                          InkWell(
                            onTap: () => _marquerVendu(context, r, o),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.check_circle_outline,
                                  size: 20, color: Colors.green),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: widget.config.primaryColor,
        foregroundColor: Colors.white,
        title: _selectionMode
            ? Text(
                '${_selected.length} sélectionnée${_selected.length > 1 ? 's' : ''}')
            : const Text('Mes demandes'),
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _toggleSelectionMode,
              )
            : null,
        actions: [
          if (_selectionMode) ...[
            IconButton(
              tooltip: 'Tout sélectionner',
              icon: const Icon(Icons.select_all),
              onPressed: () {
                setState(() {
                  if (_selected.length == _requests.length) {
                    _selected.clear();
                  } else {
                    _selected
                      ..clear()
                      ..addAll(_requests.map((r) => r.id));
                  }
                });
              },
            ),
            IconButton(
              tooltip: 'Supprimer la sélection',
              icon: const Icon(Icons.delete_outline),
              onPressed: _selected.isEmpty ? null : _deleteSelected,
            ),
          ] else ...[
            IconButton(
              tooltip: 'Sélection multiple',
              icon: const Icon(Icons.checklist),
              onPressed: _toggleSelectionMode,
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Erreur : $_error'),
                  ),
                )
              : _requests.isEmpty
                  ? const Center(
                      child: Text('Aucune demande diffusée pour le moment.'),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _requests.length,
                      itemBuilder: (context, i) {
                        final r = _requests[i];
                        final isOpen = _ouvertes.contains(r.id);
                        final selected = _selected.contains(r.id);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          color: selected
                              ? widget.config.primaryColor.withOpacity(0.08)
                              : null,
                          child: ExpansionTile(
                            key: PageStorageKey('demande_${r.id}'),
                            maintainState: true,
                            initiallyExpanded: isOpen,
                            onExpansionChanged: (open) {
                              if (_selectionMode) return;
                              setState(() {
                                if (open) {
                                  _ouvertes.add(r.id);
                                } else {
                                  _ouvertes.remove(r.id);
                                }
                              });
                            },
                            leading: _selectionMode
                                ? Checkbox(
                                    value: selected,
                                    onChanged: (_) => _toggleSelected(r.id),
                                    activeColor: widget.config.primaryColor,
                                  )
                                : (r.photoUrl.isNotEmpty
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: Image.network(r.photoUrl,
                                            width: 48,
                                            height: 48,
                                            fit: BoxFit.cover),
                                      )
                                    : const Icon(Icons.build)),
                            title: GestureDetector(
                              onTap: _selectionMode
                                  ? () => _toggleSelected(r.id)
                                  : null,
                              onLongPress: () {
                                if (!_selectionMode) {
                                  setState(() {
                                    _selectionMode = true;
                                    _selected.add(r.id);
                                  });
                                }
                              },
                              child: Text(
                                  r.pieceNom.isEmpty ? 'Pièce' : r.pieceNom),
                            ),
                            subtitle: Text(
                              _statutLabel(r),
                              style: TextStyle(
                                color: _statutColor(r),
                                fontSize: 12,
                              ),
                            ),
                            trailing: _selectionMode
                                ? null
                                : IconButton(
                                    tooltip: 'Supprimer',
                                    icon: Icon(Icons.delete_outline,
                                        size: 20, color: Colors.red.shade400),
                                    onPressed: () => _deleteOne(r.id),
                                  ),
                            children: [_buildOffers(r)],
                          ),
                        );
                      },
                    ),
    );
  }
}
