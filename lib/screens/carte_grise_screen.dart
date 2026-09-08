import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../config/app_config.dart';
import '../services/gemini_service.dart';
import '../services/models.dart';
import '../services/ocr_service.dart';
import '../services/vehicule.dart';
import '../services/vehicule_service.dart';

/// Carte Grise Magic : scanne la carte grise (jaune) algérienne pour en
/// extraire automatiquement le type, l'année, le châssis et la puissance,
/// puis déduire le code moteur et le carburant. Ces infos alimentent
/// ensuite le Scanner IA pièces pour une identification bien plus fiable
/// qu'une simple photo de la pièce seule.
///
/// Deux modes :
/// - Création : [vehicule] est null. Le type ([typeVehicule]) est déjà
///   choisi par l'utilisateur avant d'arriver ici. Le scan crée directement
///   la fiche véhicule (nom = marque + modèle détectés) et appelle
///   [onVehiculeCree] avec le véhicule créé.
/// - Mise à jour : [vehicule] est fourni (ex: re-scanner après changement
///   de véhicule). Le scan met à jour la fiche existante.
class CarteGriseScreen extends StatefulWidget {
  final AppConfig config;
  final Vehicule? vehicule;
  final String typeVehicule;
  final bool isAr;

  /// true quand ce widget est empilé dans la fiche véhicule à 3 sections
  /// plutôt qu'affiché seul dans son propre onglet.
  final bool embedded;

  /// Appelé une fois le véhicule créé (mode création uniquement).
  final void Function(Vehicule)? onVehiculeCree;

  const CarteGriseScreen({
    super.key,
    required this.config,
    this.vehicule,
    this.typeVehicule = TypeVehicule.voiture,
    this.isAr = false,
    this.embedded = false,
    this.onVehiculeCree,
  });

  @override
  State<CarteGriseScreen> createState() => _CarteGriseScreenState();
}

class _CarteGriseScreenState extends State<CarteGriseScreen> {
  final _picker = ImagePicker();
  final _gemini = GeminiService();
  final _ocr = OcrService();

  File? _image;
  bool _loading = false;
  String? _error;
  CarteGriseInfo? _info;

  bool get _modeCreation => widget.vehicule == null;

  String _t(String fr, String ar) => widget.isAr ? ar : fr;

  @override
  void dispose() {
    _ocr.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Si le véhicule a déjà une carte grise enregistrée, on l'affiche
    // directement sans attendre un nouveau scan.
    final v = widget.vehicule;
    if (v != null && v.carteGriseRenseignee) {
      _info = CarteGriseInfo(
        marque: v.marque,
        chassis: v.chassisNumber,
        annee: v.year,
        puissanceFiscale: v.puissanceFiscale,
        immatriculation: v.immatriculation,
        engineCode: v.engineCode,
        fuelType: v.fuelType,
      );
    }
  }

  String _nomDepuis(CarteGriseInfo info) {
    final parts = <String>[];
    if (info.marque.trim().isNotEmpty) parts.add(info.marque.trim());
    final modele = info.modele.trim();
    if (modele.isNotEmpty &&
        modele.toLowerCase() != 'null' &&
        modele.toLowerCase() != info.marque.toLowerCase()) {
      parts.add(modele);
    }
    return parts.join(' ').trim();
  }

  Future<void> _appliquerScan(CarteGriseInfo info) async {
    if (_modeCreation) {
      final nomDetecte = _nomDepuis(info);
      final v = Vehicule(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        nom: nomDetecte.isNotEmpty
            ? nomDetecte
            : (widget.typeVehicule == TypeVehicule.voiture
                ? 'Ma voiture'
                : 'Ma moto'),
        marque: info.marque,
        immatriculation: info.immatriculation,
        type: widget.typeVehicule,
        chassisNumber: info.chassis,
        year: info.annee,
        puissanceFiscale: info.puissanceFiscale,
        engineCode: info.engineCode,
        fuelType: info.fuelType,
      );
      await VehiculeService.add(v);
      widget.onVehiculeCree?.call(v);
      return;
    }

    final v = widget.vehicule!;
    if (info.marque.isNotEmpty) {
      v.marque = info.marque;
      final nomDetecte = _nomDepuis(info);
      if (nomDetecte.isNotEmpty) v.nom = nomDetecte;
    }
    if (info.chassis.isNotEmpty) v.chassisNumber = info.chassis;
    if (info.annee != null) v.year = info.annee;
    if (info.puissanceFiscale.isNotEmpty) {
      v.puissanceFiscale = info.puissanceFiscale;
    }
    if (info.immatriculation.isNotEmpty) {
      v.immatriculation = info.immatriculation;
    }
    if (info.engineCode.isNotEmpty) v.engineCode = info.engineCode;
    if (info.fuelType.isNotEmpty) v.fuelType = info.fuelType;
    await VehiculeService.update(v);
  }

  /// Déduit la marque à partir du préfixe chassis (WMI / code type DZ).
  String? _marqueFromChassis(String chassis) {
    final c = chassis.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (c.length < 3) return null;
    final p3 = c.substring(0, 3);
    final p2 = c.substring(0, 2);
    if (p2 == 'JT' || p3 == 'NCP' || p3 == 'NSP' || p3 == 'NZE' || p3 == 'ZZE') {
      return 'TOYOTA';
    }
    if (p3 == 'VF1') return 'RENAULT';
    if (p3 == 'VF3') return 'PEUGEOT';
    if (p3 == 'VF7') return 'CITROEN';
    if (p2 == 'WV' || p3 == 'WVW' || p3 == 'WVG') return 'VOLKSWAGEN';
    if (p3 == 'WDB' || p3 == 'WDD' || p3 == 'WDC') return 'MERCEDES';
    if (p3 == 'WBA' || p3 == 'WBS') return 'BMW';
    if (p3 == 'KMH' || p3 == 'U5Y' || p3 == 'TMA') return 'HYUNDAI';
    if (p3 == 'U5Z' || p2 == 'KN') return 'KIA';
    if (p3 == 'UU1') return 'DACIA';
    return null;
  }

  /// Secours local : OCR ML Kit + détection marque arabe/latin + WMI chassis.
  Future<CarteGriseInfo?> _fallbackLocal(File file) async {
    try {
      final raw = await _ocr.extractText(file);
      if (raw.trim().isEmpty) return null;
      var marque = OcrService.detectMarqueLocale(raw) ?? '';
      final chassisMatch = RegExp(r'\b([A-HJ-NPR-Z0-9]{11,17})\b')
          .firstMatch(raw.toUpperCase());
      final chassis = chassisMatch?.group(1) ?? '';
      if (marque.isEmpty && chassis.isNotEmpty) {
        marque = _marqueFromChassis(chassis) ?? '';
      }
      if (marque.isEmpty && chassis.isEmpty) return null;
      return CarteGriseInfo(
        marque: marque,
        chassis: chassis,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    setState(() {
      _error = null;
      _info = null;
    });

    // Image plus légère → moins de tokens ITPM Groq (rate limit).
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 55,
      maxWidth: 1280,
    );
    if (picked == null) return;

    final file = File(picked.path);
    setState(() {
      _image = file;
      _loading = true;
    });

    try {
      // OCR local en parallèle : sert de filet de secours (marque/châssis)
      // si Gemini ne trouve rien, mais ne prime plus sur sa lecture de la
      // case الصنف (voir plus bas).
      final local = await _fallbackLocal(file);
      final json = await _gemini.analyzeCarteGrise(file);

      if (json.containsKey('error')) {
        if (local != null && !local.estVide) {
          _info = local;
          await _appliquerScan(local);
          _error = null;
        } else {
          _error = _t('Erreur : ${json['error']}', 'خطأ: ${json['error']}');
        }
      } else {
        var info = CarteGriseInfo.fromJson(json);
        // Gemini (lecture visuelle ciblée de la case الصنف, cf. prompt)
        // fait foi pour la marque : c'est le seul des deux qui "regarde"
        // réellement cette case précise. L'OCR local (ML Kit, texte brut
        // de toute l'image, sans repérage de case) ne sert que de secours
        // quand Gemini n'a rien trouvé — il ne doit jamais écraser une
        // marque déjà lue par Gemini, au risque de retomber sur un
        // mot-clé capté ailleurs sur la page (bug observé : "HYUNDAI"
        // renvoyé sur une carte grise Mercedes).
        final chassisSecours =
            info.chassis.isNotEmpty ? info.chassis : (local?.chassis ?? '');
        if (info.marque.isEmpty && local != null && local.marque.isNotEmpty) {
          info = CarteGriseInfo(
            marque: local.marque,
            modele: info.modele,
            type: info.type,
            annee: info.annee,
            chassis: chassisSecours,
            puissanceFiscale: info.puissanceFiscale,
            immatriculation: info.immatriculation,
            engineCode: info.engineCode,
            fuelType: info.fuelType,
          );
        } else if (info.chassis.isEmpty && chassisSecours.isNotEmpty) {
          info = CarteGriseInfo(
            marque: info.marque,
            modele: info.modele,
            type: info.type,
            annee: info.annee,
            chassis: chassisSecours,
            puissanceFiscale: info.puissanceFiscale,
            immatriculation: info.immatriculation,
            engineCode: info.engineCode,
            fuelType: info.fuelType,
          );
        }
        if (info.estVide) {
          _error = _t(
            'Aucune information reconnue sur cette photo. '
                'Reprends la photo bien cadrée sur le TABLEAU DU BAS '
                '(case الصنف / MARQUE).',
            'لم يتم التعرف على أي معلومة. أعد التقاط الصورة مع تأطير '
                'الجدول السفلي (خانة الصنف / الماركة).',
          );
        } else {
          _info = info;
          await _appliquerScan(info);
        }
      }
    } catch (e) {
      final local = await _fallbackLocal(file);
      if (local != null && !local.estVide) {
        _info = local;
        await _appliquerScan(local);
      } else {
        _error = _t('Erreur d\'analyse : $e', 'خطأ في التحليل: $e');
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
            width: 110,
            child: Text(label,
                style: const TextStyle(fontSize: 13, color: Colors.black54)),
          ),
          Expanded(
            child: Text(value,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
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
            _modeCreation
                ? _t('Scanner la carte grise', 'مسح البطاقة الرمادية')
                : _t(
                    'Carte Grise — ${widget.vehicule!.nom}',
                    'البطاقة الرمادية — ${widget.vehicule!.nom}',
                  ),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            _modeCreation
                ? _t(
                    'Photographie la carte grise : la fiche du véhicule sera '
                        'créée automatiquement.',
                    'صوّر البطاقة الرمادية: سيتم إنشاء بطاقة المركبة تلقائيًا.',
                  )
                : _t(
                    'Photographie la carte grise pour identifier le moteur et '
                        'améliorer la reconnaissance des pièces compatibles.',
                    'صوّر البطاقة الرمادية لتحديد المحرك وتحسين التعرف على '
                        'القطع المتوافقة.',
                  ),
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 4),
          Text(
            _t(
              '⚠️ Cadre bien le TABLEAU DU BAS (marque, type, châssis, '
              'puissance) : c\'est là que se trouvent toutes les infos '
              'utiles, pas seulement le haut avec le nom du propriétaire.',
              '⚠️ أطّر جيدًا الجدول السفلي (الماركة، النوع، رقم الهيكل، '
              'القوة الجبائية): هناك تجد كل المعلومات المفيدة، وليس فقط '
              'الجزء العلوي الذي يحمل اسم المالك.',
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
                label: Text(_t('Prendre Photo', 'التقاط صورة')),
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
        if (_info != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: widget.config.primaryColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: widget.config.primaryColor.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle,
                        color: widget.config.primaryColor, size: 20),
                    const SizedBox(width: 6),
                    Text(
                      _modeCreation
                          ? _t('Véhicule créé', 'تم إنشاء المركبة')
                          : _t('Moteur identifié', 'تم تحديد المحرك'),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _infoRow(_t('Marque', 'الماركة'), _info!.marque),
                _infoRow(_t('Modèle', 'الموديل'), _info!.modele),
                _infoRow(_t('Année', 'السنة'), _info!.annee?.toString() ?? ''),
                _infoRow(_t('Châssis', 'رقم الهيكل'), _info!.chassis),
                _infoRow(_t('Puissance fiscale', 'القوة الجبائية'),
                    _info!.puissanceFiscale),
                _infoRow(_t('Code moteur', 'رمز المحرك'), _info!.engineCode),
                _infoRow(_t('Carburant', 'نوع الوقود'), _info!.fuelType),
                if (_info!.engineCode.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _t(
                        'Code moteur non déduit avec certitude — '
                        'vérifiable sur le carnet d\'entretien.',
                        'لم يتم تحديد رمز المحرك بشكل مؤكد — '
                        'يمكن التحقق منه في دفتر الصيانة.',
                      ),
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
              ],
            ),
          ),
          if (!_modeCreation) ...[
            const SizedBox(height: 12),
            Text(
              _t(
                'Ces infos seront utilisées automatiquement dans le Scanner '
                'IA pièces pour affiner l\'identification.',
                'ستُستخدم هذه المعلومات تلقائيًا في الماسح الذكي للقطع '
                'لتحسين دقة التعرف.',
              ),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ],
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
