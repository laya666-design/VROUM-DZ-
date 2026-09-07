import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Point UNIQUE pour Google Sign-In dans toute l'app.
///
/// - Utilise l'API google_sign_in 6.x (constructeur + signIn)
/// - serverClientId = client Web Firebase (obligatoire pour idToken)
/// - Message d'erreur clair pour ApiException 10 (SHA / package)
class GoogleAuthHelper {
  /// Client Web OAuth du projet Firebase fakerni-b96c2
  /// (google-services.json → oauth_client type 3).
  static const String webClientId =
      '994131871524-dbn081ucefsf4vi4v0jl1m4gc11di90p.apps.googleusercontent.com';

  /// Package Android attendu (doit matcher Firebase + applicationId Gradle).
  static const String expectedPackage =
      'com.elbouni.ajalaks.el_bouni_pieces_auto';

  /// SHA-1 du keystore debug du dépôt (android/keystore/debug.keystore).
  static const String expectedSha1 =
      'F0:3D:AB:51:B8:48:D0:6F:32:7C:68:A6:9F:40:33:AD:25:E5:BF:36';

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
      throw Exception(_messagePourPlatformException(e));
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message ?? 'Erreur Firebase Auth (${e.code}).');
    }
  }

  static String _messagePourPlatformException(PlatformException e) {
    final code = e.code.toLowerCase();
    final msg = '${e.message ?? ''} ${e.details ?? ''}'.toLowerCase();

    // ApiException: 10 = DEVELOPER_ERROR → SHA-1 / package / OAuth
    if (code.contains('sign_in_failed') ||
        msg.contains('apiexception: 10') ||
        msg.contains('api exception: 10') ||
        msg.contains('developer_error') ||
        msg.contains(': 10')) {
      return 'Connexion Google refusée (erreur 10).\n\n'
          'Cause : le certificat de cet APK n\'est pas enregistré dans Firebase.\n\n'
          'À faire une seule fois :\n'
          '1) L\'APK doit être signé avec android/keystore/debug.keystore\n'
          '   (SHA-1 attendu : $expectedSha1)\n'
          '2) Package exact : $expectedPackage\n'
          '3) Firebase → Paramètres projet → empreintes SHA-1 + SHA-256\n'
          '4) Télécharger un nouveau google-services.json\n'
          '5) Désinstaller l\'ancienne app, réinstaller le nouvel APK\n\n'
          'Le workflow GitHub force déjà le bon keystore.';
    }

    if (msg.contains('network') || code.contains('network')) {
      return 'Réseau indisponible. Vérifie ta connexion et réessaie.';
    }

    return 'Connexion Google impossible (${e.code}).';
  }
}
