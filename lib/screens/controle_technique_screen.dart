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

  const ControleTechniqueScreen({
    super.key,
    required this.config,
    this.vehicule,
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
        _error =
            'Aucune date reconnue sur cette photo. Reprends la photo bien '
            'cadrée sur la date du prochain contrôle, ou vérifie manuellement.';
      }

      // 2) Gemini en complément pour les détails (centre, numéro...)
      try {
        final json = await _gemini.analyzeControleTechnique(file);
        _info = ControleTechniqueInfo.fromJson(json);
      } catch (_) {
        // Le complément IA est optionnel : l'échec ne bloque pas le calcul.
        _info = ControleTechniqueInfo();
      }

      await _saveToVehicule();
    } catch (e) {
      _error = 'Erreur de lecture de l\'image : $e';
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
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.vehicule != null
                  ? 'Contrôle technique — ${widget.vehicule!.nom}'
                  : 'Contrôle technique',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            const Text(
              'Photographie l\'attestation de contrôle technique pour '
              'calculer les jours restants avant le prochain passage.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed:
                        _loading ? null : () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Caméra'),
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
                    label: const Text('Galerie'),
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
              StatusCard(status: _status!),
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
                    const Text('Détails',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 8),
                    _infoRow('Centre', _info!.centre),
                    _infoRow('Numéro', _info!.numero),
                    _infoRow('Kilométrage', _info!.kilometrage),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
