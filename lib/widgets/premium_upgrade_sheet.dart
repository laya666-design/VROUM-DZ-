import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../config/app_config.dart';
import '../services/premium_payment_service.dart';
import '../services/vehicule_service.dart';
import '../screens/sos/tel_picker_dialog.dart';

/// Bottom sheet Premium partagé (Profil + Véhicules / Motos).
/// Envoi d'une preuve de paiement BaridiMob → validation admin.
Future<void> showPremiumUpgradeSheet({
  required BuildContext context,
  required AppConfig config,
  required String Function(String fr, String ar) t,
  VoidCallback? onPremiumActivated,
}) async {
  final pendingRequestId = SettingsService.premiumRequestId;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      String planId = 'mensuel';
      String methode = 'Baridimob';
      File? recu;
      bool sending = false;
      bool checking = false;
      String? checkError;
      final phoneController =
          TextEditingController(text: SettingsService.userTel ?? '');

      Future<void> choisirRecu(void Function(void Function()) setSt) async {
        final picker = ImagePicker();
        final img =
            await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
        if (img == null) return;
        setSt(() => recu = File(img.path));
      }

      Future<void> envoyer(
          void Function(void Function()) setSt, BuildContext sheetCtx) async {
        if (recu == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(t('Ajoute une photo du reçu.', 'أضف صورة الوصل.'))),
          );
          return;
        }
        var phone = phoneController.text.trim();
        if (phone.isEmpty) {
          final saisi = await showTelPickerDialog(
            sheetCtx,
            accentColor: config.primaryColor,
            valeurInitiale: SettingsService.userTel,
          );
          if (saisi == null || saisi.trim().isEmpty) return;
          phone = saisi.trim();
          phoneController.text = phone;
        }
        await SettingsService.setUserTel(phone);
        setSt(() => sending = true);
        try {
          final requestId = await PremiumPaymentService.submitPremiumPayment(
            recu: recu!,
            phone: phone,
            methode: methode,
            planId: planId,
          );
          await SettingsService.setPremiumRequestId(requestId);
          if (!ctx.mounted) return;
          Navigator.pop(ctx);
          if (context.mounted) {
            showDialog(
              context: context,
              builder: (dctx) => AlertDialog(
                title: Text(t('Preuve envoyée', 'تم إرسال الوصل')),
                content: Text(t(
                  'Ta demande Premium est en cours de validation. '
                  'Tu recevras l\'accès dès qu\'un admin aura confirmé le paiement. '
                  'Tu peux vérifier le statut depuis l\'onglet Profil.',
                  'طلب Premium قيد التحقق. ستحصل على الوصول بمجرد تأكيد الدفع من قبل المشرف. يمكنك التحقق من الحالة من تبويب الملف الشخصي.',
                )),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dctx),
                    child: Text(t('OK', 'حسناً')),
                  ),
                ],
              ),
            );
          }
        } catch (e) {
          if (!sheetCtx.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur : $e')),
          );
        } finally {
          if (sheetCtx.mounted) setSt(() => sending = false);
        }
      }

      Future<void> verifierStatut(void Function(void Function()) setSt) async {
        if (pendingRequestId == null) return;
        setSt(() {
          checking = true;
          checkError = null;
        });
        try {
          final res =
              await PremiumPaymentService.checkStatus(pendingRequestId);
          if (res.statut == 'valide') {
            await SettingsService.setPremiumUntil(res.premiumEndDate ??
                DateTime.now().add(const Duration(days: 30)));
            await SettingsService.setPremiumRequestId(null);
            if (!ctx.mounted) return;
            Navigator.pop(ctx);
            onPremiumActivated?.call();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      t('🎉 Bienvenue en Premium !', '🎉 مرحباً بك في Premium !')),
                  backgroundColor: config.primaryColor,
                ),
              );
            }
            return;
          } else if (res.statut == 'refuse') {
            await SettingsService.setPremiumRequestId(null);
            setSt(() => checkError = t(
                'Paiement refusé. Contacte le support si tu penses que c\'est une erreur.',
                'تم رفض الدفع. تواصل مع الدعم إذا كنت تعتقد أن هذا خطأ.'));
          } else {
            setSt(() => checkError = t(
                'Toujours en attente de validation.', 'لا يزال قيد التحقق.'));
          }
        } catch (e) {
          setSt(() => checkError = 'Erreur : $e');
        } finally {
          setSt(() => checking = false);
        }
      }

      return StatefulBuilder(builder: (ctx, setSt) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            child: SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(Icons.workspace_premium,
                            color: config.primaryColor, size: 28),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            t('Passe en Premium', 'الترقية إلى Premium'),
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      t(
                        'La version gratuite permet de gérer 1 élément dans cette '
                        'rubrique. Passe en Premium pour en ajouter sans limite, '
                        'exporter tes documents en PDF, et utiliser l\'app sans '
                        'publicité.',
                        'تسمح النسخة المجانية بإدارة عنصر واحد فقط في هذا القسم. '
                        'قم بالترقية إلى Premium لإضافة عناصر بلا حدود، وتصدير '
                        'مستنداتك بصيغة PDF، واستخدام التطبيق بدون إعلانات.',
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (pendingRequestId != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              t(
                                'Une demande est déjà en attente de validation.',
                                'يوجد طلب قيد الانتظار.',
                              ),
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            if (checkError != null) ...[
                              const SizedBox(height: 6),
                              Text(checkError!,
                                  style: TextStyle(color: Colors.red.shade700)),
                            ],
                            const SizedBox(height: 8),
                            FilledButton(
                              onPressed:
                                  checking ? null : () => verifierStatut(setSt),
                              style: FilledButton.styleFrom(
                                  backgroundColor: config.primaryColor),
                              child: checking
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white),
                                    )
                                  : Text(t('Vérifier le statut', 'تحقق من الحالة')),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text(t('Plan', 'الخطة'),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(
                            value: 'mensuel',
                            label: Text(t('Mensuel', 'شهري'))),
                        ButtonSegment(
                            value: 'annuel',
                            label: Text(t('Annuel', 'سنوي'))),
                      ],
                      selected: {planId},
                      onSelectionChanged: (s) =>
                          setSt(() => planId = s.first),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: t('Téléphone', 'الهاتف'),
                        prefixIcon: const Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: sending ? null : () => choisirRecu(setSt),
                      icon: const Icon(Icons.receipt_long),
                      label: Text(recu == null
                          ? t('Ajouter la photo du reçu', 'أضف صورة الوصل')
                          : t('Reçu sélectionné ✓', 'تم اختيار الوصل ✓')),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: sending ? null : () => envoyer(setSt, ctx),
                      style: FilledButton.styleFrom(
                        backgroundColor: config.primaryColor,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: sending
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text(t('Envoyer la preuve de paiement',
                              'إرسال إثبات الدفع')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      });
    },
  );
}
