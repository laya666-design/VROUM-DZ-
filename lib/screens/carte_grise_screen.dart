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
  /// true une fois que l'utilisateur a explicitement validé le scan
  /// (évite d'enregistrer des erreurs OCR/IA sans relecture).
  bool _confirmed = false;

  // Contrôleurs pour permettre la correction manuelle avant enregistrement
  final _marqueCtrl = TextEditingController();
  final _modeleCtrl = TextEditingController();
  final _anneeCtrl = TextEditingController();
  final _chassisCtrl = TextEditingController();
  final _puissanceCtrl = TextEditingController();
  final _immatCtrl = TextEditingController();
  final _engineCtrl = TextEditingController();
  final _fuelCtrl = TextEditingController();

  bool get _modeCreation => widget.vehicule == null;

  String _t(String fr, String ar) => widget.isAr ? ar : fr;

  @override
  void dispose() {
    _ocr.dispose();
    _marqueCtrl.dispose();
    _modeleCtrl.dispose();
    _anneeCtrl.dispose();
    _chassisCtrl.dispose();
    _puissanceCtrl.dispose();
    _immatCtrl.dispose();
    _engineCtrl.dispose();
    _fuelCtrl.dispose();
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
      _fillControllers(_info!);
      _confirmed = true;
    }
  }

  void _fillControllers(CarteGriseInfo info) {
    _marqueCtrl.text = info.marque;
    _modeleCtrl.text = info.modele;
    _anneeCtrl.text = info.annee?.toString() ?? '';
    _chassisCtrl.text = info.chassis;
    _puissanceCtrl.text = info.puissanceFiscale;
    _immatCtrl.text = info.immatriculation;
    _engineCtrl.text = info.engineCode;
    _fuelCtrl.text = info.fuelType;
  }

  CarteGriseInfo _infoFromControllers() {
    return CarteGriseInfo(
      marque: _marqueCtrl.text.trim().toUpperCase(),
      modele: _modeleCtrl.text.trim(),
      annee: int.tryParse(_anneeCtrl.text.trim()),
      chassis: _chassisCtrl.text.trim().toUpperCase(),
      puissanceFiscale: _puissanceCtrl.text.trim(),
      immatriculation: _immatCtrl.text.trim(),
      engineCode: _engineCtrl.text.trim(),
      fuelType: _fuelCtrl.text.trim(),
    );
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

  /// Déduit la marque à partir d'un code type / chassis (WMI).
  /// VF3/VF1/VF7 (codes type algériens) sont prioritaires et très fiables.
  String? _marqueFromChassis(String chassis) {
    final c = chassis.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (c.length < 2) return null;
    final p3 = c.length >= 3 ? c.substring(0, 3) : c;
    final p2 = c.substring(0, 2);
    // Codes type algériens — fiables même sur 8-12 caractères (VF3XG8HHC)
    if (p3 == 'VF3') return 'PEUGEOT';
    if (p3 == 'VF1') return 'RENAULT';
    if (p3 == 'VF7') return 'CITROEN';
    if (p2 == 'JT' ||
        p3 == 'NCP' ||
        p3 == 'NSP' ||
        p3 == 'NZE' ||
        p3 == 'ZZE' ||
        p3 == 'SCP') {
      return 'TOYOTA';
    }
    if (p2 == 'WV' || p3 == 'WVW' || p3 == 'WVG') return 'VOLKSWAGEN';
    if (p3 == 'WDB' || p3 == 'WDD' || p3 == 'WDC') return 'MERCEDES';
    if (p3 == 'WBA' || p3 == 'WBS') return 'BMW';
    if (p3 == 'KMH' || p3 == 'U5Y' || p3 == 'TMA') return 'HYUNDAI';
    if (p3 == 'U5Z' || p2 == 'KN') return 'KIA';
    if (p3 == 'UU1') return 'DACIA';
    return null;
  }

  /// Cherche d'abord un code VF* (Peugeot/Renault/Citroën) dans le texte OCR,
  /// sinon le premier code alphanumérique plausible.
  String _extractBestChassisOrType(String raw) {
    final upper = raw.toUpperCase();
    // Priorité : codes type algériens VF1/VF3/VF7 (ex. VF3XG8HHC)
    final vf = RegExp(r'\b(VF[137][A-HJ-NPR-Z0-9]{4,14})\b').firstMatch(upper);
    if (vf != null) return vf.group(1)!;
    final any = RegExp(r'\b([A-HJ-NPR-Z0-9]{6,17})\b').firstMatch(upper);
    return any?.group(1) ?? '';
  }

  /// Secours local : OCR ML Kit + détection marque arabe/latin + WMI.
  /// La marque lue (arabe/latin) prime ; le WMI ne sert que si marque vide,
  /// sauf VF3/VF1/VF7 qui corrigent une confusion بيجو ↔ تويوتا.
  Future<CarteGriseInfo?> _fallbackLocal(File file) async {
    try {
      final raw = await _ocr.extractText(file);
      if (raw.trim().isEmpty) return null;
      var marque = OcrService.detectMarqueLocale(raw) ?? '';
      final chassis = _extractBestChassisOrType(raw);
      final fromWmi = chassis.isNotEmpty ? _marqueFromChassis(chassis) : null;

      // VF3/VF1/VF7 (code type clair) corrigent toujours une mauvaise marque
      if (fromWmi == 'PEUGEOT' ||
          fromWmi == 'RENAULT' ||
          fromWmi == 'CITROEN') {
        marque = fromWmi!;
      } else if (marque.isEmpty && fromWmi != null) {
        marque = fromWmi;
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
      _confirmed = false;
    });

    // Qualité plus élevée = texte arabe + petits chiffres (puissance,
    // année, châssis) bien plus lisibles pour le modèle vision.
    // 85 / 1600 reste raisonnable pour les tokens Groq.
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (picked == null) return;

    final file = File(picked.path);
    setState(() {
      _image = file;
      _loading = true;
    });

    try {
      // OCR local en parallèle : sert de filet de secours (marque/châssis)
      // si le modèle vision ne trouve rien.
      final local = await _fallbackLocal(file);
      final json = await _gemini.analyzeCarteGrise(file);

      if (json.containsKey('error')) {
        if (local != null && !local.estVide) {
          _info = local;
          _fillControllers(local);
          _error = null;
        } else {
          _error = _t('Erreur : ${json['error']}', 'خطأ: ${json['error']}');
        }
      } else {
        var info = CarteGriseInfo.fromJson(json);
        // Le modèle vision (lecture ciblée de la case الصنف) fait foi pour
        // la marque. L'OCR local ne sert que de secours quand la marque
        // est vide — il ne doit jamais écraser une marque déjà lue
        // (bug observé : "HYUNDAI" renvoyé sur une Mercedes).
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
        // Filet de sécurité : priorité à la case الصنف (marque déjà lue).
        // On ne force via WMI QUE si :
        //  - un code TYPE VF3/VF1/VF7 est présent (très fiable sur docs DZ), ou
        //  - la marque est encore vide.
        // On n'écrase JAMAIS PEUGEOT/RENAULT… avec un JT… potentiellement
        // halluciné (bug fréquent : بيجو → TOYOTA via faux chassis JTD…).
        final typeCode = info.type
            .toUpperCase()
            .replaceAll(RegExp(r'[^A-Z0-9]'), '');
        final chassisForWmi = chassisSecours.isNotEmpty
            ? chassisSecours
            : info.chassis;
        String? forcedMarque;
        for (final code in [typeCode, chassisForWmi, info.modele]) {
          final c = code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
          if (c.length >= 3) {
            final p3 = c.substring(0, 3);
            if (p3 == 'VF3') {
              forcedMarque = 'PEUGEOT';
              break;
            }
            if (p3 == 'VF1') {
              forcedMarque = 'RENAULT';
              break;
            }
            if (p3 == 'VF7') {
              forcedMarque = 'CITROEN';
              break;
            }
          }
        }
        if (forcedMarque == null && info.marque.isEmpty && chassisForWmi.length >= 6) {
          forcedMarque = _marqueFromChassis(chassisForWmi);
        }
        if (forcedMarque != null &&
            forcedMarque.isNotEmpty &&
            info.marque.toUpperCase() != forcedMarque) {
          info = CarteGriseInfo(
            marque: forcedMarque,
            modele: info.modele,
            type: info.type,
            annee: info.annee,
            chassis: chassisForWmi.isNotEmpty ? chassisForWmi : info.chassis,
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
          // On n'enregistre PAS encore : l'utilisateur doit confirmer
          // (et peut corriger) les champs extraits.
          _info = info;
          _fillControllers(info);
        }
      }
    } catch (e) {
      final local = await _fallbackLocal(file);
      if (local != null && !local.estVide) {
        _info = local;
        _fillControllers(local);
      } else {
        _error = _t('Erreur d\'analyse : $e', 'خطأ في التحليل: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmAndSave() async {
    final info = _infoFromControllers();
    if (info.estVide) {
      setState(() {
        _error = _t(
          'Renseigne au moins la marque ou le châssis.',
          'أدخل على الأقل الماركة أو رقم الهيكل.',
        );
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _appliquerScan(info);
      if (mounted) {
        setState(() {
          _info = info;
          _confirmed = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _t('Erreur d\'enregistrement : $e', 'خطأ في الحفظ: $e');
        });
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

  Widget _editField(String label, TextEditingController ctrl,
      {TextInputType keyboard = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: ctrl,
        keyboardType: keyboard,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          filled: true,
          fillColor: Colors.white,
        ),
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
                    Icon(
                      _confirmed ? Icons.check_circle : Icons.edit_note,
                      color: widget.config.primaryColor,
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _confirmed
                            ? (_modeCreation
                                ? _t('Véhicule créé', 'تم إنشاء المركبة')
                                : _t('Moteur identifié', 'تم تحديد المحرك'))
                            : _t(
                                'Vérifie et corrige si besoin',
                                'تحقق وصحح إذا لزم الأمر',
                              ),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_confirmed) ...[
                  // Mode lecture seule après validation
                  _infoRow(_t('Marque', 'الماركة'), _info!.marque),
                  _infoRow(_t('Modèle', 'الموديل'), _info!.modele),
                  _infoRow(
                      _t('Année', 'السنة'), _info!.annee?.toString() ?? ''),
                  _infoRow(_t('Châssis', 'رقم الهيكل'), _info!.chassis),
                  _infoRow(_t('Puissance fiscale', 'القوة الجبائية'),
                      _info!.puissanceFiscale),
                  _infoRow(
                      _t('Code moteur', 'رمز المحرك'), _info!.engineCode),
                  _infoRow(_t('Carburant', 'نوع الوقود'), _info!.fuelType),
                ] else ...[
                  // Mode édition : l'utilisateur peut corriger les erreurs IA
                  _editField(_t('Marque', 'الماركة'), _marqueCtrl),
                  _editField(_t('Modèle', 'الموديل'), _modeleCtrl),
                  _editField(_t('Année', 'السنة'), _anneeCtrl,
                      keyboard: TextInputType.number),
                  _editField(_t('Châssis', 'رقم الهيكل'), _chassisCtrl),
                  _editField(
                      _t('Puissance fiscale', 'القوة الجبائية'), _puissanceCtrl),
                  _editField(_t('Immatriculation', 'رقم التسجيل'), _immatCtrl),
                  _editField(_t('Code moteur', 'رمز المحرك'), _engineCtrl),
                  _editField(_t('Carburant', 'نوع الوقود'), _fuelCtrl),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _loading ? null : _confirmAndSave,
                      icon: const Icon(Icons.save),
                      label: Text(_t(
                        'Confirmer et enregistrer',
                        'تأكيد وحفظ',
                      )),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.config.primaryColor,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _t(
                      'Corrige les champs erronés avant de valider. '
                      'La qualité de la photo a été augmentée pour réduire les erreurs.',
                      'صحح الحقول الخاطئة قبل التأكيد. '
                      'تم رفع جودة الصورة لتقليل الأخطاء.',
                    ),
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
                if (_confirmed && _info!.engineCode.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _t(
                        'Code moteur non déduit avec certitude — '
                        'vérifiable sur le carnet d\'entretien.',
                        'لم يتم تحديد رمز المحرك بشكل مؤكد — '
                        'يمكن التحقق منه في دفتر الصيانة.',
                      ),
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black54),
                    ),
                  ),
              ],
            ),
          ),
          if (_confirmed && !_modeCreation) ...[
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
