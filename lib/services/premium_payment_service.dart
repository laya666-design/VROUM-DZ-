import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart';
import 'cloudinary_service.dart';

/// Paiement Premium (compte personnel automobiliste) par virement
/// manuel — BaridiMob / CCP / virement bancaire — avec validation par un
/// admin, sur le même principe que le paiement d'abonnement magasin
/// (voir StoreService.submitPaymentProof), mais côté serveur via des
/// Cloud Functions dédiées (`premium_requests`) car un compte personnel
/// n'a pas de document Firestore associé : le Premium reste géré en
/// local sur l'appareil (voir SettingsService), et cette classe ne fait
/// que vérifier périodiquement si la demande a été validée.
class PremiumPaymentResult {
  final String statut; // 'en_attente' | 'valide' | 'refuse'
  final DateTime? premiumEndDate;
  PremiumPaymentResult({required this.statut, this.premiumEndDate});
}

class PremiumPaymentService {
  /// Envoie la preuve de paiement (photo du reçu) et crée la demande
  /// côté serveur. Retourne l'id de la demande, à conserver localement
  /// pour pouvoir vérifier son statut plus tard.
  static Future<String> submitPremiumPayment({
    required File recu,
    required String phone,
    required String methode,
    required String planId,
  }) async {
    final recuUrl = await CloudinaryService.uploadImage(
      recu,
      folder: 'premium_payment_proofs',
    );

    final callable =
        FirebaseFunctions.instance.httpsCallable('submitPremiumPayment');
    final result = await callable.call({
      'phone': phone,
      'methode': methode,
      'recuUrl': recuUrl,
      'planId': planId,
    });
    final requestId = result.data?['requestId'] as String?;
    if (requestId == null || requestId.isEmpty) {
      throw Exception('Impossible d\'enregistrer la demande.');
    }
    return requestId;
  }

  /// Consulte le statut d'une demande précédemment envoyée.
  static Future<PremiumPaymentResult> checkStatus(String requestId) async {
    final callable =
        FirebaseFunctions.instance.httpsCallable('checkPremiumPaymentStatus');
    final result = await callable.call({'requestId': requestId});
    final statut = result.data?['statut'] as String? ?? 'en_attente';
    final endStr = result.data?['premiumEndDate'] as String?;
    return PremiumPaymentResult(
      statut: statut,
      premiumEndDate: endStr != null ? DateTime.tryParse(endStr) : null,
    );
  }
}
