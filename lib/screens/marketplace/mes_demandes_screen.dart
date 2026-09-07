import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_config.dart';
import '../../services/marketplace_models.dart';
import '../../services/marketplace_service.dart';

class MesDemandesScreen extends StatelessWidget {
  final AppConfig config;
  const MesDemandesScreen({super.key, required this.config});

  Future<void> _call(String tel) async {
    if (tel.isEmpty) return;
    await launchUrl(Uri(scheme: 'tel', path: tel));
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
        return Colors.orange;
      case 'vendu':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: config.primaryColor,
        foregroundColor: Colors.white,
        title: const Text('Mes demandes'),
      ),
      body: StreamBuilder<List<PartRequest>>(
        stream: MarketplaceService.myRequests(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Erreur : ${snapshot.error}'),
              ),
            );
          }
          final requests = snapshot.data ?? [];
          if (requests.isEmpty) {
            return const Center(
              child: Text('Aucune demande diffusée pour le moment.'),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: requests.length,
            itemBuilder: (context, i) {
              final r = requests[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ExpansionTile(
                  leading: r.photoUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(r.photoUrl,
                              width: 48, height: 48, fit: BoxFit.cover),
                        )
                      : const Icon(Icons.build),
                  title: Text(r.pieceNom.isEmpty ? 'Pièce' : r.pieceNom),
                  subtitle: Text(
                    _statutLabel(r),
                    style: TextStyle(
                      color: _statutColor(r),
                      fontSize: 12,
                    ),
                  ),
                  children: [
                    if (!r.estOuverte && !r.estVendue)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Demande clôturée.',
                            style: TextStyle(
                                fontSize: 13, color: Colors.black54)),
                      )
                    else
                    StreamBuilder<List<PartOffer>>(
                      stream: MarketplaceService.offersFor(r.id),
                      builder: (context, offerSnap) {
                        final offers = offerSnap.data ?? [];
                        if (offerSnap.connectionState ==
                                ConnectionState.waiting &&
                            offers.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(
                                child: CircularProgressIndicator(
                                    strokeWidth: 2)),
                          );
                        }
                        if (offers.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'Pas encore de réponse. Les magasins sont '
                              'notifiés, reviens un peu plus tard.',
                              style: TextStyle(
                                  fontSize: 13, color: Colors.black54),
                            ),
                          );
                        }
                        return Column(
                          children: offers
                              .map((o) => ListTile(
                                    title: Text(
                                        o.storeNom.isEmpty
                                            ? 'Magasin'
                                            : o.storeNom,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600)),
                                    subtitle: Text(o.stock.isEmpty
                                        ? (o.message.isEmpty
                                            ? ''
                                            : o.message)
                                        : '${o.stock}${o.message.isNotEmpty ? ' — ${o.message}' : ''}'),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text('${o.prix} DA',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold)),
                                        if (o.storeTel.isNotEmpty)
                                          IconButton(
                                            icon: const Icon(Icons.call,
                                                size: 20),
                                            onPressed: () => _call(o.storeTel),
                                          ),
                                        if (r.estOuverte)
                                          IconButton(
                                            tooltip: 'Marquer comme vendue',
                                            icon: const Icon(
                                                Icons.check_circle_outline,
                                                size: 20,
                                                color: Colors.green),
                                            onPressed: () =>
                                                _marquerVendu(context, r, o),
                                          ),
                                      ],
                                    ),
                                  ))
                              .toList(),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
