import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Point UNIQUE pour Google Sign-In dans toute l'app.
///
/// - Utilise l'API google_sign_in 6.x (constructeur + signIn)
/// - serverClientId = client Web Firebase (obligatoire pour idToken)
/// - Message d'erreur clair pour ApiException 10 (SHA / package)
/// - Affiche le VRAI SHA-1 de l'APK installée (via MethodChannel Kotlin)
///   pour éliminer toute ambiguïté entre debug / Play upload / Play signing.
class GoogleAuthHelper {
  /// Client Web OAuth du projet Firebase fakerni-b96c2
  /// (google-services.json → oauth_client type 3).
  static const String webClientId =
      '994131871524-dbn081ucefsf4vi4v0jl1m4gc11di90p.apps.googleusercontent.com';

  /// Package Android attendu (doit matcher Firebase + applicationId Gradle).
  static const String expectedPackage =
      'com.elbouni.ajalaks.el_bouni_pieces_auto';

  /// Tous les SHA-1 autorisés (doivent être enregistrés dans Firebase).
  ///
  /// - Debug (android/keystore/debug.keystore du dépôt)
  /// - Play Console – certificat d'upload
  /// - Play App Signing – certificat de signature final
  static const List<String> allowedSha1 = [
    'F0:3D:AB:51:B8:48:D0:6F:32:7C:68:A6:9F:40:33:AD:25:E5:BF:36', // debug
    '9C:F1:79:B7:4A:E8:94:3B:83:0E:25:C2:E6:93:F3:E7:66:0A:99:41', // Play upload
    '94:5D:CB:33:B8:FE:66:B2:92:7F:66:69:EE:B6:E8:18:4F:D6:B1:D2', // Play signing
  ];

  static const MethodChannel _signatureChannel =
      MethodChannel('vroum/app_signature');

  /// Récupère le SHA-1 réel de signature de l'APK actuellement installée.
  /// Retourne null si le channel n'est pas disponible (ex. iOS / web).
  static Future<String?> getInstalledSha1() async {
    try {
      final result = await _signatureChannel.invokeMethod<String>('getSigningSha1');
      return result;
    } catch (_) {
      return null;
    }
  }

  /// Lance le flux Google et retourne le [UserCredential] Firebase.
  /// Lance une [Exception] avec un message lisible en cas d'échec.
  static Future<UserCredential> signIn() async {
    final googleSignIn = GoogleSignIn(
      serverClientId: webClientId,
      scopes: const ['email', 'profile'],
    );

    try {
      // Force un compte propre si une session Google native est corrompue.
      try {
        await googleSignIn.signOut();
      } catch (_) {}

      final GoogleSignInAccount? account = await googleSignIn.signIn();
      if (account == null) {
        throw Exception('Connexion Google annulée.');
      }

      final GoogleSignInAuthentication auth = await account.authentication;
      if (auth.idToken == null) {
        throw Exception(
          'Google n\'a pas renvoyé de jeton (idToken null). '
          'Vérifie que le client Web OAuth est correct dans Firebase.',
        );
      }

      final credential = GoogleAuthProvider.credential(
        accessToken: auth.accessToken,
        idToken: auth.idToken,
      );

      return await FirebaseAuth.instance.signInWithCredential(credential);
    } on PlatformException catch (e) {
      throw Exception(await _messagePourPlatformException(e));
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message ?? 'Erreur Firebase Auth (${e.code}).');
    }
  }

  static Future<String> _messagePourPlatformException(PlatformException e) async {
    final code = e.code.toLowerCase();
    final msg = '${e.message ?? ''} ${e.details ?? ''}'.toLowerCase();

    // ApiException: 10 = DEVELOPER_ERROR → SHA-1 / package / OAuth
    if (code.contains('sign_in_failed') ||
        msg.contains('apiexception: 10') ||
        msg.contains('api exception: 10') ||
        msg.contains('developer_error') ||
        msg.contains(': 10')) {
      final installedSha1 = await getInstalledSha1();
      final shaLine = installedSha1 != null
          ? 'SHA-1 de CET APK installé :\n$installedSha1\n\n'
          : '';

      final isKnown = installedSha1 != null &&
          allowedSha1.any((s) => s.toUpperCase() == installedSha1.toUpperCase());

      final advice = isKnown
          ? 'Ce SHA-1 est déjà dans la liste autorisée.\n'
              'Causes possibles restantes :\n'
              '• google-services.json pas à jour dans le build\n'
              '• Propagation Firebase/Google (attendre 5-15 min)\n'
              '• Ancienne version de l\'app encore installée → désinstalle complètement puis réinstalle\n'
              '• Client OAuth Android désactivé dans Google Cloud Console'
          : 'Ce SHA-1 n\'est PAS dans la liste autorisée.\n'
              'Ajoute-le dans Firebase → Paramètres projet → Empreintes SHA,\n'
              'puis télécharge un nouveau google-services.json et rebuild.';

      return 'Connexion Google refusée (erreur 10).\n\n'
          'Cause : le certificat de cet APK n\'est pas reconnu par Google/Firebase.\n\n'
          '$shaLine'
          'SHA-1 autorisés :\n'
          '• Debug     : ${allowedSha1[0]}\n'
          '• Play upload : ${allowedSha1[1]}\n'
          '• Play signing: ${allowedSha1[2]}\n\n'
          'Package attendu : $expectedPackage\n\n'
          '$advice';
    }

    if (msg.contains('network') || code.contains('network')) {
      return 'Réseau indisponible. Vérifie ta connexion et réessaie.';
    }

    return 'Connexion Google impossible (${e.code}).';
  }
}
