import 'package:cloud_firestore/cloud_firestore.dart';

/// Une demande de pièce diffusée aux magasins (Phase 4).
class PartRequest {
  final String id;
  final String clientId; // identifiant anonyme du demandeur (device/uid)
  final String pieceNom;
  final String reference;
  final List<String> compatibilite;
  final String photoUrl;
  final String statut; // 'open' | 'vendu' | 'closed'
  final DateTime dateCreation;
  final String? soldToStoreId;
  final String? soldToStoreNom;
  final DateTime? dateVente;

  PartRequest({
    required this.id,
    required this.clientId,
    required this.pieceNom,
    required this.reference,
    required this.compatibilite,
    required this.photoUrl,
    required this.statut,
    required this.dateCreation,
    this.soldToStoreId,
    this.soldToStoreNom,
    this.dateVente,
  });

  bool get estVendue => statut == 'vendu';
  bool get estOuverte => statut == 'open';

  factory PartRequest.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return PartRequest(
      id: doc.id,
      clientId: d['clientId']?.toString() ?? '',
      pieceNom: d['pieceNom']?.toString() ?? '',
      reference: d['reference']?.toString() ?? '',
      compatibilite: (d['compatibilite'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      photoUrl: d['photoUrl']?.toString() ?? '',
      statut: d['statut']?.toString() ?? 'open',
      dateCreation: (d['dateCreation'] as Timestamp?)?.toDate() ??
          DateTime.now(),
      soldToStoreId: d['soldToStoreId']?.toString(),
      soldToStoreNom: d['soldToStoreNom']?.toString(),
      dateVente: (d['dateVente'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'clientId': clientId,
        'pieceNom': pieceNom,
        'reference': reference,
        'compatibilite': compatibilite,
        'photoUrl': photoUrl,
        'statut': statut,
        'dateCreation': FieldValue.serverTimestamp(),
      };
}

/// La réponse d'un magasin à une demande (sous-collection de PartRequest).
class PartOffer {
  final String id;
  final String storeId;
  final String storeNom;
  final String storeTel;
  final num prix;
  final String stock; // ex: "En stock", "2-3 jours"
  final String message;
  final DateTime dateReponse;

  PartOffer({
    required this.id,
    required this.storeId,
    required this.storeNom,
    required this.storeTel,
    required this.prix,
    required this.stock,
    required this.message,
    required this.dateReponse,
  });

  factory PartOffer.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return PartOffer(
      id: doc.id,
      storeId: d['storeId']?.toString() ?? '',
      storeNom: d['storeNom']?.toString() ?? '',
      storeTel: d['storeTel']?.toString() ?? '',
      prix: (d['prix'] is num) ? d['prix'] as num : 0,
      stock: d['stock']?.toString() ?? '',
      message: d['message']?.toString() ?? '',
      dateReponse:
          (d['dateReponse'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'storeId': storeId,
        'storeNom': storeNom,
        'storeTel': storeTel,
        'prix': prix,
        'stock': stock,
        'message': message,
        'dateReponse': FieldValue.serverTimestamp(),
      };
}

/// Un forfait d'abonnement magasin proposé dans le portail vendeur.
class SubscriptionPlan {
  final String id;
  final String nom;
  final int dureeJours;
  final int prixDA;

  const SubscriptionPlan({
    required this.id,
    required this.nom,
    required this.dureeJours,
    required this.prixDA,
  });

  /// Prix ramené au mois, pour comparer les forfaits entre eux.
  double get prixParMoisDA => prixDA / (dureeJours / 30);
}

const List<SubscriptionPlan> kSubscriptionPlans = [
  SubscriptionPlan(id: 'mensuel', nom: 'Mensuel', dureeJours: 30, prixDA: 2000),
  SubscriptionPlan(
      id: 'trimestriel', nom: 'Trimestriel', dureeJours: 90, prixDA: 5000),
  SubscriptionPlan(id: 'annuel', nom: 'Annuel', dureeJours: 365, prixDA: 18000),
];

/// Statuts d'abonnement possibles pour un magasin.
class SubscriptionStatus {
  static const essai = 'essai'; // mois d'essai gratuit
  static const actif = 'actif'; // abonnement payé, en cours
  static const enAttente = 'paiement_en_attente'; // preuve envoyée, à valider
  static const expire = 'expire'; // essai ou abonnement terminé, non renouvelé
}

/// Profil d'un magasin abonné (compte Pro).
class StoreProfile {
  final String uid;
  final String nom;
  final String tel;
  final String adresse;
  final bool actif; // identité validée manuellement (compte non-fake)
  final String? fcmToken;
  final String subscriptionStatus; // voir SubscriptionStatus
  final DateTime? trialEndDate;
  final DateTime? subscriptionEndDate;
  final String? currentPlanId; // dernier forfait payé (voir kSubscriptionPlans)

  StoreProfile({
    required this.uid,
    required this.nom,
    required this.tel,
    required this.adresse,
    required this.actif,
    this.fcmToken,
    this.subscriptionStatus = SubscriptionStatus.essai,
    this.trialEndDate,
    this.subscriptionEndDate,
    this.currentPlanId,
  });

  /// Identifiant court du magasin à afficher dans l'app (support/admin).
  String get idCourt => uid.length > 6 ? uid.substring(0, 6).toUpperCase() : uid.toUpperCase();

  /// Le magasin a-t-il le droit de voir/répondre aux demandes en ce moment ?
  /// (identité validée ET essai ou abonnement toujours en cours)
  bool get accesDemandesAutorise {
    if (!actif) return false;
    final now = DateTime.now();
    if (subscriptionStatus == SubscriptionStatus.essai) {
      return trialEndDate != null && trialEndDate!.isAfter(now);
    }
    if (subscriptionStatus == SubscriptionStatus.actif) {
      return subscriptionEndDate != null && subscriptionEndDate!.isAfter(now);
    }
    return false;
  }

  /// Jours restants sur l'essai ou l'abonnement en cours (0 si terminé).
  int get joursRestants {
    final now = DateTime.now();
    final DateTime? fin = subscriptionStatus == SubscriptionStatus.essai
        ? trialEndDate
        : subscriptionEndDate;
    if (fin == null) return 0;
    final diff = fin.difference(now).inHours / 24;
    return diff > 0 ? diff.ceil() : 0;
  }

  factory StoreProfile.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return StoreProfile(
      uid: doc.id,
      nom: d['nom']?.toString() ?? '',
      tel: d['tel']?.toString() ?? '',
      adresse: d['adresse']?.toString() ?? '',
      actif: d['actif'] as bool? ?? false,
      fcmToken: d['fcmToken']?.toString(),
      subscriptionStatus:
          d['subscriptionStatus']?.toString() ?? SubscriptionStatus.essai,
      trialEndDate: (d['trialEndDate'] as Timestamp?)?.toDate(),
      subscriptionEndDate: (d['subscriptionEndDate'] as Timestamp?)?.toDate(),
      currentPlanId: d['currentPlanId']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'nom': nom,
        'tel': tel,
        'adresse': adresse,
        'actif': actif,
        if (fcmToken != null) 'fcmToken': fcmToken,
        'subscriptionStatus': subscriptionStatus,
        if (trialEndDate != null)
          'trialEndDate': Timestamp.fromDate(trialEndDate!),
        if (subscriptionEndDate != null)
          'subscriptionEndDate': Timestamp.fromDate(subscriptionEndDate!),
        if (currentPlanId != null) 'currentPlanId': currentPlanId,
      };
}

/// Une preuve de paiement envoyée par un magasin (virement/CCP/Baridimob),
/// en attente de validation manuelle avant activation de l'abonnement.
class PaymentRequest {
  final String id;
  final String storeId;
  final num montant;
  final String methode; // 'Virement' | 'CCP' | 'Baridimob'
  final String recuUrl;
  final String statut; // 'en_attente' | 'valide' | 'refuse'
  final DateTime dateEnvoi;

  PaymentRequest({
    required this.id,
    required this.storeId,
    required this.montant,
    required this.methode,
    required this.recuUrl,
    required this.statut,
    required this.dateEnvoi,
  });

  factory PaymentRequest.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return PaymentRequest(
      id: doc.id,
      storeId: d['storeId']?.toString() ?? '',
      montant: (d['montant'] is num) ? d['montant'] as num : 0,
      methode: d['methode']?.toString() ?? '',
      recuUrl: d['recuUrl']?.toString() ?? '',
      statut: d['statut']?.toString() ?? 'en_attente',
      dateEnvoi:
          (d['dateEnvoi'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'storeId': storeId,
        'montant': montant,
        'methode': methode,
        'recuUrl': recuUrl,
        'statut': statut,
        'dateEnvoi': FieldValue.serverTimestamp(),
      };
}
