import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/app_config.dart';
import '../../services/admin_service.dart';
import '../../services/marketplace_models.dart';
import '../../services/sos_models.dart';
import 'admin_payments_screen.dart';

/// Tableau de bord admin : magasins, paiements, demandes.
class AdminDashboardScreen extends StatefulWidget {
  final AppConfig config;
  const AdminDashboardScreen({super.key, required this.config});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    await AdminService.signOut();
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: widget.config.primaryColor,
        foregroundColor: Colors.white,
        title: const Text('Admin'),
        actions: [
          IconButton(
            tooltip: 'Déconnexion',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Magasins', icon: Icon(Icons.storefront, size: 18)),
            Tab(text: 'Paiements', icon: Icon(Icons.payment, size: 18)),
            Tab(text: 'Demandes', icon: Icon(Icons.list_alt, size: 18)),
            Tab(text: 'Dépanneuses', icon: Icon(Icons.local_shipping, size: 18)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _StoresTab(config: widget.config),
          AdminPaymentsScreen(config: widget.config, embedded: true),
          _RequestsTab(config: widget.config),
          _DepanneusesTab(config: widget.config),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Magasins
// ---------------------------------------------------------------------------

class _StoresTab extends StatefulWidget {
  final AppConfig config;
  const _StoresTab({required this.config});

  @override
  State<_StoresTab> createState() => _StoresTabState();
}

class _StoresTabState extends State<_StoresTab> {
  // Même correctif que store_dashboard_screen.dart : le flux est créé
  // une seule fois ici plutôt que dans build(), pour éviter qu'un
  // rebuild du parent (ex: changement d'onglet, setState ailleurs) ne
  // recrée le Stream et ne fasse repartir le StreamBuilder à zéro.
  late final Stream<List<StoreProfile>> _storesStream =
      AdminService.watchStores();

  bool _selectionMode = false;
  final Set<String> _selected = {};

  AppConfig get config => widget.config;

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
        title: const Text('Supprimer les magasins'),
        content: Text(
          'Supprimer définitivement $count magasin${count > 1 ? 's' : ''} '
          'sélectionné${count > 1 ? 's' : ''} ? Action irréversible.',
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
      await AdminService.deleteStores(_selected.toList());
      if (!mounted) return;
      setState(() {
        _selected.clear();
        _selectionMode = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '$count magasin${count > 1 ? 's' : ''} supprimé${count > 1 ? 's' : ''}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<StoreProfile>>(
      stream: _storesStream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Erreur : ${snap.error}',
                  style: const TextStyle(color: Colors.red)),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final stores = List<StoreProfile>.from(snap.data!);
        // En attente d'abord, puis actifs, puis bloqués
        stores.sort((a, b) {
          int rank(StoreProfile s) {
            if (!s.actif) return 0;
            if (!s.accesDemandesAutorise) return 1;
            return 2;
          }
          final c = rank(a).compareTo(rank(b));
          if (c != 0) return c;
          return a.nom.toLowerCase().compareTo(b.nom.toLowerCase());
        });

        if (stores.isEmpty) {
          return const Center(child: Text('Aucun magasin inscrit.'));
        }

        final enAttente = stores.where((s) => !s.actif).length;
        final actifs = stores.where((s) => s.accesDemandesAutorise).length;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(
                children: [
                  _StatChip(
                    label: 'Total',
                    value: '${stores.length}',
                    color: Colors.blueGrey,
                  ),
                  const SizedBox(width: 8),
                  _StatChip(
                    label: 'En attente',
                    value: '$enAttente',
                    color: Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  _StatChip(
                    label: 'Actifs',
                    value: '$actifs',
                    color: Colors.green,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  if (_selectionMode) ...[
                    Text(
                      '${_selected.length} sélectionné${_selected.length > 1 ? 's' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Tout sélectionner',
                      icon: const Icon(Icons.select_all),
                      onPressed: () {
                        setState(() {
                          if (_selected.length == stores.length) {
                            _selected.clear();
                          } else {
                            _selected
                              ..clear()
                              ..addAll(stores.map((s) => s.uid));
                          }
                        });
                      },
                    ),
                    IconButton(
                      tooltip: 'Supprimer la sélection',
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed:
                          _selected.isEmpty ? null : _deleteSelected,
                    ),
                    IconButton(
                      tooltip: 'Annuler',
                      icon: const Icon(Icons.close),
                      onPressed: _toggleSelectionMode,
                    ),
                  ] else ...[
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _toggleSelectionMode,
                      icon: const Icon(Icons.checklist, size: 18),
                      label: const Text('Sélection'),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: stores.length,
                itemBuilder: (context, i) => _StoreCard(
                  store: stores[i],
                  config: config,
                  selectionMode: _selectionMode,
                  selected: _selected.contains(stores[i].uid),
                  onToggleSelect: () => _toggleSelected(stores[i].uid),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 18, color: color)),
            Text(label,
                style: TextStyle(fontSize: 11, color: color.withOpacity(0.9))),
          ],
        ),
      ),
    );
  }
}

class _StoreCard extends StatelessWidget {
  final StoreProfile store;
  final AppConfig config;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onToggleSelect;
  const _StoreCard({
    required this.store,
    required this.config,
    this.selectionMode = false,
    this.selected = false,
    this.onToggleSelect,
  });

  Color get _badgeColor {
    if (!store.actif) return Colors.orange;
    if (!store.accesDemandesAutorise) return Colors.red;
    return Colors.green;
  }

  String get _badgeLabel {
    if (!store.actif) return 'En attente';
    if (!store.accesDemandesAutorise) return 'Bloqué / expiré';
    return 'Actif (${store.joursRestants} j)';
  }

  Future<void> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required Future<void> Function() action,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmer')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await action();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$title — OK')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    }
  }

  void _showActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(store.nom.isEmpty ? '(sans nom)' : store.nom,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${store.tel}\n${store.adresse}'),
              isThreeLine: true,
            ),
            const Divider(height: 1),
            if (!store.actif)
              ListTile(
                leading: const Icon(Icons.check_circle, color: Colors.green),
                title: const Text('Valider / activer le compte'),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirm(
                    context,
                    title: 'Activer le magasin',
                    body:
                        'Le magasin pourra recevoir les demandes (selon son essai/abo).',
                    action: () => AdminService.setStoreActif(
                        storeId: store.uid, actif: true),
                  );
                },
              ),
            if (store.actif)
              ListTile(
                leading: const Icon(Icons.block, color: Colors.red),
                title: const Text('Bloquer le magasin'),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirm(
                    context,
                    title: 'Bloquer',
                    body:
                        'Le magasin ne verra plus les demandes et son abo sera marqué expiré.',
                    action: () => AdminService.bloquerMagasin(store.uid),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.card_giftcard, color: Colors.blue),
              title: const Text('Remettre 30 j d\'essai'),
              onTap: () {
                Navigator.pop(ctx);
                _confirm(
                  context,
                  title: 'Essai 30 jours',
                  body: 'Active le compte et redémarre un essai de 30 jours.',
                  action: () =>
                      AdminService.remettreEssai(storeId: store.uid, jours: 30),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.workspace_premium, color: Colors.amber),
              title: const Text('Activer abo 30 jours'),
              onTap: () {
                Navigator.pop(ctx);
                _confirm(
                  context,
                  title: 'Abonnement 30 j',
                  body: 'Active le magasin avec 30 jours d\'abonnement payé.',
                  action: () => AdminService.activerAbonnement(
                      storeId: store.uid, dureeJours: 30, planId: 'mensuel'),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.workspace_premium, color: Colors.amber),
              title: const Text('Activer abo 365 jours'),
              onTap: () {
                Navigator.pop(ctx);
                _confirm(
                  context,
                  title: 'Abonnement 1 an',
                  body: 'Active le magasin avec 365 jours d\'abonnement.',
                  action: () => AdminService.activerAbonnement(
                      storeId: store.uid, dureeJours: 365, planId: 'annuel'),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copier l\'UID'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: store.uid));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('UID copié')),
                );
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('Supprimer le magasin',
                  style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _confirm(
                  context,
                  title: 'Supprimer le magasin',
                  body:
                      'Supprime définitivement la fiche de "${store.nom.isEmpty ? '(sans nom)' : store.nom}" '
                      '(abonnement, historique de paiements). Le magasin ne '
                      'pourra plus accéder à son espace tant qu\'il n\'aura '
                      'pas recréé un profil. Action irréversible.',
                  action: () => AdminService.deleteStore(store.uid),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: selected ? config.primaryColor.withOpacity(0.08) : null,
      child: ListTile(
        onTap: () {
          if (selectionMode) {
            onToggleSelect?.call();
          } else {
            _showActions(context);
          }
        },
        onLongPress: selectionMode ? null : onToggleSelect,
        leading: selectionMode
            ? Checkbox(
                value: selected,
                onChanged: (_) => onToggleSelect?.call(),
                activeColor: config.primaryColor,
              )
            : null,
        title: Text(
          store.nom.isEmpty ? '(sans nom)' : store.nom,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(store.tel.isEmpty ? 'Pas de tél.' : store.tel),
            if (store.adresse.isNotEmpty)
              Text(store.adresse,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 4),
            Text(
              'Abo : ${store.subscriptionStatus} · ID ${store.idCourt}',
              style: const TextStyle(fontSize: 11, color: Colors.black45),
            ),
            Row(
              children: [
                Icon(
                  store.aUnePosition ? Icons.location_on : Icons.location_off,
                  size: 13,
                  color: store.aUnePosition ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 3),
                Text(
                  store.aUnePosition ? 'Géolocalisé' : 'Sans position GPS',
                  style: TextStyle(
                    fontSize: 11,
                    color: store.aUnePosition ? Colors.green : Colors.orange,
                  ),
                ),
              ],
            ),
          ],
        ),
        isThreeLine: true,
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _badgeColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _badgeLabel,
            style: TextStyle(
                color: _badgeColor, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Demandes
// ---------------------------------------------------------------------------

class _RequestsTab extends StatefulWidget {
  final AppConfig config;
  const _RequestsTab({required this.config});

  @override
  State<_RequestsTab> createState() => _RequestsTabState();
}

class _RequestsTabState extends State<_RequestsTab> {
  // Même correctif que store_dashboard_screen.dart.
  late final Stream<List<PartRequest>> _requestsStream =
      AdminService.watchRequests();

  AppConfig get config => widget.config;

  bool _selectionMode = false;
  final Set<String> _selected = {};

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
    final count = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer les demandes'),
        content: Text(
          'Supprimer définitivement $count demande${count > 1 ? 's' : ''} '
          'sélectionnée${count > 1 ? 's' : ''} ? Action irréversible.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AdminService.deleteRequests(_selected.toList());
      if (mounted) {
        setState(() {
          _selected.clear();
          _selectionMode = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$count demande${count > 1 ? 's' : ''} supprimée${count > 1 ? 's' : ''}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PartRequest>>(
      stream: _requestsStream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Text('Erreur : ${snap.error}',
                style: const TextStyle(color: Colors.red)),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snap.data!;
        if (list.isEmpty) {
          return const Center(child: Text('Aucune demande.'));
        }
        return Column(
          children: [
            Material(
              color: _selectionMode
                  ? config.primaryColor.withOpacity(0.08)
                  : Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    if (_selectionMode) ...[
                      Text(
                        '${_selected.length} sélectionnée${_selected.length > 1 ? 's' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Tout sélectionner',
                        icon: const Icon(Icons.select_all),
                        onPressed: () => setState(() {
                          _selected
                            ..clear()
                            ..addAll(list.map((r) => r.id));
                        }),
                      ),
                      IconButton(
                        tooltip: 'Supprimer la sélection',
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed:
                            _selected.isEmpty ? null : _deleteSelected,
                      ),
                      IconButton(
                        tooltip: 'Annuler',
                        icon: const Icon(Icons.close),
                        onPressed: _toggleSelectionMode,
                      ),
                    ] else ...[
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _toggleSelectionMode,
                        icon: const Icon(Icons.checklist),
                        label: const Text('Sélectionner'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final r = list[i];
                  final selected = _selected.contains(r.id);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: selected
                        ? config.primaryColor.withOpacity(0.08)
                        : null,
                    child: ListTile(
                      onTap: _selectionMode
                          ? () => _toggleSelected(r.id)
                          : null,
                      onLongPress: () {
                        if (!_selectionMode) {
                          setState(() => _selectionMode = true);
                        }
                        _toggleSelected(r.id);
                      },
                      leading: _selectionMode
                          ? Checkbox(
                              value: selected,
                              onChanged: (_) => _toggleSelected(r.id),
                            )
                          : (r.photoUrl.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.network(
                                    r.photoUrl,
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(
                                        Icons.image_not_supported),
                                  ),
                                )
                              : const Icon(Icons.build)),
                      title: Text(r.pieceNom,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '${r.statut} · ${r.reference}\n'
                        'Client ${r.clientId.length > 8 ? r.clientId.substring(0, 8) : r.clientId}…',
                      ),
                      isThreeLine: true,
                      trailing: _selectionMode
                          ? null
                          : PopupMenuButton<String>(
                              onSelected: (v) async {
                                try {
                                  if (v == 'close') {
                                    await AdminService.closeRequest(r.id);
                                  } else if (v == 'delete') {
                                    await AdminService.deleteRequest(r.id);
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      SnackBar(content: Text('Erreur : $e')),
                                    );
                                  }
                                }
                              },
                              itemBuilder: (_) => [
                                if (r.statut == 'open')
                                  const PopupMenuItem(
                                      value: 'close',
                                      child: Text('Clôturer')),
                                const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Supprimer')),
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
  }
}

// ---------------------------------------------------------------------------
// Dépanneuses (bouton SOS)
// ---------------------------------------------------------------------------

class _DepanneusesTab extends StatelessWidget {
  final AppConfig config;
  const _DepanneusesTab({required this.config});

  Future<void> _confirmerSuppression(
    BuildContext context,
    DepanneuseProfile d,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la dépanneuse'),
        content: Text('Supprimer définitivement "${d.nom}" ? Action irréversible.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await AdminService.deleteDepanneuse(d.uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DepanneuseProfile>>(
      stream: AdminService.watchDepanneuses(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final depanneuses = List<DepanneuseProfile>.from(snap.data!);
        depanneuses.sort((a, b) {
          final c = (a.actif ? 1 : 0).compareTo(b.actif ? 1 : 0);
          if (c != 0) return c;
          return a.nom.toLowerCase().compareTo(b.nom.toLowerCase());
        });

        if (depanneuses.isEmpty) {
          return const Center(child: Text('Aucun compte dépanneuse inscrit.'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: depanneuses.length,
          itemBuilder: (context, i) {
            final d = depanneuses[i];
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: (d.actif ? config.primaryColor : Colors.orange)
                      .withOpacity(0.12),
                  child: Icon(Icons.local_shipping,
                      color: d.actif ? config.primaryColor : Colors.orange),
                ),
                title: Text(d.nom.isEmpty ? d.tel : d.nom,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${d.wilaya} — ${d.tel}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: d.actif,
                      activeColor: config.primaryColor,
                      onChanged: (v) => AdminService.setDepanneuseActif(
                        depanneuseId: d.uid,
                        actif: v,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Supprimer',
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _confirmerSuppression(context, d),
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
}
