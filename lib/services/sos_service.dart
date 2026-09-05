import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'location_service.dart';
import 'sos_models.dart';
import 'store_service.dart';

/// Bouton SOS : diffusion d'une alerte de panne aux dépanneuses de la
/// même wilaya, et espace dépanneuse (compte séparé, accès caché — un
/// appui long sur le bouton SOS, pas de menu visible).
///
/// Même mécanisme d'authentification téléphone + mot de passe que
/// [StoreService] (email technique "@vroumdep.local"), pour rester
/// gratuit (pas de SMS) et cohérent avec le reste de l'app.
class SosService {
  static const _alertsCollection = 'sos_alerts';
  static const _depanneusesCollection = 'depanneuses';
  static const _phoneAsIdKey = 'depanneuse_phone_as_id';

  // --- Côté utilisateur en panne (envoi de l'alerte) ---------------------

  /// Garantit une session Firebase (anonyme si besoin) et retourne
  /// l'identifiant à utiliser comme clientId — même logique que
  /// MarketplaceService.ensureSignedIn, réutilisée indépendamment ici
  /// pour que le bouton SOS marche même si l'utilisateur n'a jamais
  /// ouvert le portail acheteur.
  static Future<String> _ensureSignedIn() async {
    var user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      final cred = await FirebaseAuth.instance.signInAnonymously();
      user = cred.user;
    }
    return user!.uid;
  }

  /// Envoie une alerte de panne, position GPS incluse en best-effort
  /// (jamais bloquant si le GPS est indisponible/refusé). Le téléphone
  /// du client est requis : c'est le seul moyen pour la dépanneuse qui
  /// accepte de le rappeler (le compte SOS est anonyme, sans numéro
  /// Firebase Auth).
  static Future<String> sendAlert({
    required String wilaya,
    required String telephone,
  }) async {
    final numero = StoreService.normaliserNumeroLocal(telephone);
    if (numero == null) {
      throw Exception('Numéro invalide. Utilise le format 0556 65 32 20.');
    }
    final uid = await _ensureSignedIn();
    final position = await LocationService.getCurrentPosition();

    final id = FirebaseFirestore.instance.collection(_alertsCollection).doc().id;
    final alert = SosAlert(
      id: id,
      clientId: uid,
      clientTel: numero,
      wilaya: wilaya,
      latitude: position.latitude,
      longitude: position.longitude,
      statut: SosStatus.ouverte,
      dateCreation: DateTime.now(),
    );
    await FirebaseFirestore.instance
        .collection(_alertsCollection)
        .doc(id)
        .set(alert.toMap());
    return id;
  }

  /// Suit en direct le statut d'une alerte envoyée (pour afficher
  /// "En attente..." puis les coordonnées de la dépanneuse qui répond).
  static Stream<SosAlert?> watchAlert(String alertId) {
    return FirebaseFirestore.instance
        .collection(_alertsCollection)
        .doc(alertId)
        .snapshots()
        .map((doc) => doc.exists ? SosAlert.fromDoc(doc) : null);
  }

  static Future<void> cancelAlert(String alertId) async {
    await FirebaseFirestore.instance
        .collection(_alertsCollection)
        .doc(alertId)
        .update({'statut': SosStatus.annulee});
  }

  // --- Côté dépanneuse (auth téléphone + mot de passe) --------------------

  static User? get currentUser => FirebaseAuth.instance.currentUser;

  static String? _phoneAsId;

  // Le numéro en local (SharedPreferences) ne suffit pas à lui seul :
  // si la session Firebase Auth a été perdue entre-temps (déconnexion,
  // session expirée, un autre flux — ex: SOS anonyme — qui a remplacé
  // l'utilisateur courant), l'app pensait quand même être "connectée"
  // et tentait des lectures/écritures Firestore qui échouaient alors
  // en permission-denied. On exige donc aussi une session Firebase Auth
  // active pour considérer la dépanneuse comme connectée.
  static bool get isDepanneuseLoggedIn =>
      _phoneAsId != null &&
      _phoneAsId!.isNotEmpty &&
      FirebaseAuth.instance.currentUser != null;

  static Future<void> loadPhoneAsId() async {
    final prefs = await SharedPreferences.getInstance();
    _phoneAsId = prefs.getString(_phoneAsIdKey);
  }

  static Future<void> _savePhoneAsId(String numero) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_phoneAsIdKey, numero);
    _phoneAsId = numero;
  }

  static String? get currentDepanneuseDocId =>
      isDepanneuseLoggedIn ? _phoneAsId : null;

  static String _emailTechniqueDepuisNumero(String numeroLocal) =>
      '$numeroLocal@vroumdep.local';

  /// Message affichable à l'utilisateur pour n'importe quelle erreur
  /// remontée par un appel Firestore/Auth côté dépanneuse — jamais le
  /// texte technique brut (ex: "[cloud_firestore/permission-denied] ...").
  static String friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('permission-denied')) {
      return 'Session expirée ou non autorisée. Reconnecte-toi et réessaie.';
    }
    if (s.contains('network-request-failed') || s.contains('unavailable')) {
      return 'Pas de connexion internet. Vérifie ton réseau et réessaie.';
    }
    return 'Une erreur est survenue. Réessaie dans un instant.';
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
      case 'network-request-failed':
        return 'Pas de connexion internet. Vérifie ton réseau et réessaie.';
      default:
        return e.message ?? 'Erreur de connexion.';
    }
  }

  /// Crée un compte dépanneuse : `actif: false` jusqu'à validation
  /// manuelle par l'admin (même logique que les magasins).
  static Future<void> signUp({
    required String telephone,
    required String password,
    required String nom,
    required String wilaya,
  }) async {
    final numero = StoreService.normaliserNumeroLocal(telephone);
    if (numero == null) {
      throw Exception('Numéro invalide. Utilise le format 0556 65 32 20.');
    }
    try {
      final email = _emailTechniqueDepuisNumero(numero);
      final cred = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      final position = await LocationService.getCurrentPosition();
      final profile = DepanneuseProfile(
        uid: numero,
        nom: nom,
        tel: numero,
        wilaya: wilaya,
        actif: false,
        latitude: position.latitude,
        longitude: position.longitude,
      );
      await FirebaseFirestore.instance
          .collection(_depanneusesCollection)
          .doc(numero)
          .set(profile.toMap());

      await _savePhoneAsId(numero);
      await cred.user?.updateDisplayName(nom);
    } on FirebaseAuthException catch (e) {
      throw Exception(_messageErreurAuth(e));
    }
  }

  static Future<void> signIn({
    required String telephone,
    required String password,
  }) async {
    final numero = StoreService.normaliserNumeroLocal(telephone);
    if (numero == null) {
      throw Exception('Numéro invalide. Utilise le format 0556 65 32 20.');
    }
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailTechniqueDepuisNumero(numero),
        password: password,
      );
      await _savePhoneAsId(numero);
    } on FirebaseAuthException catch (e) {
      throw Exception(_messageErreurAuth(e));
    }
  }

  static Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_phoneAsIdKey);
    _phoneAsId = null;
    await FirebaseAuth.instance.signOut();
  }

  static Future<DepanneuseProfile?> myProfile() async {
    final docId = currentDepanneuseDocId;
    if (docId == null) return null;
    final doc = await FirebaseFirestore.instance
        .collection(_depanneusesCollection)
        .doc(docId)
        .get();
    if (!doc.exists) return null;
    return DepanneuseProfile.fromDoc(doc);
  }

  static Stream<DepanneuseProfile?> myProfileStream() {
    final docId = currentDepanneuseDocId;
    if (docId == null) return const Stream.empty();
    return FirebaseFirestore.instance
        .collection(_depanneusesCollection)
        .doc(docId)
        .snapshots()
        .map((doc) => doc.exists ? DepanneuseProfile.fromDoc(doc) : null);
  }

  /// Alertes ouvertes de la wilaya de la dépanneuse connectée, les plus
  /// récentes d'abord. Pas de orderBy Firestore (même raison qu'ailleurs
  /// dans l'app : évite de dépendre d'un index composite absent) — tri
  /// fait côté client.
  static Stream<List<SosAlert>> openAlertsForMyWilaya(String wilaya) {
    return FirebaseFirestore.instance
        .collection(_alertsCollection)
        .where('statut', isEqualTo: SosStatus.ouverte)
        .where('wilaya', isEqualTo: wilaya)
        .snapshots()
        .map((s) {
      final alertes = s.docs.map(SosAlert.fromDoc).toList();
      alertes.sort((a, b) => b.dateCreation.compareTo(a.dateCreation));
      return alertes;
    });
  }

  /// La dépanneuse accepte une alerte : elle devient visible/prioritaire
  /// pour cette dépanneuse côté utilisateur (numéro affiché).
  static Future<void> acceptAlert(String alertId) async {
    final profile = await myProfile();
    if (profile == null) throw Exception('Profil dépanneuse introuvable.');
    await FirebaseFirestore.instance
        .collection(_alertsCollection)
        .doc(alertId)
        .update({
      'statut': SosStatus.acceptee,
      'acceptedByDepanneuseId': profile.uid,
      'acceptedByDepanneuseNom': profile.nom,
      'acceptedByDepanneuseTel': profile.tel,
      'dateAcceptation': FieldValue.serverTimestamp(),
    });
  }

  /// La dépanneuse confirme qu'elle est arrivée sur place, une fois sur
  /// les lieux de la panne.
  static Future<void> confirmArrival(String alertId) async {
    await FirebaseFirestore.instance
        .collection(_alertsCollection)
        .doc(alertId)
        .update({
      'statut': SosStatus.arrivee,
      'dateArrivee': FieldValue.serverTimestamp(),
    });
  }

  /// Alertes déjà acceptées (ou terminées) par la dépanneuse connectée.
  /// Tri côté client, plus récentes d'abord.
  static Stream<List<SosAlert>> myAcceptedAlertsStream() {
    final docId = currentDepanneuseDocId;
    if (docId == null) return const Stream.empty();
    return FirebaseFirestore.instance
        .collection(_alertsCollection)
        .where('acceptedByDepanneuseId', isEqualTo: docId)
        .snapshots()
        .map((s) {
      final alertes = s.docs.map(SosAlert.fromDoc).toList();
      alertes.sort((a, b) {
        final da = a.dateAcceptation ?? a.dateCreation;
        final db = b.dateAcceptation ?? b.dateCreation;
        return db.compareTo(da);
      });
      return alertes;
    });
  }

  static Future<void> saveFcmToken() async {

    final docId = currentDepanneuseDocId;
    if (docId == null) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await FirebaseFirestore.instance
          .collection(_depanneusesCollection)
          .doc(docId)
          .update({'fcmToken': token});
    } catch (_) {
      // Pas de push si le token est indisponible : la dépanneuse peut
      // toujours ouvrir l'app pour voir les alertes.
    }
  }
}
