import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../config/app_config.dart';
import '../services/premium_payment_service.dart';
import '../services/vehicule_service.dart';
import '../screens/sos/tel_picker_dialog.dart';

/// Bottom sheet Premium identique à celui du Profil
/// (prix, BaridiMob, reçu, avantages).
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
                  'طلب Premium قيد التحقق. ستحصل على الوصول بمجرد تأكيد الدفع من قبل المشرف.',
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

      Widget planCard({
        required bool selected,
        required String titre,
        required String sousTitre,
        required VoidCallback onTap,
      }) {
        return Material(
          color: selected
              ? config.primaryColor.withOpacity(0.12)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? config.primaryColor
                      : Colors.grey.shade300,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    titre,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: selected
                          ? config.primaryColor
                          : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    sousTitre,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      Widget benefitRow(String title, String subtitle) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.check_circle, color: config.primaryColor, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
            ],
          ),
        );
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
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'VROUM Premium',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      t(
                        'Tout ce dont vous avez besoin pour gérer vos véhicules sans limite.',
                        'كل ما تحتاجه لإدارة مركباتك بلا حدود.',
                      ),
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 20),

                    if (pendingRequestId != null) ...[
                      Container(
                        width: double.infinity,
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
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            if (checkError != null) ...[
                              const SizedBox(height: 6),
                              Text(checkError!,
                                  style:
                                      TextStyle(color: Colors.red.shade700)),
                            ],
                            const SizedBox(height: 8),
                            FilledButton(
                              onPressed: checking
                                  ? null
                                  : () => verifierStatut(setSt),
                              style: FilledButton.styleFrom(
                                  backgroundColor: config.primaryColor),
                              child: checking
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white),
                                    )
                                  : Text(t('Vérifier le statut',
                                      'تحقق من الحالة')),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    Row(
                      children: [
                        Expanded(
                          child: planCard(
                            selected: planId == 'mensuel',
                            titre: '490 DA',
                            sousTitre: t('/ mois', '/ شهر'),
                            onTap: () => setSt(() => planId = 'mensuel'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: planCard(
                            selected: planId == 'annuel',
                            titre: '4 900 DA',
                            sousTitre:
                                t('/ an · -2 mois', '/ سنة · وفّر شهرين'),
                            onTap: () => setSt(() => planId = 'annuel'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    DropdownButtonFormField<String>(
                      value: methode,
                      decoration: InputDecoration(
                        labelText: t('Méthode de paiement', 'طريقة الدفع'),
                        border: const OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'Baridimob', child: Text('BaridiMob')),
                        DropdownMenuItem(value: 'CCP', child: Text('CCP')),
                        DropdownMenuItem(
                            value: 'Virement',
                            child: Text('Virement bancaire')),
                      ],
                      onChanged: (v) =>
                          setSt(() => methode = v ?? 'Baridimob'),
                    ),
                    if (methode == 'Baridimob') ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.blue.shade100),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.phone_iphone,
                                color: Colors.blueGrey),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t(
                                      'Envoie le montant sur ce numéro BaridiMob :',
                                      'أرسل المبلغ إلى رقم BaridiMob هذا:',
                                    ),
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.black54),
                                  ),
                                  Text(
                                    config.baridimobPhone,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 20),
                              tooltip: t('Copier le numéro', 'نسخ الرقم'),
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(
                                    text: config.baridimobPhone));
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(t('Numéro copié.',
                                            'تم نسخ الرقم.'))),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText:
                            t('Ton numéro de téléphone', 'رقم هاتفك'),
                        prefixIcon: const Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: sending ? null : () => choisirRecu(setSt),
                      icon: Icon(recu == null
                          ? Icons.camera_alt_outlined
                          : Icons.check_circle_outline),
                      label: Text(recu == null
                          ? t('Ajouter la photo du reçu', 'أضف صورة الوصل')
                          : t('Reçu sélectionné ✓', 'تم اختيار الوصل ✓')),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
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
                    const SizedBox(height: 24),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        t('Pourquoi Premium ?', 'لماذا Premium ؟'),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 12),
                    benefitRow(
                      t('Véhicules illimités', 'مركبات غير محدودة'),
                      t(
                          'Ajoutez autant de voitures ou motos que vous voulez',
                          'أضف أكبر عدد من السيارات أو الدراجات'),
                    ),
                    benefitRow(
                      t('Export PDF des documents', 'تصدير المستندات PDF'),
                      t(
                          'Une fiche récapitulative de ton véhicule, prête à partager',
                          'بطاقة ملخصة لمركبتك، جاهزة للمشاركة'),
                    ),
                    benefitRow(
                      t('Sans publicité', 'بدون إعلانات'),
                      t('Utilise l\'app sans aucune bannière',
                          'استخدم التطبيق بدون أي إعلان'),
                    ),
                    benefitRow(
                      t('Support prioritaire', 'دعم ذو أولوية'),
                      t('Réponse en moins de 2h via WhatsApp',
                          'رد في أقل من ساعتين عبر واتساب'),
                    ),
                    benefitRow(
                      t('Accès anticipé', 'وصول مبكر'),
                      t('Nouvelles fonctionnalités en avant-première',
                          'ميزات جديدة قبل الجميع'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(
                        t('Plus tard', 'لاحقاً'),
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
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
