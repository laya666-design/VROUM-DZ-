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

  const InsuranceScreen({
    super.key,
    required this.config,
    this.vehicule,
    this.isAr = false,
    this.embedded = false,
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

  Future<void> _pickImage(ImageSource source) async {
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
      // 1) OCR local -> fait foi pour le calcul (fonctionne sans internet)
      final rawText = await _ocr.extractText(file);
      final dates = OcrService.extractDates(rawText);
      final expiration = OcrService.mostRecentDate(dates);

      if (expiration != null) {
        _status = ExpiryStatus(expirationDate: expiration);
      } else {
        _error = _t(
          'Aucune date reconnue sur cette photo. Reprends la photo bien '
              'cadrée sur les dates, ou vérifie manuellement.',
          'لم يتم التعرف على أي تاريخ في هذه الصورة. أعد التقاط الصورة مع '
              'تأطير جيد للتواريخ، أو تحقق يدويًا.',
        );
      }

      // 2) Gemini en complément pour les détails (compagnie, nom, marque...)
      try {
        final json = await _gemini.analyzeInsuranceCard(file);
        _info = InsuranceInfo.fromJson(json);
      } catch (_) {
        // Le complément IA est optionnel : l'échec ne bloque pas le calcul.
        _info = InsuranceInfo();
      }

      await _saveToVehicule();
    } catch (e) {
      _error = _t('Erreur de lecture de l\'image : $e', 'خطأ في قراءة الصورة: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
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
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
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
