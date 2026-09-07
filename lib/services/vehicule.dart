import 'package:hive/hive.dart';

/// Catégories de véhicules gérées par l'app.
class TypeVehicule {
  static const String voiture = 'voiture';
  static const String moto = 'moto';
  static const String scooter = 'scooter';
}

/// Un véhicule géré dans l'app : regroupe assurance/vignette (une seule
/// carte jaune couvre les deux en Algérie) et, à terme, le contrôle
/// technique (Phase 2). Couvre voitures, motos et scooters (même structure,
/// distingués par [type]).
class Vehicule extends HiveObject {
  String id;
  String nom; // ex: "Peugeot 208" ou "Voiture de Sarah"
  String marque;
  String immatriculation;

  /// TypeVehicule.voiture / .moto / .scooter — 'voiture' par défaut pour
  /// rester compatible avec les véhicules déjà enregistrés avant l'ajout
  /// des catégories.
  String type;

  // --- Assurance / Vignette (Phase 1) ---
  DateTime? assuranceExpiration;
  String assuranceCompagnie;
  String assuranceNumeroPolice;
  String assuranceNomAssure;

  // --- Contrôle technique (Phase 2) ---
  DateTime? controleTechniqueExpiration;
  String ctCentre;
  String ctNumero;

  // --- Carte Grise Magic ---
  // Renseignés automatiquement par le scan de la carte grise (ou à la main).
  // Servent de base à l'identification de pièces compatibles dans le volet
  // Pièces (ex: "K9K" + "diesel" -> Gemini identifie la bonne référence
  // plutôt que de deviner à l'aveugle sur la seule photo de la pièce).
  String engineCode; // ex: "K9K" (code moteur Renault/Dacia)
  String fuelType; // ex: "diesel", "essence", "gpl"
  int? year; // année du véhicule (type carte grise)
  int? km; // kilométrage renseigné/estimé
  String chassisNumber; // numéro de châssis (VIN)
  String puissanceFiscale; // puissance fiscale telle qu'imprimée sur la CG

  final DateTime dateAjout;

  Vehicule({
    required this.id,
    required this.nom,
    this.marque = '',
    this.immatriculation = '',
    this.type = TypeVehicule.voiture,
    this.assuranceExpiration,
    this.assuranceCompagnie = '',
    this.assuranceNumeroPolice = '',
    this.assuranceNomAssure = '',
    this.controleTechniqueExpiration,
    this.ctCentre = '',
    this.ctNumero = '',
    this.engineCode = '',
    this.fuelType = '',
    this.year,
    this.km,
    this.chassisNumber = '',
    this.puissanceFiscale = '',
    DateTime? dateAjout,
  }) : dateAjout = dateAjout ?? DateTime.now();

  /// Résumé véhicule injecté dans le prompt du scanner pièces (ex:
  /// "Renault Clio 4 · K9K · diesel"). Inclut le nom du véhicule (modèle
  /// exact, ex: "Clio 4") en plus de la marque : sans le modèle, Gemini
  /// ne peut que deviner une liste de compatibilité générique à partir
  /// de la seule photo, au lieu de l'ancrer sur le véhicule réel de
  /// l'utilisateur.
  String get resumeMoteur {
    final parts = <String>[
      if (nom.trim().isNotEmpty)
        nom.trim()
      else if (marque.trim().isNotEmpty)
        marque.trim(),
      if (engineCode.trim().isNotEmpty) engineCode.trim(),
      if (fuelType.trim().isNotEmpty) fuelType.trim(),
    ];
    return parts.join(' · ');
  }

  bool get carteGriseRenseignee =>
      engineCode.trim().isNotEmpty || chassisNumber.trim().isNotEmpty;
}

/// Adapter Hive écrit à la main (évite la dépendance à build_runner).
/// typeId = 0, réservé pour Vehicule — ne pas réutiliser pour un autre type.
class VehiculeAdapter extends TypeAdapter<Vehicule> {
  @override
  final int typeId = 0;

  @override
  Vehicule read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Vehicule(
      id: fields[0] as String,
      nom: fields[1] as String,
      marque: fields[2] as String? ?? '',
      immatriculation: fields[3] as String? ?? '',
      assuranceExpiration: fields[4] as DateTime?,
      assuranceCompagnie: fields[5] as String? ?? '',
      assuranceNumeroPolice: fields[6] as String? ?? '',
      controleTechniqueExpiration: fields[7] as DateTime?,
      dateAjout: fields[8] as DateTime? ?? DateTime.now(),
      assuranceNomAssure: fields[9] as String? ?? '',
      ctCentre: fields[10] as String? ?? '',
      ctNumero: fields[11] as String? ?? '',
      // Champ ajouté après coup : les véhicules déjà enregistrés n'ont pas
      // ce champ -> on les considère comme des voitures (comportement
      // inchangé pour l'existant).
      type: fields[12] as String? ?? TypeVehicule.voiture,
      // Champs Carte Grise Magic ajoutés après coup : les véhicules déjà
      // enregistrés n'ont pas ces champs -> valeurs vides/null par défaut,
      // sans casser la lecture des données existantes.
      engineCode: fields[13] as String? ?? '',
      fuelType: fields[14] as String? ?? '',
      year: fields[15] as int?,
      km: fields[16] as int?,
      chassisNumber: fields[17] as String? ?? '',
      puissanceFiscale: fields[18] as String? ?? '',
    );
  }

  @override
  void write(BinaryWriter writer, Vehicule obj) {
    writer
      ..writeByte(19)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.nom)
      ..writeByte(2)
      ..write(obj.marque)
      ..writeByte(3)
      ..write(obj.immatriculation)
      ..writeByte(4)
      ..write(obj.assuranceExpiration)
      ..writeByte(5)
      ..write(obj.assuranceCompagnie)
      ..writeByte(6)
      ..write(obj.assuranceNumeroPolice)
      ..writeByte(7)
      ..write(obj.controleTechniqueExpiration)
      ..writeByte(8)
      ..write(obj.dateAjout)
      ..writeByte(9)
      ..write(obj.assuranceNomAssure)
      ..writeByte(10)
      ..write(obj.ctCentre)
      ..writeByte(11)
      ..write(obj.ctNumero)
      ..writeByte(12)
      ..write(obj.type)
      ..writeByte(13)
      ..write(obj.engineCode)
      ..writeByte(14)
      ..write(obj.fuelType)
      ..writeByte(15)
      ..write(obj.year)
      ..writeByte(16)
      ..write(obj.km)
      ..writeByte(17)
      ..write(obj.chassisNumber)
      ..writeByte(18)
      ..write(obj.puissanceFiscale);
  }
}
