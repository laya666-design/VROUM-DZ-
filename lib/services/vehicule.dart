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
    DateTime? dateAjout,
  }) : dateAjout = dateAjout ?? DateTime.now();
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
    );
  }

  @override
  void write(BinaryWriter writer, Vehicule obj) {
    writer
      ..writeByte(13)
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
      ..write(obj.type);
  }
}
