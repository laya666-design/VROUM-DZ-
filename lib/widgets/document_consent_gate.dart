import 'package:flutter/material.dart';
import '../services/vehicule_service.dart';
import '../theme/app_theme.dart';

/// Vérifie/obtient le consentement de l'utilisateur avant le tout premier
/// scan d'un document (carte grise, assurance, contrôle technique).
///
/// Contexte légal (loi 18-07 modifiée par la loi 25-11, Algérie) : le
/// traitement de données personnelles nécessite un consentement exprès,
/// et le transfert de données vers un pays tiers doit être signalé. La
/// photo du document est envoyée à un service d'IA externe (Google
/// Gemini, via un relais Cloudflare) le temps de l'analyse ; seules les
/// informations extraites (dates, numéros…) sont ensuite conservées, et
/// uniquement sur l'appareil de l'utilisateur (base locale Hive, pas de
/// serveur VROUM DZ).
///
/// Affiché une seule fois (flag persistant dans SettingsService) : si le
/// consentement a déjà été donné, retourne true immédiatement sans rien
/// afficher. Sinon, ouvre une feuille modale avec une case à cocher
/// obligatoire avant de continuer. Retourne false si l'utilisateur annule.
Future<bool> ensureDocumentScanConsent(
  BuildContext context, {
  required bool isAr,
}) async {
  if (SettingsService.hasDocumentScanConsent) return true;

  final accepted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (_) => _ConsentSheet(isAr: isAr),
  );

  if (accepted == true) {
    await SettingsService.setDocumentScanConsent(true);
    return true;
  }
  return false;
}

class _ConsentSheet extends StatefulWidget {
  final bool isAr;
  const _ConsentSheet({required this.isAr});

  @override
  State<_ConsentSheet> createState() => _ConsentSheetState();
}

class _ConsentSheetState extends State<_ConsentSheet> {
  bool _checked = false;

  String _t(String fr, String ar) => widget.isAr ? ar : fr;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.privacy_tip_outlined, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _t('Confidentialité de tes documents', 'خصوصية وثائقك'),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _t(
                'Les informations extraites (dates, numéros, marque…) sont enregistrées uniquement sur ton téléphone — VROUM DZ n\'a pas de serveur qui les stocke.\n\n'
                'La photo elle-même est envoyée, le temps de l\'analyse, à un service d\'intelligence artificielle (Google Gemini) qui lit le document pour en extraire ces informations automatiquement.',
                'المعلومات المستخرجة (التواريخ، الأرقام، الماركة...) تُحفظ فقط في هاتفك — تطبيق VROUM DZ ليس له خادم يخزنها.\n\n'
                'أما الصورة نفسها، فتُرسل خلال وقت التحليل فقط إلى خدمة ذكاء اصطناعي (Google Gemini) تقرأ الوثيقة لاستخراج هذه المعلومات تلقائياً.',
              ),
              style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary, height: 1.45),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: () => setState(() => _checked = !_checked),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: _checked,
                      onChanged: (v) => setState(() => _checked = v ?? false),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _t(
                            'J\'ai compris et j\'accepte que ce document soit analysé de cette façon.',
                            'فهمت وأوافق على تحليل هذه الوثيقة بهذه الطريقة.',
                          ),
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(_t('Annuler', 'إلغاء')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _checked ? () => Navigator.of(context).pop(true) : null,
                    child: Text(_t('Continuer', 'متابعة')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
