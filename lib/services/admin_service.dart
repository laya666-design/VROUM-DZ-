import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'google_auth_helper.dart';
import 'marketplace_models.dart';
import 'sos_models.dart';

/// Espace admin : magasins, abonnements, paiements, demandes.
///
/// Un compte n'est admin que s'il a le custom claim `admin: true`
/// (posé via functions/setAdmin.js). Les règles Firestore autorisent
/// alors la lecture/écriture admin sur `stores` et `part_requests`.
class AdminService {
  static final _db = FirebaseFirestore.instance;

  static Future<void> signIn({
    required String email,
    required String password,
  }) async {
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  /// Connexion admin par téléphone — secours si l'email est bloqué ou
  /// oublié. Le numéro doit avoir été lié au compte au préalable via
  /// functions/linkAdminPhone.js (jamais depuis l'app). La fonction
  /// `getAdminEmailByPhone` retrouve l'email réel du compte associé, puis
  /// on se connecte normalement avec ce mail + le mot de passe fourni.
  static Future<void> signInWithPhone({
    required String telephone,
    required String password,
  }) async {
    final numero = normaliserNumeroLocal(telephone);
    if (numero == null) {
      throw Exception('Numéro invalide. Utilise le format 0556 65 32 20.');
    }
    String email;
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('getAdminEmailByPhone');
      final result = await callable.call({'telephone': numero});
      email = result.data?['email'] as String? ?? '';
      if (email.isEmpty) throw Exception('Aucun compte admin pour ce numéro.');
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'Aucun compte admin pour ce numéro.');
    }
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  /// Normalise une saisie de numéro algérien vers le format local à 10
  /// chiffres commençant par 0 (même logique que StoreService).
  static String? normaliserNumeroLocal(String saisie) {
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    const western = '0123456789';
    var s = saisie.trim();
    for (var i = 0; i < 10; i++) {
      s = s.replaceAll(eastern[i], western[i]);
    }
    var chiffres = s.replaceAll(RegExp(r'[^0-9+]'), '');

    if (chiffres.startsWith('+213') && chiffres.length == 13) {
      chiffres = '0${chiffres.substring(4)}';
    } else if (chiffres.startsWith('213') && chiffres.length == 12) {
      chiffres = '0${chiffres.substring(3)}';
    } else if (chiffres.length == 9 &&
        (chiffres.startsWith('5') ||
            chiffres.startsWith('6') ||
            chiffres.startsWith('7'))) {
      chiffres = '0$chiffres';
    }

    if (chiffres.startsWith('0') && chiffres.length == 10) {
      return chiffres;
    }
    return null;
  }

  static Future<bool> isCurrentUserAdmin({bool force = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final token = await user.getIdTokenResult(force);
    return token.claims?['admin'] == true;
  }

  static Future<void> signOut() => FirebaseAuth.instance.signOut();


  static Future<void> signInWithGoogle() async {
    await GoogleAuthHelper.signIn();
    final isAdmin = await isCurrentUserAdmin(force: true);
    if (!isAdmin) {
      await FirebaseAuth.instance.signOut();
      throw Exception('Ce compte Google n\'a pas les droits admin.');
    }
  }

  static Future<void> sendPasswordResetEmail(String email) async {
    await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
  }

  // --- Magasins ----------------------------------------------------------

  static Stream<List<StoreProfile>> watchStores() {
    return _db.collection('stores').snapshots().map(
          (s) => s.docs.map(StoreProfile.fromDoc).toList(),
        );
  }

  static Future<List<StoreProfile>> listStores() async {
    final snap = await _db.collection('stores').get();
    return snap.docs.map(StoreProfile.fromDoc).toList();
  }

  static Future<void> setStoreActif({
    required String storeId,
    required bool actif,
  }) async {
    await _db.collection('stores').doc(storeId).update({'actif': actif});
  }

  /// Supprime la fiche magasin de Firestore (magasins, plus ses
  /// sous-collections payment_requests). Ne supprime PAS le compte
  /// Firebase Auth associé (nécessite Admin SDK/Cloud Function) : le
  /// magasin ne pourra donc plus se connecter à un espace actif, mais le
  /// compte d'authentification lui-même reste et pourrait recréer une
  /// fiche magasin en se reconnectant. Suffisant pour retirer un
  /// magasin de test ou un magasin fermé de la liste.
  static Future<void> deleteStore(String storeId) async {
    final ref = _db.collection('stores').doc(storeId);
    final payments = await ref.collection('payment_requests').get();
    final batch = _db.batch();
    for (final p in payments.docs) {
      batch.delete(p.reference);
    }
    batch.delete(ref);
    await batch.commit();
  }

  // --- Dépanneuses (bouton SOS) -------------------------------------------

  static Stream<List<DepanneuseProfile>> watchDepanneuses() {
    return _db.collection('depanneuses').snapshots().map(
          (s) => s.docs.map(DepanneuseProfile.fromDoc).toList(),
        );
  }

  static Future<void> setDepanneuseActif({
    required String depanneuseId,
    required bool actif,
  }) async {
    await _db.collection('depanneuses').doc(depanneuseId).update({'actif': actif});
  }

  static Future<void> deleteDepanneuse(String depanneuseId) async {
    await _db.collection('depanneuses').doc(depanneuseId).delete();
  }

  /// Suppression multiple de magasins (batch par magasin).
  static Future<void> deleteStores(List<String> storeIds) async {
    for (final id in storeIds) {
      await deleteStore(id);
    }
  }

  static Future<void> activerAbonnement({
    required String storeId,
    required int dureeJours,
    String? planId,
  }) async {
    final fin = DateTime.now().add(Duration(days: dureeJours));
    await _db.collection('stores').doc(storeId).update({
      'actif': true,
      'subscriptionStatus': SubscriptionStatus.actif,
      'subscriptionEndDate': Timestamp.fromDate(fin),
      if (planId != null) 'currentPlanId': planId,
    });
  }

  static Future<void> bloquerMagasin(String storeId) async {
    await _db.collection('stores').doc(storeId).update({
      'actif': false,
      'subscriptionStatus': SubscriptionStatus.expire,
    });
  }

  static Future<void> remettreEssai({
    required String storeId,
    int jours = 30,
  }) async {
    final fin = DateTime.now().add(Duration(days: jours));
    await _db.collection('stores').doc(storeId).update({
      'actif': true,
      'subscriptionStatus': SubscriptionStatus.essai,
      'trialEndDate': Timestamp.fromDate(fin),
    });
  }

  // --- Paiements ---------------------------------------------------------

  static Future<List<Map<String, dynamic>>> listPendingPayments() async {
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('listPendingPayments');
      final result = await callable.call();
      final payments = (result.data?['payments'] as List?) ?? [];
      return payments.cast<Map<String, dynamic>>();
    } catch (_) {
      return _listPendingPaymentsFirestore();
    }
  }

  static Future<List<Map<String, dynamic>>> _listPendingPaymentsFirestore() async {
    final stores = await _db.collection('stores').get();
    final out = <Map<String, dynamic>>[];
    for (final storeDoc in stores.docs) {
      final payments = await storeDoc.reference
          .collection('payment_requests')
          .where('statut', isEqualTo: 'en_attente')
          .get();
      final store = StoreProfile.fromDoc(storeDoc);
      for (final p in payments.docs) {
        final d = p.data();
        out.add({
          'paymentId': p.id,
          'storeId': storeDoc.id,
          'storeNom': store.nom,
          'storeTel': store.tel,
          'montant': d['montant'],
          'methode': d['methode'],
          'planId': d['planId'],
          'recuUrl': d['recuUrl'],
          'dateEnvoi': d['dateEnvoi'],
        });
      }
    }
    out.sort((a, b) {
      final da = a['dateEnvoi'];
      final db = b['dateEnvoi'];
      if (da is Timestamp && db is Timestamp) {
        return db.compareTo(da);
      }
      return 0;
    });
    return out;
  }

  static Future<void> validatePayment({
    required String storeId,
    required String paymentId,
  }) async {
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('validatePayment');
      await callable.call({'storeId': storeId, 'paymentId': paymentId});
      return;
    } catch (_) {}
    final payRef = _db
        .collection('stores')
        .doc(storeId)
        .collection('payment_requests')
        .doc(paymentId);
    final paySnap = await payRef.get();
    final data = paySnap.data() ?? {};
    final planId = data['planId']?.toString();
    SubscriptionPlan? plan;
    for (final p in kSubscriptionPlans) {
      if (p.id == planId) {
        plan = p;
        break;
      }
    }
    final jours = plan?.dureeJours ?? 30;
    final fin = DateTime.now().add(Duration(days: jours));

    final batch = _db.batch();
    batch.update(payRef, {'statut': 'valide'});
    batch.update(_db.collection('stores').doc(storeId), {
      'actif': true,
      'subscriptionStatus': SubscriptionStatus.actif,
      'subscriptionEndDate': Timestamp.fromDate(fin),
      if (planId != null) 'currentPlanId': planId,
    });
    await batch.commit();
  }

  static Future<void> rejectPayment({
    required String storeId,
    required String paymentId,
    String? raison,
  }) async {
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('rejectPayment');
      await callable.call({
        'storeId': storeId,
        'paymentId': paymentId,
        if (raison != null) 'raison': raison,
      });
      return;
    } catch (_) {}
    await _db
        .collection('stores')
        .doc(storeId)
        .collection('payment_requests')
        .doc(paymentId)
        .update({
      'statut': 'refuse',
      if (raison != null) 'raison': raison,
    });
  }

  // --- Paiements Premium individuel (automobiliste) -----------------------
  // Collection top-level `premium_requests`, gérée exclusivement via les
  // Cloud Functions dédiées (voir functions/index.js) : pas de repli
  // Firestore direct ici, les règles Firestore n'autorisent rien sur
  // cette collection (tout passe par l'Admin SDK côté serveur).

  static Future<List<Map<String, dynamic>>> listPendingPremiumPayments() async {
    final callable =
        FirebaseFunctions.instance.httpsCallable('listPendingPremiumPayments');
    final result = await callable.call();
    final payments = (result.data?['payments'] as List?) ?? [];
    return payments.cast<Map<String, dynamic>>();
  }

  static Future<void> validatePremiumPayment({required String requestId}) async {
    final callable =
        FirebaseFunctions.instance.httpsCallable('validatePremiumPayment');
    await callable.call({'requestId': requestId});
  }

  static Future<void> rejectPremiumPayment({
    required String requestId,
    String? raison,
  }) async {
    final callable =
        FirebaseFunctions.instance.httpsCallable('rejectPremiumPayment');
    await callable.call({
      'requestId': requestId,
      if (raison != null) 'raison': raison,
    });
  }

  // --- Demandes ----------------------------------------------------------

  static Stream<List<PartRequest>> watchRequests({int limit = 50}) {
    return _db
        .collection('part_requests')
        .orderBy('dateCreation', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(PartRequest.fromDoc).toList());
  }

  static Future<void> closeRequest(String requestId) async {
    await _db
        .collection('part_requests')
        .doc(requestId)
        .update({'statut': 'closed'});
  }

  static Future<void> deleteRequest(String requestId) async {
    await _db.collection('part_requests').doc(requestId).delete();
  }

  /// Supprime plusieurs demandes en une fois (sélection multiple côté
  /// admin). Utilise un batch Firestore (max 500 par batch, largement
  /// suffisant ici) plutôt qu'une boucle d'appels individuels.
  static Future<void> deleteRequests(List<String> requestIds) async {
    if (requestIds.isEmpty) return;
    final batch = _db.batch();
    for (final id in requestIds) {
      batch.delete(_db.collection('part_requests').doc(id));
    }
    await batch.commit();
  }
}
