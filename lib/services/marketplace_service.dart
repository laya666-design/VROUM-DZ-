import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'cloudinary_service.dart';
import 'marketplace_models.dart';
import 'part_categories.dart';
import 'store_service.dart';

/// Marketplace pièces — côté demandeur (client / acheteur).
///
/// Connexion par numéro de téléphone + mot de passe (même principe que
/// [StoreService] côté magasin) : le numéro normalisé est converti en un
/// email technique invisible ("0556653220@vroumclient.local") pour
/// utiliser Firebase Auth email/mot de passe, sans SMS à payer.
/// La session persiste grâce à SharedPreferences : retour en arrière
/// ne déconnecte pas.
class MarketplaceService {
  static const _requestsCollection = 'part_requests';
  static const _phoneAsIdKey = 'buyer_phone_as_id';

  static User? get currentUser => FirebaseAuth.instance.currentUser;

  /// Numéro sauvegardé comme identifiant.
  static String? _phoneAsId;

  /// Connecté avec un numéro enregistré.
  static bool get isPhoneLoggedIn =>
      _phoneAsId != null && _phoneAsId!.isNotEmpty;

  /// Une session existe (numéro-as-id ou Firebase anonyme).
  static bool get hasSession =>
      (_phoneAsId != null && _phoneAsId!.isNotEmpty) || currentUser != null;

  /// Charge le numéro sauvegardé (à appeler avant de décider de la navigation).
  static Future<void> loadPhoneAsId() async {
    final prefs = await SharedPreferences.getInstance();
    _phoneAsId = prefs.getString(_phoneAsIdKey);
  }

  // --- Authentification téléphone + mot de passe (méthode principale) ---
  // Même mécanisme que StoreService côté magasin : le numéro devient un
  // email technique "@vroumclient.local" pour Firebase Auth. Comme ce
  // domaine n'existe pas réellement, sendPasswordResetEmail ne peut pas
  // fonctionner pour ces comptes — mot de passe oublié = contacter le
  // support pour une réinitialisation manuelle depuis la console Firebase.

  static String _emailTechniqueDepuisNumero(String numeroLocal) =>
      '$numeroLocal@vroumclient.local';

  /// Email actuellement utilisé pour l'authentification Firebase de ce
  /// numéro : l'email technique par défaut, sauf si une récupération de
  /// mot de passe a déjà eu lieu (voir StoreService, même mécanisme —
  /// champ `authEmail` dans `buyer_accounts/<numero>`).
  static Future<String> _authEmailPourNumero(String numero) async {
    final technique = _emailTechniqueDepuisNumero(numero);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('buyer_accounts')
          .doc(numero)
          .get();
      final authEmail = doc.data()?['authEmail'] as String?;
      return (authEmail != null && authEmail.isNotEmpty) ? authEmail : technique;
    } catch (_) {
      return technique;
    }
  }

  static String _messageErreurAuth(FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-password':
      case 'invalid-credential':
        return 'Numéro ou mot de passe incorrect.';
      case 'user-not-found':
        return 'Aucun compte avec ce numéro. Crée un compte d\'abord.';
      case 'email-already-in-use':
        return 'Un compte existe déjà avec ce numéro. Connecte-toi plutôt.';
      case 'weak-password':
        return 'Mot de passe trop court (6 caractères minimum).';
      case 'too-many-requests':
        return 'Trop de tentatives. Réessaie plus tard.';
      case 'network-request-failed':
        return 'Pas de connexion internet. Vérifie ton réseau et réessaie.';
      default:
        return e.message ?? 'Erreur de connexion.';
    }
  }

  static Future<void> _savePhoneAsId(String numero) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_phoneAsIdKey, numero);
    _phoneAsId = numero;
  }

  /// Crée un compte acheteur avec numéro + mot de passe.
  static Future<void> signUpWithPhonePassword({
    required String telephone,
    required String password,
  }) async {
    final numero = StoreService.normaliserNumeroLocal(telephone);
    if (numero == null) {
      throw Exception('Numéro invalide. Utilise le format 0556 65 32 20.');
    }
    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailTechniqueDepuisNumero(numero),
        password: password,
      );
      await _savePhoneAsId(numero);
    } on FirebaseAuthException catch (e) {
      throw Exception(_messageErreurAuth(e));
    }
  }

  /// Connexion acheteur avec numéro + mot de passe.
  static Future<void> signInWithPhonePassword({
    required String telephone,
    required String password,
  }) async {
    final numero = StoreService.normaliserNumeroLocal(telephone);
    if (numero == null) {
      throw Exception('Numéro invalide. Utilise le format 0556 65 32 20.');
    }
    try {
      final email = await _authEmailPourNumero(numero);
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      await _savePhoneAsId(numero);
    } on FirebaseAuthException catch (e) {
      throw Exception(_messageErreurAuth(e));
    }
  }

  /// Garantit une session Firebase et retourne l'identifiant des demandes
  /// (numéro prioritaire, sinon uid).
  static Future<String> ensureSignedIn() async {
    // Recharge au cas où (ex: après hot-reload).
    if (_phoneAsId == null) {
      await loadPhoneAsId();
    }
    var user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      final cred = await FirebaseAuth.instance.signInAnonymously();
      user = cred.user;
    }
    if (_phoneAsId != null && _phoneAsId!.isNotEmpty) {
      return _phoneAsId!;
    }
    return user!.uid;
  }

  /// Identifiant des demandes : numéro de téléphone prioritaire.
  static String? get clientId {
    if (_phoneAsId != null && _phoneAsId!.isNotEmpty) return _phoneAsId;
    return FirebaseAuth.instance.currentUser?.uid;
  }


  /// Connexion Google — pour acheteur (conducteur)
  /// Utilise le même serverClientId que côté magasin (projet Firebase unique)
  
  static Future<void> signInWithGoogle() async {
    final GoogleSignIn googleSignIn = GoogleSignIn.instance;
    await googleSignIn.initialize(
      serverClientId: '994131871524-dbn081ucefsf4vi4v0jl1m4gc11di90p.apps.googleusercontent.com',
    );
    final GoogleSignInAccount account = await googleSignIn.authenticate();
    final String? idToken = account.authentication.idToken;
    if (idToken == null) throw Exception('ID token manquant.');
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    await FirebaseAuth.instance.signInWithCredential(credential);
  }



  static Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_phoneAsIdKey);
    _phoneAsId = null;
    await FirebaseAuth.instance.signOut();
  }

  // --- Authentification par e-mail (alternative au téléphone) ---
  // Contrairement au flux téléphone, ceci utilise un vrai email : la
  // réinitialisation de mot de passe (sendPasswordResetEmail) fonctionne
  // normalement.

  /// Crée un compte acheteur avec email + mot de passe.
  static Future<void> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  /// Connexion acheteur avec email + mot de passe.
  static Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  /// Envoie l'email Firebase de réinitialisation de mot de passe.
  static Future<void> sendPasswordResetEmail(String email) async {
    await FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
  }

  /// Demande la réinitialisation du mot de passe d'un compte téléphone
  /// (même mécanisme que StoreService.demanderResetParEmail côté
  /// magasin — 100% Firebase, aucun service tiers) : associe/vérifie
  /// [email] comme email réel du compte, puis déclenche l'envoi natif.
  static Future<void> demanderResetParEmail({
    required String telephone,
    required String email,
  }) async {
    final numero = StoreService.normaliserNumeroLocal(telephone);
    if (numero == null) {
      throw Exception('Numéro invalide. Utilise le format 0556 65 32 20.');
    }
    try {
      final callable = FirebaseFunctions.instance
          .httpsCallable('attacherEmailRecuperationTelephone');
      final result = await callable.call({
        'telephone': numero,
        'email': email.trim(),
        'type': 'buyer',
      });
      final emailReel = result.data?['email'] as String? ?? email.trim();
      await FirebaseAuth.instance.sendPasswordResetEmail(email: emailReel);
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'Envoi impossible.');
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message ?? 'Envoi impossible.');
    }
  }

  /// Diffuse une demande de pièce à tous les magasins actifs.
  static Future<String> broadcastRequest({
    required File photo,
    required String pieceNom,
    required String reference,
    required List<String> compatibilite,
    File? noteVocale,
  }) async {
    final uid = await ensureSignedIn();
    final id = FirebaseFirestore.instance.collection(_requestsCollection).doc().id;

    final photoUrl = await CloudinaryService.uploadImage(
      photo,
      folder: 'part_requests',
    );

    String? noteVocaleUrl;
    if (noteVocale != null) {
      try {
        noteVocaleUrl = await CloudinaryService.uploadAudio(
          noteVocale,
          folder: 'part_requests_audio',
        );
      } catch (_) {
        noteVocaleUrl = null;
      }
    }

    final categorie = detecterCategorie(pieceNom);

    final request = PartRequest(
      id: id,
      clientId: uid,
      pieceNom: pieceNom,
      reference: reference,
      compatibilite: compatibilite,
      photoUrl: photoUrl,
      noteVocaleUrl: noteVocaleUrl,
      categorie: categorie,
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
  static Stream<List<PartRequest>> myRequests() async* {
    final uid = await ensureSignedIn();
    yield* FirebaseFirestore.instance
        .collection(_requestsCollection)
        .where('clientId', isEqualTo: uid)
        // Pas de orderBy Firestore ici (même raison que côté magasin) :
        // where + orderBy sur des champs différents exige un index
        // composite ; sans lui la requête échoue et la liste reste vide.
        // Tri fait côté client.
        .snapshots()
        .map((s) {
      final demandes = s.docs.map(PartRequest.fromDoc).toList();
      demandes.sort((a, b) => b.dateCreation.compareTo(a.dateCreation));
      return demandes;
    });
  }

  /// Réponses des magasins pour une demande donnée.
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

  /// Suppression définitive d'une demande par l'acheteur
  /// (et de ses offres en sous-collection).
  static Future<void> deleteRequest(String requestId) async {
    final ref = FirebaseFirestore.instance
        .collection(_requestsCollection)
        .doc(requestId);
    final offers = await ref.collection('offers').get();
    final batch = FirebaseFirestore.instance.batch();
    for (final o in offers.docs) {
      batch.delete(o.reference);
    }
    batch.delete(ref);
    await batch.commit();
  }

  /// Suppression multiple côté acheteur.
  static Future<void> deleteRequests(List<String> requestIds) async {
    for (final id in requestIds) {
      await deleteRequest(id);
    }
  }
}
