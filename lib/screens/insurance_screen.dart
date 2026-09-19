import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../config/app_config.dart';
import '../services/gemini_service.dart';
import '../services/models.dart';
import '../services/notification_service.dart';
import '../services/ocr_service.dart';
import '../services/vehicule.dart';
import '../services/vehicule_service.dart';
import '../widgets/document_consent_gate.dart';
import '../widgets/status_card.dart';

class InsuranceScreen extends StatefulWidget {
  final AppConfig config;

  /// Si fourni, les résultats sont rattachés et sauvegardés sur ce véhicule
  /// (Phase 1 — gestion multi-véhicules). Si null, l'écran fonctionne comme
  /// avant, sans persistance (compatibilité ascendante).
  final Vehicule? vehicule;
  final bool isAr;

  /// true quand ce widget est empilé dans la fiche véhicule à 3 sections
  /// plutôt qu'affiché seul dans son propre onglet.
  final bool embedded;

  /// Appelé automatiquement juste après un enregistrement réussi (photo
  /// scannée + date reconnue + sauvegardée). Utilisé par le parcours
  /// d'ajout de véhicule pour enchaîner directement sur l'étape suivante
  /// (contrôle technique) sans action supplémentaire de l'utilisateur.
  final VoidCallback? onEnregistre;

  const InsuranceScreen({
    super.key,
    required this.config,
    this.vehicule,
    this.isAr = false,
    this.embedded = false,
    this.onEnregistre,
  });

  @override
  State<InsuranceScreen> createState() => _InsuranceScreenState();
}

class _InsuranceScreenState extends State<InsuranceScreen> {
  final _picker = ImagePicker();
  final _ocr = OcrService();
  final _gemini = GeminiService();

  File? _image;
  bool _loading = false;
  String? _error;
  String? _retryLabel; // ex. "Vérification 2/3…" pendant les nouvelles tentatives

  ExpiryStatus? _status; // calculé localement via OCR -> fait foi
  InsuranceInfo? _info; // détails structurés via Gemini -> complément

  String _t(String fr, String ar) => widget.isAr ? ar : fr;

  @override
  void initState() {
    super.initState();
    // Si le véhicule a déjà une assurance enregistrée, on l'affiche
    // directement sans attendre une nouvelle photo.
    final v = widget.vehicule;
    if (v?.assuranceExpiration != null) {
      _status = ExpiryStatus(expirationDate: v!.assuranceExpiration!);
      _info = InsuranceInfo(
        compagnie: v.assuranceCompagnie,
        nom: v.assuranceNomAssure,
        marque: v.marque,
        police: v.assuranceNumeroPolice,
      );
    }
  }

  @override
  void dispose() {
    _ocr.dispose();
    super.dispose();
  }

  Future<void> _saveToVehicule() async {
    final v = widget.vehicule;
    if (v == null || _status == null) return;
    v.assuranceExpiration = _status!.expirationDate;
    if (_info != null) {
      if (_info!.compagnie.isNotEmpty) v.assuranceCompagnie = _info!.compagnie;
      if (_info!.nom.isNotEmpty) v.assuranceNomAssure = _info!.nom;
      if (_info!.police.isNotEmpty) v.assuranceNumeroPolice = _info!.police;
      if (_info!.marque.isNotEmpty && v.marque.isEmpty) v.marque = _info!.marque;
    }
    await VehiculeService.update(v);
    await NotificationService.scheduleExpiryReminders(
      vehiculeId: v.id,
      typeRappel: 'assurance',
      titre: v.nom,
      libelleDocument: 'Assurance / Vignette',
      expiration: v.assuranceExpiration!,
    );
  }

  /// Une seule passe d'analyse complète (OCR local + Gemini + fusion des
  /// dates), même principe que pour le contrôle technique : on ne fait
  /// JAMAIS confiance à une seule source pour la date d'expiration.
  Future<({InsuranceInfo info, DateTime? expiration})> _analyzeOnce(
      File file) async {
    final rawText = await _ocr.extractText(file);
    final allOcrDates = OcrService.extractDates(rawText);
    final fromOcrKeyword = OcrService.extractDateExpirationAssurance(rawText);

    InsuranceInfo info = InsuranceInfo();
    try {
      final json = await _gemini.analyzeInsuranceCard(file);
      if (json['error'] == null) {
        info = InsuranceInfo.fromJson(json);
      }
    } catch (_) {
      // Complément IA optionnel — l'OCR local reste la source de vérité des dates.
    }

    final fromAi = info.expirationParsed;
    final candidates = <DateTime>[
      ...allOcrDates,
      if (fromOcrKeyword != null) fromOcrKeyword,
      if (fromAi != null) fromAi,
    ];
    DateTime? expiration;
    if (candidates.isNotEmpty) {
      candidates.sort();
      expiration = candidates.last; // PLUS RÉCENTE de toutes (= date AU)
    }

    return (info: info, expiration: expiration);
  }

  Future<void> _pickImage(ImageSource source) async {
    final ok = await ensureDocumentScanConsent(context, isAr: widget.isAr);
    if (!ok) return;

    setState(() {
      _error = null;
      _status = null;
      _info = null;
    });

    final picked = await _picker.pickImage(source: source, imageQuality: 90);
    if (picked == null) return;

    final file = File(picked.path);
    setState(() {
      _image = file;
      _loading = true;
    });

    try {
      // Règle métier (identique au contrôle technique) : on n'a pas droit
      // à l'erreur sur une date EXPIRÉE affichée à tort. Si le résultat
      // d'une tentative est rouge, on relance l'analyse complète jusqu'à
      // 3 fois au total ; dès qu'une tentative trouve une date valide
      // (verte), on l'affiche et on s'arrête.
      const maxTentatives = 3;
      InsuranceInfo? meilleureInfo;
      DateTime? meilleureExpiration;

      for (var tentative = 1; tentative <= maxTentatives; tentative++) {
        if (tentative > 1 && mounted) {
          setState(() {
            _retryLabel = _t(
              'Date expirée détectée, nouvelle vérification $tentative/$maxTentatives…',
              'تم رصد تاريخ منتهي، إعادة التحقق $tentative/$maxTentatives…',
            );
          });
        }

        final resultat = await _analyzeOnce(file);
        if (resultat.expiration != null) {
          meilleureInfo = resultat.info;
          meilleureExpiration = resultat.expiration;
          final estExpire = resultat.expiration!.isBefore(DateTime.now());
          if (!estExpire) break; // date verte trouvée -> on s'arrête là
          // rouge -> on retente (sauf si c'était la dernière tentative)
        }
      }
      _retryLabel = null;

      if (meilleureExpiration != null) {
        _status = ExpiryStatus(expirationDate: meilleureExpiration);
        _info = meilleureInfo;
      } else {
        _error = _t(
          'Aucune date reconnue sur cette photo, même après plusieurs '
              'vérifications. Reprends la photo bien cadrée sur les dates, '
              'ou vérifie manuellement.',
          'لم يتم التعرف على أي تاريخ في هذه الصورة رغم عدة محاولات. أعد '
              'التقاط الصورة مع تأطير جيد للتواريخ، أو تحقق يدويًا.',
        );
      }

      try {
        await _saveToVehicule();
      } catch (_) {
        // Sauvegarde / rappels locaux (exact alarms) ne doivent jamais
        // afficher une erreur rouge si l'OCR a déjà réussi.
      }
    } catch (e) {
      // N'affiche le bandeau rouge que pour une vraie échec de lecture OCR.
      final msg = e.toString();
      if (!msg.contains('exact_alarms') && !msg.contains('Exact alarms')) {
        _error = _t(
          'Erreur de lecture de l\'image. Reprends la photo bien cadrée.',
          'خطأ في قراءة الصورة. أعد التقاط الصورة بإطار جيد.',
        );
      }
    } finally {
      _retryLabel = null;
      if (mounted) setState(() => _loading = false);
    }

    // Enchaînement automatique (parcours d'ajout de véhicule) : seulement
    // si une date a bien été reconnue et enregistrée, avec un court délai
    // pour laisser l'utilisateur voir le résultat avant de passer à l'étape
    // suivante (contrôle technique).
    if (mounted && _status != null && widget.onEnregistre != null) {
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) widget.onEnregistre!.call();
    }
  }

  Widget _infoRow(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: Colors.black54)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.embedded) ...[
          Text(
            widget.vehicule != null
                ? _t(
                    'Assurance / Vignette — ${widget.vehicule!.nom}',
                    'التأمين / البطاقة الضريبية — ${widget.vehicule!.nom}',
                  )
                : _t('Assurance / Vignette', 'التأمين / البطاقة الضريبية'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            _t(
              'Photographie la carte jaune pour calculer les jours restants.',
              'صوّر البطاقة الصفراء لحساب الأيام المتبقية.',
            ),
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed:
                    _loading ? null : () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.camera_alt),
                label: Text(_t('Caméra', 'الكاميرا')),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: widget.config.primaryColor,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed:
                    _loading ? null : () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: Text(_t('Galerie', 'المعرض')),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (_image != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(_image!, height: 180, fit: BoxFit.cover),
          ),
        const SizedBox(height: 16),
        if (_loading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  if (_retryLabel != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _retryLabel!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.black54, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
          ),
        if (_error != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_error!,
                style: const TextStyle(color: Color(0xFF991B1B))),
          ),
        if (_status != null) ...[
          StatusCard(status: _status!, isAr: widget.isAr),
          const SizedBox(height: 16),
        ],
        if (_info != null &&
            (_info!.compagnie.isNotEmpty ||
                _info!.nom.isNotEmpty ||
                _info!.marque.isNotEmpty))
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_t('Détails', 'التفاصيل'),
                    style:
                        const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 8),
                _infoRow(_t('Compagnie', 'الشركة'), _info!.compagnie),
                _infoRow(_t('Nom', 'الاسم'), _info!.nom),
                _infoRow(_t('Véhicule', 'المركبة'), _info!.marque),
                _infoRow(_t('Police', 'رقم البوليصة'), _info!.police),
                _infoRow(_t('Début', 'تاريخ البداية'), _info!.debut),
              ],
            ),
          ),
      ],
    );

    if (widget.embedded) return content;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: content,
      ),
    );
  }
}
