import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'cloudinary_service.dart';
import 'location_service.dart';
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
  static const _phoneAsIdKey = 'store_phone_as_id';

  static User? get currentUser => FirebaseAuth.instance.currentUser;
  static bool get isLoggedIn => currentUser != null;

  /// À appeler avant tout test de session au lancement d'un écran racine
  /// (ex: MagasinShellScreen). Sans ça, juste après un redémarrage de
  /// l'app (ex: l'OS a tué le process en arrière-plan puis l'utilisateur
  /// revient dessus), `currentUser` peut valoir null pendant les
  /// quelques millisecondes où Firebase Auth restaure encore la session
  /// persistée depuis le disque — ce qui provoquait une déconnexion
  /// visuelle (retour à l'écran de connexion) alors que la session
  /// existait bel et bien. authStateChanges().first attend la première
  /// valeur réelle (connecté ou non) avant de conclure.
  static Future<void> waitForAuthReady() async {
    await FirebaseAuth.instance.authStateChanges().first;
  }

  /// Numéro sauvegardé localement comme identifiant du magasin connecté
  /// — indépendant de l'email Firebase Auth actuel du compte, qui peut
  /// changer (voir [demanderResetParEmail] : l'email technique
  /// "@elbouni.local" est remplacé par un vrai email dès la première
  /// récupération de mot de passe).
  static String? _phoneAsId;

  /// Charge le numéro sauvegardé (à appeler avant de décider de la
  /// navigation — voir PartsPortalScreen).
  static Future<void> loadPhoneAsId() async {
    final prefs = await SharedPreferences.getInstance();
    _phoneAsId = prefs.getString(_phoneAsIdKey);
  }

  static Future<void> _savePhoneAsId(String numero) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_phoneAsIdKey, numero);
    _phoneAsId = numero;
  }

  /// Identifiant du document Firestore du magasin connecté.
  ///
  /// Pour les comptes créés via [signUpWithPhonePassword], c'est le
  /// numéro de téléphone lui-même (sauvegardé localement à la connexion,
  /// voir [_phoneAsId]) : le document est stocké à `stores/0556653220`,
  /// lisible directement dans la console Firestore, et ce quel que soit
  /// l'email Firebase Auth actuel du compte (fake ou réel après une
  /// récupération de mot de passe). Pour les anciens comptes (Google,
  /// email classique) créés avant ce changement, on retombe sur l'UID
  /// Firebase Auth (leur document existe déjà sous cette clé).
  static String? get currentStoreDocId {
    final user = currentUser;
    if (user == null) return null;
    if (_phoneAsId != null && _phoneAsId!.isNotEmpty) return _phoneAsId;
    final email = user.email;
    if (email != null && email.endsWith('@elbouni.local')) {
      return email.split('@').first;
    }
    return user.uid;
  }

  // --- Authentification téléphone + mot de passe (méthode principale) ---
  // Le magasin tape son numéro + un mot de passe qu'il choisit. Comme
  // Firebase Auth n'a pas nativement de "email/password mais avec un
  // numéro comme identifiant", on convertit le numéro normalisé en un
  // email technique invisible pour l'utilisateur : "0556653220" devient
  // "0556653220@elbouni.local". Ce domaine n'existe pas réellement — il
  // ne sert qu'à fabriquer un identifiant unique valide pour Firebase.
  // Avantage : pas de SMS à payer, connexion instantanée, sécurisé par
  // un vrai mot de passe choisi par le magasin.
  //
  // LIMITE IMPORTANTE : comme "@elbouni.local" n'est pas un vrai domaine,
  // `sendPasswordResetEmail` ne peut pas fonctionner directement pour ces
  // comptes (aucun email ne peut être livré). Voir [demanderResetParEmail]
  // ci-dessous : à la première demande, la Cloud Function
  // `attacherEmailRecuperationTelephone` bascule l'email réel du compte
  // vers celui fourni par le magasin — ensuite Firebase peut envoyer
  // nativement un vrai email de réinitialisation (aucun service tiers).

  /// Demande la réinitialisation du mot de passe d'un compte téléphone :
  /// associe (première fois) ou vérifie (fois suivantes) [email] comme
  /// email réel du compte, puis déclenche l'envoi natif Firebase.
  static Future<void> demanderResetParEmail({
    required String telephone,
    required String email,
  }) async {
    final numero = normaliserNumeroLocal(telephone);
    if (numero == null) {
      throw Exception('Numéro invalide. Utilise le format 0556 65 32 20.');
    }
    try {
      final callable = FirebaseFunctions.instance
          .httpsCallable('attacherEmailRecuperationTelephone');
      final result = await callable.call({
        'telephone': numero,
        'email': email.trim(),
        'type': 'store',
      });
      final emailReel = result.data?['email'] as String? ?? email.trim();
      // Envoi natif Firebase — fonctionne car l'email du compte est
      // désormais un vrai email (basculé par la Cloud Function ci-dessus).
      await FirebaseAuth.instance.sendPasswordResetEmail(email: emailReel);
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'Envoi impossible.');
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message ?? 'Envoi impossible.');
    }
  }

  /// Normalise une saisie de numéro algérien vers le format local à 10
  /// chiffres commençant par 0 (ex: "0556653220"), quel que soit le
  /// format saisi (+213..., 213..., chiffres arabes...). Retourne null
  /// si la saisie n'est pas un numéro algérien valide.
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

  /// Email technique invisible pour l'utilisateur, dérivé du numéro.
  static String _emailTechniqueDepuisNumero(String numeroLocal) =>
      '$numeroLocal@elbouni.local';

  /// Email actuellement utilisé pour l'authentification Firebase de ce
  /// numéro : l'email technique par défaut, sauf si une récupération de
  /// mot de passe a déjà eu lieu — auquel cas c'est le vrai email fourni
  /// à ce moment-là (champ `authEmail`, mis à jour par
  /// `attacherEmailRecuperationTelephone`).
  static Future<String> _authEmailPourNumero(String numero) async {
    final technique = _emailTechniqueDepuisNumero(numero);
    try {
      final doc = await FirebaseFirestore.instance
          .collection(_storesCollection)
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

  /// Crée un compte magasin avec numéro + mot de passe. `actif: false`
  /// jusqu'à validation manuelle, comme pour les autres méthodes
  /// d'inscription. L'écran appelant doit ensuite rediriger vers
  /// [StoreCompleteProfileScreen] (nom + adresse du magasin).
  static Future<void> signUpWithPhonePassword({
    required String telephone,
    required String password,
  }) async {
    final numero = normaliserNumeroLocal(telephone);
    if (numero == null) {
      throw Exception(
          'Numéro invalide. Utilise le format 0556 65 32 20.');
    }
    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailTechniqueDepuisNumero(numero),
        password: password,
      );
      // Position GPS "best effort" : si le magasin refuse la permission ou
      // que le GPS est coupé, l'inscription continue quand même (position
      // ajoutable plus tard depuis le dashboard via updateLocation()).
      final position = await LocationService.getCurrentPosition();
      final profile = StoreProfile(
        uid: numero,
        nom: '',
        tel: numero,
        adresse: '',
        actif: false,
        subscriptionStatus: SubscriptionStatus.essai,
        trialEndDate:
            DateTime.now().add(const Duration(days: kEssaiGratuitJours)),
        latitude: position.latitude,
        longitude: position.longitude,
      );
      // Le document est stocké sous le numéro de téléphone (et non l'UID
      // Firebase Auth généré par cred.user!.uid), pour rester lisible et
      // identifiable directement dans la console Firestore.
      await FirebaseFirestore.instance
          .collection(_storesCollection)
          .doc(numero)
          .set(profile.toMap());
      await _saveRememberMe(true);
      await _savePhoneAsId(numero);
      await _registerFcmToken(numero);
    } on FirebaseAuthException catch (e) {
      throw Exception(_messageErreurAuth(e));
    }
  }

  /// Connexion magasin avec numéro + mot de passe.
  static Future<void> signInWithPhonePassword({
    required String telephone,
    required String password,
    bool rememberMe = true,
  }) async {
    final numero = normaliserNumeroLocal(telephone);
    if (numero == null) {
      throw Exception(
          'Numéro invalide. Utilise le format 0556 65 32 20.');
    }
    try {
      final email = await _authEmailPourNumero(numero);
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      await _saveRememberMe(rememberMe);
      await _savePhoneAsId(numero);
      await _registerFcmToken(numero);
    } on FirebaseAuthException catch (e) {
      throw Exception(_messageErreurAuth(e));
    }
  }

  // --- Ancienne authentification téléphone/SMS (conservée mais plus
  // utilisée par l'écran de connexion — voir signUpWithPhonePassword /
  // signInWithPhonePassword ci-dessus) ---

  /// Lance l'envoi du code SMS vers [phoneNumber] (format international,
  /// ex: "+213556653220"). [onCodeSent] reçoit l'id de vérification à
  /// fournir ensuite à [confirmPhoneCode]. [onAutoVerified] est appelé si
  /// Android confirme le numéro tout seul (sans saisie du code) — rare
  /// mais possible sur certains appareils ; son paramètre indique si un
  /// nouveau profil vient d'être créé (même sens que le retour de
  /// [confirmPhoneCode]).
  static Future<void> startPhoneVerification({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(String message) onError,
    required void Function(bool isNouveau) onAutoVerified,
  }) async {
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) async {
        try {
          await FirebaseAuth.instance.signInWithCredential(credential);
          final isNouveau = await _ensureProfileAfterPhoneAuth();
          final uid = currentUser?.uid;
          if (uid != null) await _registerFcmToken(uid);
          onAutoVerified(isNouveau);
        } catch (e) {
          onError('$e');
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        onError(_messageErreurTelephone(e));
      },
      codeSent: (String verificationId, int? resendToken) {
        onCodeSent(verificationId);
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        onCodeSent(verificationId);
      },
    );
  }

  static String _messageErreurTelephone(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-phone-number':
        return 'Numéro invalide. Vérifie le format (ex: 0556 65 32 20).';
      case 'too-many-requests':
        return 'Trop de tentatives. Réessaie plus tard, ou utilise l\'email / continue avec le numéro.';
      case 'quota-exceeded':
        return 'Service temporairement indisponible. '
            'Utilise la connexion par email ou continue avec le numéro.';
      default:
        return e.message ?? 'Erreur d\'envoi du code.';
    }
  }

  /// Valide le code reçu et connecte (ou crée) le compte magasin.
  /// Retourne true si c'est un nouveau compte : l'écran appelant doit
  /// alors demander nom + adresse avant d'aller au tableau de bord.
  static Future<bool> confirmPhoneCode({
    required String verificationId,
    required String smsCode,
    bool rememberMe = true,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    await FirebaseAuth.instance.signInWithCredential(credential);
    await _saveRememberMe(rememberMe);
    final isNouveau = await _ensureProfileAfterPhoneAuth();
    final uid = currentUser?.uid;
    if (uid != null) await _registerFcmToken(uid);
    return isNouveau;
  }

  /// Crée un profil minimal si c'est la première connexion par téléphone
  /// (comme pour Google) : `actif: false` en attendant validation
  /// manuelle. Retourne true si un profil a été créé (nouveau compte).
  static Future<bool> _ensureProfileAfterPhoneAuth() async {
    final uid = currentUser?.uid;
    if (uid == null) return false;
    final docRef =
        FirebaseFirestore.instance.collection(_storesCollection).doc(uid);
    final doc = await docRef.get();
    if (doc.exists) return false;
    final profile = StoreProfile(
      uid: uid,
      nom: '',
      tel: currentUser?.phoneNumber ?? '',
      adresse: '',
      actif: false,
      subscriptionStatus: SubscriptionStatus.essai,
      trialEndDate:
          DateTime.now().add(const Duration(days: kEssaiGratuitJours)),
    );
    await docRef.set(profile.toMap());
    return true;
  }

  /// Complète le profil (nom, adresse, catégories) juste après une première
  /// connexion par téléphone — le compte existe déjà (créé par
  /// [_ensureProfileAfterPhoneAuth]), on ne fait que mettre à jour.
  /// [categories] doit contenir au moins une entrée. Si « autre » est
  /// présent, [categorieAutre] est obligatoire.
  static Future<void> completerProfilApresTelephone({
    required String nom,
    required String adresse,
    required List<String> categories,
    String? categorieAutre,
  }) async {
    final docId = currentStoreDocId;
    if (docId == null) throw Exception('Non connecté.');
    if (categories.isEmpty) {
      throw Exception('Choisis au moins une catégorie de pièces.');
    }
    if (categories.contains('autre') &&
        (categorieAutre == null || categorieAutre.trim().isEmpty)) {
      throw Exception('Précise ta spécialité dans le champ « Autre ».');
    }

    final update = <String, dynamic>{
      'nom': nom,
      'adresse': adresse,
      'categories': categories,
      if (categorieAutre != null && categorieAutre.trim().isNotEmpty)
        'categorieAutre': categorieAutre.trim(),
    };

    // Si la position n'a pas pu être capturée à la création du compte
    // (permission pas encore accordée à ce moment-là), on retente ici :
    // c'est la dernière étape avant le dashboard, donc la dernière
    // occasion simple de la demander pendant l'inscription.
    final doc = await FirebaseFirestore.instance
        .collection(_storesCollection)
        .doc(docId)
        .get();
    final dejaGeolocalise =
        (doc.data()?['latitude'] != null) && (doc.data()?['longitude'] != null);
    if (!dejaGeolocalise) {
      final position = await LocationService.getCurrentPosition();
      if (position.aUnePosition) {
        update['latitude'] = position.latitude;
        update['longitude'] = position.longitude;
      }
    }

    await FirebaseFirestore.instance
        .collection(_storesCollection)
        .doc(docId)
        .update(update);
  }

  /// Met à jour uniquement les catégories du magasin connecté
  /// (paramètres / profil).
  static Future<void> updateCategories({
    required List<String> categories,
    String? categorieAutre,
  }) async {
    final docId = currentStoreDocId;
    if (docId == null) throw Exception('Non connecté.');
    if (categories.isEmpty) {
      throw Exception('Choisis au moins une catégorie de pièces.');
    }
    if (categories.contains('autre') &&
        (categorieAutre == null || categorieAutre.trim().isEmpty)) {
      throw Exception('Précise ta spécialité dans le champ « Autre ».');
    }
    await FirebaseFirestore.instance.collection(_storesCollection).doc(docId).update({
      'categories': categories,
      'categorieAutre': (categorieAutre != null && categorieAutre.trim().isNotEmpty)
          ? categorieAutre.trim()
          : FieldValue.delete(),
    });
  }

  /// (Re)géolocalise le magasin connecté (bouton "Mettre à jour ma
  /// position" dans le dashboard). Lance une exception avec un message
  /// lisible si la position n'a pas pu être obtenue, pour affichage direct
  /// à l'utilisateur (permission refusée, GPS coupé...).
  static Future<void> updateLocation() async {
    final docId = currentStoreDocId;
    if (docId == null) throw Exception('Non connecté.');
    final position = await LocationService.getCurrentPosition();
    if (!position.aUnePosition) {
      throw Exception(position.erreur ?? 'Position indisponible.');
    }
    await FirebaseFirestore.instance
        .collection(_storesCollection)
        .doc(docId)
        .update({
      'latitude': position.latitude,
      'longitude': position.longitude,
    });
  }

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
    final position = await LocationService.getCurrentPosition();
    final profile = StoreProfile(
      uid: cred.user!.uid,
      nom: nom,
      tel: tel,
      adresse: adresse,
      actif: false,
      subscriptionStatus: SubscriptionStatus.essai,
      trialEndDate:
          DateTime.now().add(const Duration(days: kEssaiGratuitJours)),
      latitude: position.latitude,
      longitude: position.longitude,
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
    final GoogleSignIn googleSignIn = GoogleSignIn.instance;
    await googleSignIn.initialize(
      serverClientId: '994131871524-dbn081ucefsf4vi4v0jl1m4gc11di90p.apps.googleusercontent.com',
    );
    try {
      final GoogleSignInAccount account = await googleSignIn.authenticate();
      final String? idToken = account.authentication.idToken;
      if (idToken == null) {
        throw Exception('ID token Google manquant.');
      }
      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final userCred = await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCred.user;
      if (user == null) throw Exception('Connexion Google impossible.');
      await _saveRememberMe(rememberMe);
      final docRef = FirebaseFirestore.instance.collection(_storesCollection).doc(user.uid);
      final doc = await docRef.get();
      if (!doc.exists) {
        await docRef.set({
          'email': user.email,
          'nom': user.displayName ?? 'Magasin',
          'tel': '',
          'adresse': '',
          'actif': false,
          'createdAt': FieldValue.serverTimestamp(),
          'uid': user.uid,
        });
      }
      if (rememberMe) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_phoneAsIdKey, user.uid);
        _phoneAsId = user.uid;
      }
      await _saveFcmToken();
    } catch (e) {
      if (e.toString().contains('canceled') || e.toString().contains('annulée')) {
        throw Exception('Connexion Google annulée.');
      }
      rethrow;
    }
  }



  static Future<void> signOut() => FirebaseAuth.instance.signOut();

  static Future<void> _registerFcmToken(String storeDocId) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await FirebaseFirestore.instance
          .collection(_storesCollection)
          .doc(storeDocId)
          .update({'fcmToken': token});
    } catch (_) {
      // Permission notifications refusée ou token indisponible : le
      // magasin reste utilisable, juste sans push (il peut toujours
      // ouvrir l'app pour voir les demandes).
    }
  }

  static Future<StoreProfile?> myProfile() async {
    final docId = currentStoreDocId;
    if (docId == null) return null;
    final doc = await FirebaseFirestore.instance
        .collection(_storesCollection)
        .doc(docId)
        .get();
    if (!doc.exists) return null;
    return StoreProfile.fromDoc(doc);
  }

  /// Demandes ouvertes (brutes), les plus récentes d'abord.
  /// Le filtrage par catégories se fait côté UI via [filtrerParCategories],
  /// pour ne pas recréer le stream Firestore à chaque changement de profil.
  static Stream<List<PartRequest>> openRequests() {
    return FirebaseFirestore.instance
        .collection('part_requests')
        .where('statut', isEqualTo: 'open')
        // Pas de orderBy ici : évite de dépendre d'un index composite
        // Firestore (statut + dateCreation) qui, s'il manque, fait échouer
        // la requête silencieusement côté magasin (liste vide). Tri fait
        // côté client juste après.
        .snapshots()
        .map((s) {
      final demandes = s.docs.map(PartRequest.fromDoc).toList();
      demandes.sort((a, b) => b.dateCreation.compareTo(a.dateCreation));
      return demandes;
    });
  }

  /// Ne garde que les demandes dont la catégorie est dans [storeCategories].
  /// Si [storeCategories] est vide → liste vide (le magasin doit renseigner
  /// ses spécialités à l'inscription / dans les paramètres).
  static List<PartRequest> filtrerParCategories(
    List<PartRequest> demandes,
    List<String> storeCategories,
  ) {
    if (storeCategories.isEmpty) return const [];
    final set = storeCategories.toSet();
    return demandes.where((d) => set.contains(d.categorie)).toList();
  }

  /// IDs des demandes que CE magasin a choisi de masquer localement
  /// (ne touche jamais aux données de l'acheteur).
  static const _hiddenRequestsKey = 'store_hidden_request_ids';

  static Future<Set<String>> hiddenRequestIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_hiddenRequestsKey) ?? [];
    return list.toSet();
  }

  /// Masque une ou plusieurs demandes côté magasin uniquement.
  static Future<void> hideRequests(List<String> requestIds) async {
    if (requestIds.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_hiddenRequestsKey) ?? [];
    final merged = {...current, ...requestIds}.toList();
    await prefs.setStringList(_hiddenRequestsKey, merged);
  }

  /// IDs des demandes déjà consultées par ce magasin (pour le badge non-lu).
  static const _seenRequestsKey = 'store_seen_request_ids';

  static Future<Set<String>> seenRequestIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_seenRequestsKey) ?? [];
    return list.toSet();
  }

  /// Marque une ou plusieurs demandes comme consultées (badge diminue).
  static Future<void> markRequestsSeen(List<String> requestIds) async {
    if (requestIds.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_seenRequestsKey) ?? [];
    final merged = {...current, ...requestIds}.toList();
    await prefs.setStringList(_seenRequestsKey, merged);
  }

  /// Le magasin répond à une demande avec un prix.
  /// [noteVocale] optionnelle : fichier audio local à uploader (même
  /// logique que la note vocale côté acheteur).
  static Future<void> respondToRequest({
    required String requestId,
    required num prix,
    required String stock,
    required String message,
    File? noteVocale,
  }) async {
    final profile = await myProfile();
    if (profile == null) {
      throw Exception('Profil magasin introuvable.');
    }

    String? noteVocaleUrl;
    if (noteVocale != null) {
      noteVocaleUrl = await CloudinaryService.uploadAudio(
        noteVocale,
        folder: 'offers_notes/${profile.uid}',
      );
    }

    final offer = PartOffer(
      id: '',
      storeId: profile.uid,
      storeNom: profile.nom,
      storeTel: profile.tel,
      prix: prix,
      stock: stock,
      message: message,
      noteVocaleUrl: noteVocaleUrl,
      storeLat: profile.latitude,
      storeLng: profile.longitude,
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
    final docId = currentStoreDocId;
    if (docId == null) throw Exception('Non connecté.');

    final id = FirebaseFirestore.instance
        .collection(_storesCollection)
        .doc(docId)
        .collection('payment_requests')
        .doc()
        .id;

    final recuUrl = await CloudinaryService.uploadImage(
      recu,
      folder: 'payment_proofs/$docId',
    );

    final payment = PaymentRequest(
      id: id,
      storeId: docId,
      montant: montant,
      methode: methode,
      recuUrl: recuUrl,
      statut: 'en_attente',
      dateEnvoi: DateTime.now(),
    );

    await FirebaseFirestore.instance
        .collection(_storesCollection)
        .doc(docId)
        .collection('payment_requests')
        .doc(id)
        .set({...payment.toMap(), if (planId != null) 'planId': planId});

    // Le magasin passe en "paiement en attente" : il perd l'accès aux
    // demandes dès la fin de son essai/abonnement en cours, jusqu'à
    // validation manuelle du paiement.
    await FirebaseFirestore.instance
        .collection(_storesCollection)
        .doc(docId)
        .update({'subscriptionStatus': SubscriptionStatus.enAttente});
  }

  /// Profil du magasin connecté, en direct (reflète l'activation
  /// automatique de l'abonnement dès que le webhook Chargily confirme le
  /// paiement, sans avoir à recharger l'écran).
  static Stream<StoreProfile?> myProfileStream() {
    final docId = currentStoreDocId;
    if (docId == null) return const Stream.empty();
    return FirebaseFirestore.instance
        .collection(_storesCollection)
        .doc(docId)
        .snapshots()
        .map((doc) => doc.exists ? StoreProfile.fromDoc(doc) : null);
  }

  /// Historique des demandes de paiement du magasin connecté.
  static Stream<List<PaymentRequest>> myPaymentRequests() {
    final docId = currentStoreDocId;
    if (docId == null) return const Stream.empty();
    return FirebaseFirestore.instance
        .collection(_storesCollection)
        .doc(docId)
        .collection('payment_requests')
        .orderBy('dateEnvoi', descending: true)
        .snapshots()
        .map((s) => s.docs.map(PaymentRequest.fromDoc).toList());
  }
}
