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

  /// Extrait toutes les dates (espaces optionnels autour des séparateurs).
  static List<DateTime> extractDates(String rawText) {
    final regex =
        RegExp(r'(\d{1,2})\s*[\/\.\-]\s*(\d{1,2})\s*[\/\.\-]\s*(\d{2,4})');
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

  /// Contrôle technique — règle métier :
  /// 1) extraire TOUTES les dates du document
  /// 2) aussi les dates proches des mots-clés VISITE PERIODIQUE / etc.
  /// 3) prendre la plus récente de l'ensemble.
  /// (Les tampons roses "11/12/2026" sont parfois mal lus par l'OCR
  /// latin seul ; les motifs aident à les récupérer.)
  static DateTime? extractDateVisitePeriodique(String rawText) {
    final all = <DateTime>[...extractDates(rawText)];

    final patterns = [
      RegExp(
        r'(?:VISITE\s*PERIODIQUE|PERIODIQUE|PROCHAINE\s*VISITE|PROCHAIN\s*CONTROLE|PROCHAIN\s*CONTR[OÔ]LE|RENDEZ[-\s]?VOUS|RDV)\s*(?:LE\s*|AU\s*|:)?\s*(\d{1,2})[\/\.\-](\d{1,2})[\/\.\-](\d{2,4})',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:VISITE|PERIODIQUE|PROCHAINE|RENDEZ|RDV)[^\d]{0,40}(\d{1,2})[\/\.\-](\d{1,2})[\/\.\-](\d{2,4})',
        caseSensitive: false,
      ),
      RegExp(r'المراقبة\s*اللاحقة[^\d]{0,40}(\d{1,2})[\/\.\-](\d{1,2})[\/\.\-](\d{2,4})'),
      RegExp(r'طبيعة\s*وتاريخ[^\d]{0,40}(\d{1,2})[\/\.\-](\d{1,2})[\/\.\-](\d{2,4})'),
      RegExp(r'الموعد\s*القادم[^\d]{0,40}(\d{1,2})[\/\.\-](\d{1,2})[\/\.\-](\d{2,4})'),
      RegExp(r'زيارة\s*دورية[^\d]{0,40}(\d{1,2})[\/\.\-](\d{1,2})[\/\.\-](\d{2,4})'),
    ];

    for (final re in patterns) {
      for (final m in re.allMatches(rawText)) {
        final day = int.tryParse(m.group(1) ?? '');
        final month = int.tryParse(m.group(2) ?? '');
        var year = int.tryParse(m.group(3) ?? '');
        if (day == null || month == null || year == null) continue;
        if (year < 100) year += 2000;
        if (month >= 1 && month <= 12 && day >= 1 && day <= 31 &&
            year >= 2000 && year <= 2100) {
          try {
            all.add(DateTime(year, month, day));
          } catch (_) {}
        }
      }
    }

    if (all.isEmpty) return null;
    all.sort();
    return all.last;
  }

  /// Détecte une marque connue dans un texte OCR brut (arabe ou latin).
  /// Utile en secours si l'IA Groq échoue (rate limit) ou renvoie null.
  static String? detectMarqueLocale(String rawText) {
    final t = rawText.toUpperCase();
    // Latin d'abord (plus fiable si déjà en majuscules sur le document)
    const latin = [
      'TOYOTA', 'RENAULT', 'PEUGEOT', 'NISSAN', 'HYUNDAI', 'KIA',
      'VOLKSWAGEN', 'DACIA', 'CITROEN', 'CITROËN', 'FIAT', 'CHEVROLET',
      'SUZUKI', 'MITSUBISHI', 'FORD', 'OPEL', 'MAZDA', 'HONDA',
      'MERCEDES', 'BMW', 'SEAT', 'SKODA', 'AUDI',
    ];
    for (final m in latin) {
      if (t.contains(m)) {
        return m == 'CITROËN' ? 'CITROEN' : m;
      }
    }
    // Arabe → latin
    const arabe = <String, String>{
      'تويوتا': 'TOYOTA',
      'رينو': 'RENAULT',
      'بيجو': 'PEUGEOT',
      'نيسان': 'NISSAN',
      'هيونداي': 'HYUNDAI',
      'هيونداى': 'HYUNDAI',
      'كيا': 'KIA',
      'فولكسفاغن': 'VOLKSWAGEN',
      'فولكس واجن': 'VOLKSWAGEN',
      'داسيا': 'DACIA',
      'سيتروين': 'CITROEN',
      'فيات': 'FIAT',
      'شيفروليه': 'CHEVROLET',
      'سوزوكي': 'SUZUKI',
      'ميتسوبيشي': 'MITSUBISHI',
      'فورد': 'FORD',
      'اوبل': 'OPEL',
      'مازدا': 'MAZDA',
      'هوندا': 'HONDA',
      'مرسيدس': 'MERCEDES',
      'بي ام دبليو': 'BMW',
    };
    for (final entry in arabe.entries) {
      if (rawText.contains(entry.key)) return entry.value;
    }
    return null;
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
