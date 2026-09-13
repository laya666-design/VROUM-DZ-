import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'ocr_service.dart';
import 'vehicule.dart';

/// Génère et partage un PDF récapitulatif d'un véhicule (identité +
/// statut assurance/CT) — fonctionnalité Premium.
///
/// Ne contient pas les photos brutes des documents scannés : l'app ne
/// conserve pas ces photos après l'OCR (seules les informations extraites
/// sont sauvegardées), donc le PDF est un résumé texte, pas un scan.
class PdfExportService {
  static Future<void> exportVehicule(
    Vehicule v, {
    required bool isAr,
  }) async {
    final doc = pw.Document();

    String t(String fr, String ar) => isAr ? ar : fr;

    String statutTexte(DateTime? expiration, String labelVide) {
      if (expiration == null) return labelVide;
      final status = ExpiryStatus(expirationDate: expiration);
      final jour = '${expiration.day}/${expiration.month}/${expiration.year}';
      if (status.isExpired) {
        return t(
          'Expiré depuis ${status.daysRemaining.abs()} j (le $jour)',
          'منتهي منذ ${status.daysRemaining.abs()} يوم ($jour)',
        );
      }
      return t(
        '$jour — ${status.daysRemaining} j restants',
        '$jour — باقي ${status.daysRemaining} يوم',
      );
    }

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'VROUM DZ',
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromHex('#16A34A'),
                    ),
                  ),
                  pw.Text(
                    t('Fiche véhicule', 'بطاقة المركبة'),
                    style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
                  ),
                ],
              ),
              pw.Divider(),
              pw.SizedBox(height: 12),
              pw.Text(
                v.nom,
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 4),
              if (v.marque.isNotEmpty)
                pw.Text(v.marque, style: const pw.TextStyle(fontSize: 13, color: PdfColors.grey700)),
              pw.SizedBox(height: 16),

              _section(t('Identité du véhicule', 'هوية المركبة')),
              _row(t('Immatriculation', 'رقم التسجيل'), v.immatriculation),
              if (v.year != null) _row(t('Année', 'السنة'), '${v.year}'),
              if (v.chassisNumber.isNotEmpty) _row(t('N° châssis', 'رقم الهيكل'), v.chassisNumber),
              if (v.engineCode.isNotEmpty) _row(t('Code moteur', 'رمز المحرك'), v.engineCode),
              if (v.fuelType.isNotEmpty) _row(t('Carburant', 'نوع الوقود'), v.fuelType),
              if (v.puissanceFiscale.isNotEmpty)
                _row(t('Puissance fiscale', 'القوة الجبائية'), v.puissanceFiscale),
              if (v.km != null) _row(t('Kilométrage', 'الكيلومترات'), '${v.km} km'),

              pw.SizedBox(height: 18),
              _section(t('Assurance', 'التأمين')),
              _row(
                t('Statut', 'الحالة'),
                statutTexte(v.assuranceExpiration, t('Non renseignée', 'غير محددة')),
              ),
              if (v.assuranceCompagnie.isNotEmpty)
                _row(t('Compagnie', 'شركة التأمين'), v.assuranceCompagnie),
              if (v.assuranceNumeroPolice.isNotEmpty)
                _row(t('N° police', 'رقم البوليصة'), v.assuranceNumeroPolice),
              if (v.assuranceNomAssure.isNotEmpty)
                _row(t('Assuré', 'المؤمَّن'), v.assuranceNomAssure),

              pw.SizedBox(height: 18),
              _section(t('Contrôle technique', 'الفحص التقني')),
              _row(
                t('Statut', 'الحالة'),
                statutTexte(v.controleTechniqueExpiration, t('Non renseigné', 'غير محدد')),
              ),
              if (v.ctCentre.isNotEmpty) _row(t('Centre', 'المركز'), v.ctCentre),
              if (v.ctNumero.isNotEmpty) _row(t('N° contrôle', 'رقم الفحص'), v.ctNumero),

              pw.Spacer(),
              pw.Divider(),
              pw.Text(
                t(
                  'Document généré automatiquement par l\'app VROUM DZ le '
                      '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year} — '
                      'informations saisies par l\'utilisateur, à vérifier avant tout usage officiel.',
                  'تم إنشاء هذه الوثيقة تلقائياً عبر تطبيق VROUM DZ بتاريخ '
                      '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year} — '
                      'المعلومات أدخلها المستخدم، يُرجى التحقق منها قبل أي استعمال رسمي.',
                ),
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
              ),
            ],
          );
        },
      ),
    );

    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: 'vroum-dz-${v.nom.replaceAll(' ', '_')}.pdf',
    );
  }

  static pw.Widget _section(String titre) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Text(
        titre,
        style: pw.TextStyle(
          fontSize: 13,
          fontWeight: pw.FontWeight.bold,
          color: PdfColor.fromHex('#16A34A'),
        ),
      ),
    );
  }

  static pw.Widget _row(String label, String valeur) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 130,
            child: pw.Text(label, style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
          ),
          pw.Expanded(
            child: pw.Text(
              valeur.isEmpty ? '—' : valeur,
              style: const pw.TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
