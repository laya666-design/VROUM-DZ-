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

class ControleTechniqueScreen extends StatefulWidget {
  final AppConfig config;
  final Vehicule? vehicule;
  final bool isAr;

  /// true quand ce widget est empilé dans la fiche véhicule à 3 sections
  /// (Carte Grise / Assurance / Contrôle technique) plutôt qu'affiché seul
  /// dans son propre onglet : supprime le titre et le SafeArea/scroll
  /// propres, qui sont alors gérés par la fiche véhicule englobante.
  final bool embedded;

  const ControleTechniqueScreen({
    super.key,
    required this.config,
    this.vehicule,
    this.isAr = false,
    this.embedded = false,
  });

  @override
  State<ControleTechniqueScreen> createState() =>
      _ControleTechniqueScreenState();
}

class _ControleTechniqueScreenState extends State<ControleTechniqueScreen> {
  final _picker = ImagePicker();
  final _ocr = OcrService();
  final _gemini = GeminiService();

  File? _image;
  bool _loading = false;
  String? _error;

  ExpiryStatus? _status; // calculé localement via OCR -> fait foi
  ControleTechniqueInfo? _info; // détails structurés via Gemini -> complément

  String _t(String fr, String ar) => widget.isAr ? ar : fr;

  @override
  void initState() {
    super.initState();
    final v = widget.vehicule;
    if (v?.controleTechniqueExpiration != null) {
      _status = ExpiryStatus(expirationDate: v!.controleTechniqueExpiration!);
      _info = ControleTechniqueInfo(centre: v.ctCentre, numero: v.ctNumero);
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
    v.controleTechniqueExpiration = _status!.expirationDate;
    if (_info != null) {
      if (_info!.centre.isNotEmpty) v.ctCentre = _info!.centre;
      if (_info!.numero.isNotEmpty) v.ctNumero = _info!.numero;
    }
    await VehiculeService.update(v);
    await NotificationService.scheduleExpiryReminders(
      vehiculeId: v.id,
      typeRappel: 'ct',
      titre: v.nom,
      libelleDocument: 'Contrôle technique',
      expiration: v.controleTechniqueExpiration!,
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    setState(() {
      _error = null;
      _status = null;
      _info = null;
    });

    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 70,
      maxWidth: 1600,
    );
    if (picked == null) return;

    final file = File(picked.path);
    setState(() {
      _image = file;
      _loading = true;
    });

    try {
      // Règle métier CT : extraire TOUTES les dates + motifs VISITE
      // PERIODIQUE, prendre la plus récente de l'ensemble.
      // Gemini ne sert qu'au complément (centre, numéro, km).
      final rawText = await _ocr.extractText(file);
      final expiration = OcrService.extractDateVisitePeriodique(rawText);

      ControleTechniqueInfo info = ControleTechniqueInfo();
      try {
        final json = await _gemini.analyzeControleTechnique(file);
        info = ControleTechniqueInfo.fromJson(json);
      } catch (_) {
        // Complément IA optionnel.
      }
      _info = info;

      if (expiration != null) {
        _status = ExpiryStatus(expirationDate: expiration);
      } else {
        // Dernier recours : date renvoyée par Gemini si l'OCR n'a rien vu.
        final fromAi = info.dateProchainControleParsed;
        if (fromAi != null) {
          _status = ExpiryStatus(expirationDate: fromAi);
        } else {
          _error = _t(
            'Aucune date reconnue sur cette photo. Cadre bien tout le '
                'document (surtout la zone VISITE PERIODIQUE), ou vérifie '
                'manuellement.',
            'لم يتم التعرف على أي تاريخ في هذه الصورة. أطّر الوثيقة كاملةً '
                '(خاصة منطقة الزيارة الدورية)، أو تحقق يدويًا.',
          );
        }
      }

      try {
        await _saveToVehicule();
      } catch (_) {
        // Rappels locaux (exact alarms) ne doivent pas masquer un OCR réussi.
      }
    } catch (e) {
      final msg = e.toString();
      if (!msg.contains('exact_alarms') && !msg.contains('Exact alarms')) {
        _error = _t(
          'Erreur de lecture de l\'image. Reprends la photo bien cadrée.',
          'خطأ في قراءة الصورة. أعد التقاط الصورة بإطار جيد.',
        );
      }
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
                style:
                    const TextStyle(fontSize: 13, color: Colors.black54)),
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
                    'Contrôle technique — ${widget.vehicule!.nom}',
                    'الفحص التقني — ${widget.vehicule!.nom}',
                  )
                : _t('Contrôle technique', 'الفحص التقني'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            _t(
              'Photographie l\'attestation de contrôle technique pour '
                  'calculer les jours restants avant le prochain passage.',
              'صوّر شهادة الفحص التقني لحساب الأيام المتبقية قبل الموعد القادم.',
            ),
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 4),
          Text(
            _t(
              '⚠️ Cadre bien TOUT le document, y compris la case en bas de '
                  'page avec la date de la PROCHAINE visite périodique — pas '
                  'seulement le tableau du haut.',
              '⚠️ أطّر الوثيقة بالكامل، بما في ذلك الخانة أسفل الصفحة التي '
                  'تحمل تاريخ الزيارة الدورية القادمة — وليس فقط الجدول '
                  'العلوي.',
            ),
            style: const TextStyle(
                color: Colors.black54,
                fontSize: 12,
                fontStyle: FontStyle.italic),
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
            (_info!.centre.isNotEmpty ||
                _info!.numero.isNotEmpty ||
                _info!.kilometrage.isNotEmpty))
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
                _infoRow(_t('Centre', 'المركز'), _info!.centre),
                _infoRow(_t('Numéro', 'الرقم'), _info!.numero),
                _infoRow(_t('Kilométrage', 'عدد الكيلومترات'), _info!.kilometrage),
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
