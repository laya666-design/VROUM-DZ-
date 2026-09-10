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

  /// Catalogue marques → modèles courants sur le marché algérien.
  /// Évite la saisie libre (erreurs OCR) : l'utilisateur choisit dans la liste.
  static const Map<String, List<String>> _catalogueMarques = {
    'PEUGEOT': [
      '206', '207', '208', '301', '307', '308', '2008', '3008', '5008',
      'Partner', 'Expert', 'Boxer', '406', '407', '508',
    ],
    'RENAULT': [
      'Clio', 'Clio 4', 'Clio 5', 'Symbol', 'Megane', 'Megane 3', 'Megane 4',
      'Logan', 'Sandero', 'Kangoo', 'Captur', 'Fluence', 'Kadjar', 'Trafic',
    ],
    'DACIA': [
      'Logan', 'Sandero', 'Duster', 'Dokker', 'Lodgy', 'Spring',
    ],
    'TOYOTA': [
      'Yaris', 'Corolla', 'Auris', 'RAV4', 'Hilux', 'Land Cruiser', 'Avensis',
      'Aygo', 'C-HR', 'Camry', 'Prado',
    ],
    'HYUNDAI': [
      'i10', 'i20', 'i30', 'Accent', 'Elantra', 'Tucson', 'Santa Fe',
      'Creta', 'Kona', 'H1', 'Porter',
    ],
    'KIA': [
      'Picanto', 'Rio', 'Cerato', 'Sportage', 'Sorento', 'Seltos', 'Morning',
      'Carnival', 'Stonic',
    ],
    'VOLKSWAGEN': [
      'Polo', 'Golf', 'Golf 6', 'Golf 7', 'Golf 8', 'Passat', 'Jetta',
      'Tiguan', 'Touareg', 'Caddy', 'Transporter',
    ],
    'CITROEN': [
      'C3', 'C4', 'C5', 'Berlingo', 'C-Elysée', 'C4 Cactus', 'Jumpy', 'Jumper',
    ],
    'NISSAN': [
      'Micra', 'Sunny', 'Qashqai', 'Juke', 'X-Trail', 'Navara', 'Patrol',
      'Note', 'Almera',
    ],
    'FIAT': [
      'Punto', 'Tipo', '500', 'Panda', 'Doblo', 'Fiorino', 'Ducato',
    ],
    'SUZUKI': [
      'Swift', 'Vitara', 'Jimny', 'Alto', 'Dzire', 'S-Presso', 'Ertiga',
    ],
    'CHEVROLET': [
      'Spark', 'Aveo', 'Cruze', 'Captiva', 'N300', 'Optra',
    ],
    'FORD': [
      'Fiesta', 'Focus', 'Fusion', 'Ranger', 'EcoSport', 'Kuga', 'Transit',
    ],
    'MITSUBISHI': [
      'Lancer', 'Pajero', 'L200', 'ASX', 'Outlander', 'Attrage',
    ],
    'MERCEDES': [
      'Classe A', 'Classe B', 'Classe C', 'Classe E', 'GLA', 'GLC', 'Sprinter',
      'Vito',
    ],
    'BMW': [
      'Série 1', 'Série 2', 'Série 3', 'Série 5', 'X1', 'X3', 'X5',
    ],
    'SEAT': ['Ibiza', 'Leon', 'Arona', 'Ateca', 'Toledo'],
    'SKODA': ['Fabia', 'Octavia', 'Rapid', 'Kodiaq', 'Kamiq'],
    'AUDI': ['A3', 'A4', 'A6', 'Q3', 'Q5', 'Q7'],
    'OPEL': ['Corsa', 'Astra', 'Insignia', 'Mokka', 'Combo'],
    'HONDA': ['Civic', 'Jazz', 'CR-V', 'HR-V', 'Accord'],
    'MAZDA': ['2', '3', '6', 'CX-5', 'CX-3'],
    // ——— Marques chinoises (parc algérien récent) ———
    'CHERY': [
      'Tiggo 2', 'Tiggo 3', 'Tiggo 4', 'Tiggo 7', 'Tiggo 8',
      'Arrizo 5', 'Arrizo 6', 'Arrizo 8', 'QQ',
    ],
    'JETOUR': [
      'X70', 'X70 Plus', 'X90', 'X90 Plus', 'Dashing', 'T2',
    ],
    'HAVAL': [
      'H6', 'Jolion', 'H9', 'Dargo', 'H2',
    ],
    'GWM': [
      'Poer', 'Wingle', 'Tank 300', 'Ora',
    ],
    'GEELY': [
      'Coolray', 'Emgrand', 'Azkarra', 'GX3', 'Okavango', 'Geometry',
    ],
    'MG': [
      'ZS', 'HS', 'MG5', 'MG6', 'RX5', 'MG3', 'Marvel R',
    ],
    'BYD': [
      'Atto 3', 'Song Plus', 'Seal', 'Dolphin', 'Han', 'Tang', 'Yuan Plus',
    ],
    'CHANGAN': [
      'CS35', 'CS35 Plus', 'CS55', 'CS75', 'Alsvin', 'UNI-T', 'UNI-V',
    ],
    'JAC': [
      'S3', 'S4', 'S7', 'J7', 'T8', 'X200',
    ],
    'DONGFENG': [
      'AX7', 'Shine', 'Rich', 'Aeolus', 'Fengon',
    ],
    'BAIC': [
      'X25', 'X35', 'X55', 'BJ40', 'Senova',
    ],
    'EXEED': [
      'TXL', 'VX', 'RX', 'LX',
    ],
    'OMODA': [
      'C5', 'E5', 'C7',
    ],
    'JAECOO': [
      'J7', 'J8',
    ],
    'DFSK': [
      'Glory 580', 'Fengon 500', 'K01', 'C37',
    ],
    'FOTON': [
      'Tunland', 'View', 'Aumark', 'Sauvana',
    ],
  };

  static const Map<String, Color> _couleurMarque = {
    'PEUGEOT': Color(0xFF1A1F71),
    'RENAULT': Color(0xFFFFCC33),
    'DACIA': Color(0xFF5B8C2A),
    'TOYOTA': Color(0xFFEB0A1E),
    'HYUNDAI': Color(0xFF002C5F),
    'KIA': Color(0xFFBB162B),
    'VOLKSWAGEN': Color(0xFF001E50),
    'CITROEN': Color(0xFFC4002B),
    'NISSAN': Color(0xFFC3002F),
    'FIAT': Color(0xFFAD1719),
    'SUZUKI': Color(0xFFE30613),
    'CHEVROLET': Color(0xFFD4A017),
    'FORD': Color(0xFF003478),
    'MITSUBISHI': Color(0xFFE60012),
    'MERCEDES': Color(0xFF333333),
    'BMW': Color(0xFF1C69D4),
    'SEAT': Color(0xFFED1C24),
    'SKODA': Color(0xFF4BA82E),
    'AUDI': Color(0xFFBB0A30),
    'OPEL': Color(0xFFF7FF00),
    'HONDA': Color(0xFFCC0000),
    'MAZDA': Color(0xFF101010),
    'CHERY': Color(0xFF1B4F9C),
    'JETOUR': Color(0xFF0B3D91),
    'HAVAL': Color(0xFFC8102E),
    'GWM': Color(0xFF00843D),
    'GEELY': Color(0xFF0033A0),
    'MG': Color(0xFFD5001C),
    'BYD': Color(0xFF1A1A1A),
    'CHANGAN': Color(0xFF0055A5),
    'JAC': Color(0xFF0072BC),
    'DONGFENG': Color(0xFF003DA5),
    'BAIC': Color(0xFF1E3A8A),
    'EXEED': Color(0xFF111827),
    'OMODA': Color(0xFF6B21A8),
    'JAECOO': Color(0xFF14532D),
    'DFSK': Color(0xFFE11D48),
    'FOTON': Color(0xFF1D4ED8),
  };

  /// Logos officiels (ou proches) via Clearbit / domaines connus.
  /// Fallback automatique sur l'initiale colorée si l'image échoue.
  static const Map<String, String> _logoMarqueUrls = {
    'PEUGEOT': 'https://logo.clearbit.com/peugeot.com',
    'RENAULT': 'https://logo.clearbit.com/renault.com',
    'DACIA': 'https://logo.clearbit.com/dacia.com',
    'TOYOTA': 'https://logo.clearbit.com/toyota.com',
    'HYUNDAI': 'https://logo.clearbit.com/hyundai.com',
    'KIA': 'https://logo.clearbit.com/kia.com',
    'VOLKSWAGEN': 'https://logo.clearbit.com/volkswagen.com',
    'CITROEN': 'https://logo.clearbit.com/citroen.com',
    'NISSAN': 'https://logo.clearbit.com/nissan.com',
    'FIAT': 'https://logo.clearbit.com/fiat.com',
    'SUZUKI': 'https://logo.clearbit.com/suzuki.com',
    'CHEVROLET': 'https://logo.clearbit.com/chevrolet.com',
    'FORD': 'https://logo.clearbit.com/ford.com',
    'MITSUBISHI': 'https://logo.clearbit.com/mitsubishi-motors.com',
    'MERCEDES': 'https://logo.clearbit.com/mercedes-benz.com',
    'BMW': 'https://logo.clearbit.com/bmw.com',
    'SEAT': 'https://logo.clearbit.com/seat.com',
    'SKODA': 'https://logo.clearbit.com/skoda-auto.com',
    'AUDI': 'https://logo.clearbit.com/audi.com',
    'OPEL': 'https://logo.clearbit.com/opel.com',
    'HONDA': 'https://logo.clearbit.com/honda.com',
    'MAZDA': 'https://logo.clearbit.com/mazda.com',
    'CHERY': 'https://logo.clearbit.com/cheryinternational.com',
    'JETOUR': 'https://logo.clearbit.com/jetourglobal.com',
    'HAVAL': 'https://logo.clearbit.com/haval.com.cn',
    'GWM': 'https://logo.clearbit.com/gwm.com.cn',
    'GEELY': 'https://logo.clearbit.com/geely.com',
    'MG': 'https://logo.clearbit.com/mg.co.uk',
    'BYD': 'https://logo.clearbit.com/byd.com',
    'CHANGAN': 'https://logo.clearbit.com/changan.com.cn',
    'JAC': 'https://logo.clearbit.com/jac.com.cn',
    'DONGFENG': 'https://logo.clearbit.com/dfmc.com.cn',
    'BAIC': 'https://logo.clearbit.com/baicgroup.com.cn',
    'EXEED': 'https://logo.clearbit.com/exeed.com',
    'OMODA': 'https://logo.clearbit.com/omoda.com',
    'JAECOO': 'https://logo.clearbit.com/jaecoo.com',
    'DFSK': 'https://logo.clearbit.com/dfsk.com',
    'FOTON': 'https://logo.clearbit.com/foton-global.com',
  };

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
    // Normalise la marque OCR vers une clé du catalogue si possible
    // (ex: "Peugeot " → PEUGEOT) pour pré-sélectionner le bon logo.
    final rawMarque = info.marque.trim().toUpperCase();
    String marque = rawMarque;
    if (rawMarque.isNotEmpty && !_catalogueMarques.containsKey(rawMarque)) {
      for (final key in _catalogueMarques.keys) {
        if (rawMarque.contains(key) || key.contains(rawMarque)) {
          marque = key;
          break;
        }
      }
    }
    _marqueCtrl.text = marque;

    // Pré-sélectionne le modèle s'il matche la liste de la marque
    final modeles = _modelesPourMarque(marque);
    final rawModele = info.modele.trim();
    String modele = rawModele;
    if (rawModele.isNotEmpty && modeles.isNotEmpty) {
      final match = modeles.cast<String?>().firstWhere(
            (m) =>
                m!.toLowerCase() == rawModele.toLowerCase() ||
                rawModele.toLowerCase().contains(m.toLowerCase()) ||
                m.toLowerCase().contains(rawModele.toLowerCase()),
            orElse: () => null,
          );
      if (match != null) modele = match;
    }
    _modeleCtrl.text = modele;

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

  Color _colorForMarque(String marque) {
    final key = marque.toUpperCase().trim();
    return _couleurMarque[key] ?? widget.config.primaryColor;
  }

  List<String> _modelesPourMarque(String marque) {
    final key = marque.toUpperCase().trim();
    return List<String>.from(_catalogueMarques[key] ?? const <String>[]);
  }

  Widget _marqueAvatar(String marque, {double size = 36}) {
    final key = marque.toUpperCase().trim();
    final c = _colorForMarque(key);
    final letter = key.isNotEmpty ? key[0] : '?';
    final luminance = c.computeLuminance();
    final fg = luminance > 0.55 ? Colors.black87 : Colors.white;
    final logoUrl = _logoMarqueUrls[key];

    Widget letterFallback() => Text(
          letter,
          style: TextStyle(
            color: fg,
            fontWeight: FontWeight.w900,
            fontSize: size * 0.42,
          ),
        );

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: logoUrl != null ? Colors.white : c,
        borderRadius: BorderRadius.circular(size * 0.28),
        border: logoUrl != null
            ? Border.all(color: Colors.grey.shade200, width: 1)
            : null,
        boxShadow: [
          BoxShadow(
            color: (logoUrl != null ? Colors.black12 : c.withValues(alpha: 0.35)),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: logoUrl != null
          ? Image.network(
              logoUrl,
              width: size * 0.78,
              height: size * 0.78,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => letterFallback(),
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return letterFallback();
              },
            )
          : letterFallback(),
    );
  }

  Future<void> _ouvrirSelecteurMarque() async {
    final marques = _catalogueMarques.keys.toList()..sort();
    final current = _marqueCtrl.text.trim().toUpperCase();
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          builder: (_, scrollCtrl) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                    child: Row(
                      children: [
                        Text(
                          _t('Choisir la marque', 'اختر الماركة'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: GridView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.95,
                      ),
                      itemCount: marques.length,
                      itemBuilder: (_, i) {
                        final m = marques[i];
                        final selected = m == current;
                        return Material(
                          color: selected
                              ? widget.config.primaryColor.withValues(alpha: 0.1)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => Navigator.pop(ctx, m),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: selected
                                      ? widget.config.primaryColor
                                      : Colors.grey.shade200,
                                  width: selected ? 2 : 1,
                                ),
                              ),
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _marqueAvatar(m, size: 42),
                                  const SizedBox(height: 8),
                                  Text(
                                    m,
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: selected
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      color: selected
                                          ? widget.config.primaryColor
                                          : Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (chosen == null || !mounted) return;
    setState(() {
      _marqueCtrl.text = chosen;
      // Reset modèle s'il n'appartient plus à la nouvelle marque
      final modeles = _modelesPourMarque(chosen);
      if (!modeles.contains(_modeleCtrl.text.trim())) {
        _modeleCtrl.clear();
      }
    });
  }

  Future<void> _ouvrirSelecteurModele() async {
    final marque = _marqueCtrl.text.trim().toUpperCase();
    if (marque.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t(
            'Choisis d’abord la marque.',
            'اختر الماركة أولاً.',
          )),
        ),
      );
      return;
    }
    final modeles = _modelesPourMarque(marque);
    if (modeles.isEmpty) {
      // Marque hors catalogue : saisie libre
      return;
    }
    final current = _modeleCtrl.text.trim();
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          builder: (_, scrollCtrl) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                    child: Row(
                      children: [
                        _marqueAvatar(marque, size: 32),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _t('Modèle $marque', 'موديل $marque'),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                      itemCount: modeles.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final m = modeles[i];
                        final selected =
                            m.toLowerCase() == current.toLowerCase();
                        return ListTile(
                          onTap: () => Navigator.pop(ctx, m),
                          leading: Icon(
                            selected
                                ? Icons.check_circle
                                : Icons.directions_car_outlined,
                            color: selected
                                ? widget.config.primaryColor
                                : Colors.grey.shade500,
                          ),
                          title: Text(
                            m,
                            style: TextStyle(
                              fontWeight: selected
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              color: selected
                                  ? widget.config.primaryColor
                                  : Colors.black87,
                            ),
                          ),
                          trailing: selected
                              ? Icon(Icons.done,
                                  color: widget.config.primaryColor)
                              : null,
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (chosen == null || !mounted) return;
    setState(() => _modeleCtrl.text = chosen);
  }

  Widget _pickerField({
    required String label,
    required String value,
    required String placeholder,
    required VoidCallback onTap,
    Widget? leading,
  }) {
    final hasValue = value.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            // Toujours "non vide" pour éviter le chevauchement label/placeholder
            // (bug Flutter InputDecorator + isEmpty + child text).
            isEmpty: false,
            decoration: InputDecoration(
              labelText: label,
              floatingLabelBehavior: FloatingLabelBehavior.always,
              isDense: true,
              contentPadding:
                  const EdgeInsets.fromLTRB(12, 18, 8, 12),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white,
              suffixIcon: const Icon(Icons.expand_more_rounded, size: 22),
            ),
            child: Row(
              children: [
                if (leading != null) ...[
                  leading,
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    hasValue ? value : placeholder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          hasValue ? FontWeight.w600 : FontWeight.w400,
                      color: hasValue ? Colors.black87 : Colors.grey.shade500,
                    ),
                  ),
                ),
              ],
            ),
          ),
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
                  // Mode édition : marque & modèle via menus (évite les
                  // erreurs de saisie / OCR). Autres champs en texte libre.
                  _pickerField(
                    label: _t('Marque', 'الماركة'),
                    value: _marqueCtrl.text,
                    placeholder: _t('Choisir la marque…', 'اختر الماركة…'),
                    onTap: _ouvrirSelecteurMarque,
                    leading: _marqueCtrl.text.trim().isNotEmpty
                        ? _marqueAvatar(_marqueCtrl.text, size: 28)
                        : null,
                  ),
                  _pickerField(
                    label: _t('Modèle', 'الموديل'),
                    value: _modeleCtrl.text,
                    placeholder: _marqueCtrl.text.trim().isEmpty
                        ? _t('D’abord la marque', 'الماركة أولاً')
                        : _t('Choisir le modèle…', 'اختر الموديل…'),
                    onTap: _ouvrirSelecteurModele,
                  ),
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
