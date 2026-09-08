import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// OCR 100% local (aucune connexion requise) via ML Kit.
/// Utilisé pour lire les cartes jaunes / vignettes assurance et,
/// en complément, la texture de la pièce détachée (référence imprimée).
class OcrService {
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  /// Retourne le texte brut détecté dans l'image.
  Future<String> extractText(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final RecognizedText result = await _recognizer.processImage(inputImage);
    return result.text;
  }

  /// Extrait toutes les dates au format JJ/MM/AAAA, J/M/AAAA, JJ.MM.AAAA
  /// ou JJ-MM-AAAA trouvées dans le texte OCR (cartes jaunes, CT, etc.).
  static List<DateTime> extractDates(String rawText) {
    final regex = RegExp(r'(\d{1,2})[\/\.\-](\d{1,2})[\/\.\-](\d{2,4})');
    final matches = regex.allMatches(rawText);
    final dates = <DateTime>[];

    for (final m in matches) {
      final day = int.tryParse(m.group(1) ?? '');
      final month = int.tryParse(m.group(2) ?? '');
      var year = int.tryParse(m.group(3) ?? '');
      if (day == null || month == null || year == null) continue;
      if (year < 100) year += 2000;
      if (month < 1 || month > 12) continue;
      if (day < 1 || day > 31) continue;
      if (year < 2000 || year > 2100) continue;
      try {
        dates.add(DateTime(year, month, day));
      } catch (_) {
        // date invalide (ex: 31/02) -> ignorée
      }
    }

    dates.sort();
    return dates;
  }

  /// La date d'expiration = la plus récente des dates détectées
  /// (règle métier confirmée sur les cartes jaunes SAA/CAAT/etc.,
  /// où la date de début précède toujours la date de fin).
  static DateTime? mostRecentDate(List<DateTime> dates) {
    if (dates.isEmpty) return null;
    return dates.last;
  }

  /// Contrôle technique — règle métier définitive :
  /// extraire TOUTES les dates du document et prendre la plus récente.
  /// (Les mots-clés VISITE PERIODIQUE / etc. ont trop souvent mené à
  /// une mauvaise date tamponnée ou mal lue par l'OCR.)
  static DateTime? extractDateVisitePeriodique(String rawText) {
    final all = extractDates(rawText);
    return mostRecentDate(all);
  }

  void dispose() {
    _recognizer.close();
  }
}

/// Résultat du calcul de jours restants, avec code couleur.
class ExpiryStatus {
  final DateTime expirationDate;
  final int daysRemaining; // peut être négatif si expiré
  final bool isExpired;

  ExpiryStatus({required this.expirationDate})
      : daysRemaining = expirationDate
            .difference(DateTime(
              DateTime.now().year,
              DateTime.now().month,
              DateTime.now().day,
            ))
            .inDays,
        isExpired = expirationDate.isBefore(DateTime.now());

  /// vert >30j, orange 7-30j, rouge <7j ou expiré
  StatusLevel get level {
    if (isExpired) return StatusLevel.expired;
    if (daysRemaining <= 30) return StatusLevel.warning;
    return StatusLevel.ok;
  }

  String get label {
    if (isExpired) {
      return 'EXPIRÉ depuis ${daysRemaining.abs()}j - À RENOUVELER';
    }
    return 'OK - ${daysRemaining}j restants';
  }

  String labelFor(bool isAr) {
    if (!isAr) return label;
    if (isExpired) {
      return 'منتهي منذ ${daysRemaining.abs()} يوم - يجب التجديد';
    }
    return 'صالح - يتبقى ${daysRemaining} يوم';
  }
}

enum StatusLevel { ok, warning, expired }
