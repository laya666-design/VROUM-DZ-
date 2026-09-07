import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'cloudinary_service.dart';
import 'marketplace_models.dart';

/// Prix de l'abonnement mensuel magasin, en DA.
const int kAbonnementPrixMensuelDA = 2000;
const int kEssaiGratuitJours = 30;

/// Marketplace pièces — côté magasin ("Espace Pro").
///
/// Compte email/mot de passe (Firebase Auth) ou Google Sign-In. Un magasin
/// créé via [signUp] ou [signInWithGoogle] (première connexion) est
/// enregistré avec `actif: false` : il ne reçoit ni ne voit aucune demande
/// tant qu'il n'a pas été validé manuellement (passage à `actif: true` dans
/// la console Firestore). C'est volontaire pour la Phase 4 — pas de vraie
/// modération automatisée pour l'instant, juste un verrou pour éviter les
/// faux comptes actifs par défaut.
class StoreService {
  static const _storesCollection = 'stores';
  static const _rememberMeKey = 'store_remember_me';

  static User? get currentUser => FirebaseAuth.instance.currentUser;
  static bool get isLoggedIn => currentUser != null;

  static Future<void> signUp({
    required String email,
    required String password,
    required String nom,
    required String tel,
    required String adresse,
  }) async {
    final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final profile = StoreProfile(
      uid: cred.user!.uid,
      nom: nom,
      tel: tel,
      adresse: adresse,
      actif: false,
      subscriptionStatus: SubscriptionStatus.essai,
      trialEndDate:
          DateTime.now().add(const Duration(days: kEssaiGratuitJours)),
    );
    await FirebaseFirestore.instance
        .collection(_storesCollection)
        .doc(cred.user!.uid)
        .set(profile.toMap());
    await _registerFcmToken(cred.user!.uid);
  }

  static Future<void> signIn({
    required String email,
    required String password,
    bool rememberMe = true,
  }) async {
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    await _saveRememberMe(rememberMe);
    final uid = currentUser?.uid;
    if (uid != null) await _registerFcmToken(uid);
  }

  /// Connexion (ou inscription automatique si c'est la première fois)
  /// avec un compte Google. Si le magasin n'existe pas encore dans
  /// Firestore, un profil minimal est créé avec `actif: false` — comme
  /// pour [signUp], une validation manuelle reste nécessaire ; le magasin
  /// peut ensuite compléter téléphone/adresse depuis son tableau de bord.
  static Future<void> signInWithGoogle({bool rememberMe = true}) async {
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) {
      throw Exception('Connexion Google annulée.');
    }
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    final userCred =
        await FirebaseAuth.instance.signInWithCredential(credential);
    final user = userCred.user;
    if (user == null) {
      throw Exception('Connexion Google impossible.');
    }
    await _saveRememberMe(rememberMe);

    final docRef =
        FirebaseFirestore.instance.collection(_storesCollection).doc(user.uid);
    final doc = await docRef.get();
    if (!doc.exists) {
      final profile = StoreProfile(
        uid: user.uid,
        nom: user.displayName ?? '',
        tel: '',
        adresse: '',
        actif: false,
        subscriptionStatus: SubscriptionStatus.essai,
        trialEndDate:
            DateTime.now().add(const Duration(days: kEssaiGratuitJours)),
      );
      await docRef.set(profile.toMap());
    }
    await _registerFcmToken(user.uid);
  }

  static Future<void> _saveRememberMe(bool rememberMe) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberMeKey, rememberMe);
  }

  /// À appeler une fois au démarrage de l'app (avant d'afficher le portail
  /// vendeur) : si le magasin s'était connecté sans cocher "Se souvenir de
  /// moi", on force la déconnexion pour que la session ne survive pas au
  /// redémarrage de l'app, même si Firebase Auth garde la session active
  /// par défaut.
  static Future<void> applyRememberMePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberMe = prefs.getBool(_rememberMeKey) ?? true;
    if (!rememberMe && currentUser != null) {
      await FirebaseAuth.instance.signOut();
    }
  }

  static Future<void> signOut() => FirebaseAuth.instance.signOut();

  static Future<void> _registerFcmToken(String uid) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await FirebaseFirestore.instance
          .collection(_storesCollection)
          .doc(uid)
          .update({'fcmToken': token});
    } catch (_) {
      // Permission notifications refusée ou token indisponible : le
      // magasin reste utilisable, juste sans push (il peut toujours
      // ouvrir l'app pour voir les demandes).
    }
  }

  static Future<StoreProfile?> myProfile() async {
    final uid = currentUser?.uid;
    if (uid == null) return null;
    final doc = await FirebaseFirestore.instance
        .collection(_storesCollection)
        .doc(uid)
        .get();
    if (!doc.exists) return null;
    return StoreProfile.fromDoc(doc);
  }

  /// Demandes ouvertes, les plus récentes d'abord.
  /// MVP : tous les magasins actifs voient toutes les demandes ouvertes
  /// (pas de filtre par catégorie/proximité pour l'instant).
  static Stream<List<PartRequest>> openRequests() {
    return FirebaseFirestore.instance
        .collection('part_requests')
        .where('statut', isEqualTo: 'open')
        .orderBy('dateCreation', descending: true)
        .snapshots()
        .map((s) => s.docs.map(PartRequest.fromDoc).toList());
  }

  /// Le magasin répond à une demande avec un prix.
  static Future<void> respondToRequest({
    required String requestId,
    required num prix,
    required String stock,
    required String message,
  }) async {
    final profile = await myProfile();
    if (profile == null) {
      throw Exception('Profil magasin introuvable.');
    }
    final offer = PartOffer(
      id: '',
      storeId: profile.uid,
      storeNom: profile.nom,
      storeTel: profile.tel,
      prix: prix,
      stock: stock,
      message: message,
      dateReponse: DateTime.now(),
    );
    await FirebaseFirestore.instance
        .collection('part_requests')
        .doc(requestId)
        .collection('offers')
        .doc(profile.uid) // un seul prix par magasin, ré-écrasable
        .set(offer.toMap());
  }

  /// Envoie une preuve de paiement (photo du reçu) pour activer ou
  /// renouveler l'abonnement. Statut mis en 'paiement_en_attente' :
  /// validation manuelle par l'équipe (comme pour `actif`), qui bascule
  /// ensuite le magasin sur `subscriptionStatus = 'actif'` avec une
  /// nouvelle `subscriptionEndDate` (+30 jours) depuis la console Firebase
  /// ou via la Cloud Function d'administration.
  static Future<void> submitPaymentProof({
    required File recu,
    required num montant,
    required String methode,
    String? planId,
  }) async {
    final uid = currentUser?.uid;
    if (uid == null) throw Exception('Non connecté.');

    final id = FirebaseFirestore.instance
        .collection(_storesCollection)
        .doc(uid)
        .collection('payment_requests')
        .doc()
        .id;

    final recuUrl = await CloudinaryService.uploadImage(
      recu,
      folder: 'payment_proofs/$uid',
    );

    final payment = PaymentRequest(
      id: id,
      storeId: uid,
      montant: montant,
      methode: methode,
      recuUrl: recuUrl,
      statut: 'en_attente',
      dateEnvoi: DateTime.now(),
    );

    await FirebaseFirestore.instance
        .collection(_storesCollection)
        .doc(uid)
        .collection('payment_requests')
        .doc(id)
        .set({...payment.toMap(), if (planId != null) 'planId': planId});

    // Le magasin passe en "paiement en attente" : il perd l'accès aux
    // demandes dès la fin de son essai/abonnement en cours, jusqu'à
    // validation manuelle du paiement.
    await FirebaseFirestore.instance
        .collection(_storesCollection)
        .doc(uid)
        .update({'subscriptionStatus': SubscriptionStatus.enAttente});
  }

  /// Profil du magasin connecté, en direct (reflète l'activation
  /// automatique de l'abonnement dès que le webhook Chargily confirme le
  /// paiement, sans avoir à recharger l'écran).
  static Stream<StoreProfile?> myProfileStream() {
    final uid = currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return FirebaseFirestore.instance
        .collection(_storesCollection)
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists ? StoreProfile.fromDoc(doc) : null);
  }

  /// Historique des demandes de paiement du magasin connecté.
  static Stream<List<PaymentRequest>> myPaymentRequests() {
    final uid = currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return FirebaseFirestore.instance
        .collection(_storesCollection)
        .doc(uid)
        .collection('payment_requests')
        .orderBy('dateEnvoi', descending: true)
        .snapshots()
        .map((s) => s.docs.map(PaymentRequest.fromDoc).toList());
  }
}
