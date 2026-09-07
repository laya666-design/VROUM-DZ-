import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'cloudinary_service.dart';
import 'marketplace_models.dart';

/// Marketplace pièces — côté demandeur (client).
///
/// Nécessite Firestore + Firebase Storage (Phase 4). Le client n'a pas de
/// compte : on utilise un identifiant anonyme généré une fois et stocké
/// localement (Hive), pour retrouver "mes demandes" sans forcer une
/// inscription.
class MarketplaceService {
  static const _requestsCollection = 'part_requests';
  static const _settingsBox = 'settings';
  static const _clientIdKey = 'marketplace_client_id';

  static String get clientId {
    final box = Hive.box(_settingsBox);
    var id = box.get(_clientIdKey) as String?;
    if (id == null) {
      id = 'c_${DateTime.now().microsecondsSinceEpoch}';
      box.put(_clientIdKey, id);
    }
    return id;
  }

  /// Diffuse une demande de pièce à tous les magasins actifs.
  /// Upload la photo sur Firebase Storage puis crée le document Firestore.
  /// Un Cloud Function (voir /functions) notifie les magasins par push.
  static Future<String> broadcastRequest({
    required File photo,
    required String pieceNom,
    required String reference,
    required List<String> compatibilite,
  }) async {
    final id = FirebaseFirestore.instance.collection(_requestsCollection).doc().id;

    final photoUrl = await CloudinaryService.uploadImage(
      photo,
      folder: 'part_requests',
    );

    final request = PartRequest(
      id: id,
      clientId: clientId,
      pieceNom: pieceNom,
      reference: reference,
      compatibilite: compatibilite,
      photoUrl: photoUrl,
      statut: 'open',
      dateCreation: DateTime.now(),
    );

    await FirebaseFirestore.instance
        .collection(_requestsCollection)
        .doc(id)
        .set(request.toMap());

    return id;
  }

  /// Mes demandes, les plus récentes d'abord.
  static Stream<List<PartRequest>> myRequests() {
    return FirebaseFirestore.instance
        .collection(_requestsCollection)
        .where('clientId', isEqualTo: clientId)
        .orderBy('dateCreation', descending: true)
        .snapshots()
        .map((s) => s.docs.map(PartRequest.fromDoc).toList());
  }

  /// Réponses des magasins pour une demande donnée, en temps réel,
  /// triées par prix croissant (les moins chères en premier).
  static Stream<List<PartOffer>> offersFor(String requestId) {
    return FirebaseFirestore.instance
        .collection(_requestsCollection)
        .doc(requestId)
        .collection('offers')
        .orderBy('prix')
        .snapshots()
        .map((s) => s.docs.map(PartOffer.fromDoc).toList());
  }

  static Future<void> closeRequest(String requestId) async {
    await FirebaseFirestore.instance
        .collection(_requestsCollection)
        .doc(requestId)
        .update({'statut': 'closed'});
  }

  /// Marque la demande comme vendue chez le magasin sélectionné : elle
  /// disparaît immédiatement des demandes ouvertes des magasins (la tâche
  /// est "terminée") et garde une trace de qui l'a vendue.
  static Future<void> markAsSold({
    required String requestId,
    required PartOffer offer,
  }) async {
    await FirebaseFirestore.instance
        .collection(_requestsCollection)
        .doc(requestId)
        .update({
      'statut': 'vendu',
      'soldToStoreId': offer.storeId,
      'soldToStoreNom': offer.storeNom,
      'dateVente': FieldValue.serverTimestamp(),
    });
  }
}
