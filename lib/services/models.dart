class InsuranceInfo {
  final String compagnie;
  final String nom;
  final String marque;
  final String police;
  final String debut;
  final String expirationStr;

  InsuranceInfo({
    this.compagnie = '',
    this.nom = '',
    this.marque = '',
    this.police = '',
    this.debut = '',
    this.expirationStr = '',
  });

  factory InsuranceInfo.fromJson(Map<String, dynamic>? json) {
    if (json == null) return InsuranceInfo();
    return InsuranceInfo(
      compagnie: json['compagnie']?.toString() ?? '',
      nom: json['nom']?.toString() ?? '',
      marque: json['marque']?.toString() ?? '',
      police: json['police']?.toString() ?? '',
      debut: json['debut']?.toString() ?? '',
      expirationStr: json['expiration']?.toString() ?? '',
    );
  }
}

class ControleTechniqueInfo {
  final String centre;
  final String numero;
  final String kilometrage;
  final String dateProchainControle; // format dd/MM/yyyy tel que renvoyé par Gemini

  ControleTechniqueInfo({
    this.centre = '',
    this.numero = '',
    this.kilometrage = '',
    this.dateProchainControle = '',
  });

  factory ControleTechniqueInfo.fromJson(Map<String, dynamic>? json) {
    if (json == null) return ControleTechniqueInfo();
    return ControleTechniqueInfo(
      centre: json['centre']?.toString() ?? '',
      numero: json['numero']?.toString() ?? '',
      kilometrage: json['kilometrage']?.toString() ?? '',
      dateProchainControle:
          json['date_prochain_controle']?.toString() ?? '',
    );
  }

  /// Parse le champ dd/MM/yyyy renvoyé par Gemini, ou null si absent/invalide.
  DateTime? get dateProchainControleParsed {
    final s = dateProchainControle.trim();
    final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(s);
    if (m == null) return null;
    final day = int.tryParse(m.group(1)!);
    final month = int.tryParse(m.group(2)!);
    final year = int.tryParse(m.group(3)!);
    if (day == null || month == null || year == null) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    try {
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }
}

/// Résultat du scan d'une carte grise algérienne (jaune), avec déduction
/// du code moteur / carburant pour alimenter la compatibilité pièces.
class CarteGriseInfo {
  final String marque;
  final String modele;
  final String type; // "type" tel qu'imprimé sur la carte grise
  final int? annee;
  final String chassis;
  final String puissanceFiscale;
  final String immatriculation;
  final String engineCode; // déduit, ex: "K9K"
  final String fuelType; // déduit, ex: "diesel"

  CarteGriseInfo({
    this.marque = '',
    this.modele = '',
    this.type = '',
    this.annee,
    this.chassis = '',
    this.puissanceFiscale = '',
    this.immatriculation = '',
    this.engineCode = '',
    this.fuelType = '',
  });

  /// Nettoie les valeurs JSON null / "null" / "undefined" renvoyées
  /// par le modèle IA (évite le nom affiché "TOYOTA null").
  static String _clean(dynamic v) {
    final s = v?.toString().trim() ?? '';
    if (s.isEmpty) return '';
    final lower = s.toLowerCase();
    if (lower == 'null' || lower == 'undefined' || lower == 'none') return '';
    return s;
  }

  factory CarteGriseInfo.fromJson(Map<String, dynamic>? json) {
    if (json == null) return CarteGriseInfo();
    return CarteGriseInfo(
      marque: _clean(json['marque']).toUpperCase(),
      modele: _clean(json['modele']),
      type: _clean(json['type']),
      annee: int.tryParse(_clean(json['annee'])),
      chassis: _clean(json['chassis']).toUpperCase(),
      puissanceFiscale: _clean(json['puissance_fiscale']),
      immatriculation: _clean(json['immatriculation']),
      engineCode: _clean(json['engine_code']),
      fuelType: _clean(json['fuel_type']),
    );
  }

  bool get estVide =>
      marque.isEmpty && modele.isEmpty && chassis.isEmpty && annee == null;
}

class StoreOffer {
  final String nom;
  final num prix;
  final String tel;
  final String stock;
  final String adresse;

  StoreOffer({
    required this.nom,
    required this.prix,
    this.tel = '',
    this.stock = '',
    this.adresse = '',
  });

  factory StoreOffer.fromJson(Map<String, dynamic> json) {
    return StoreOffer(
      nom: json['nom']?.toString() ?? '',
      prix: (json['prix'] is num) ? json['prix'] as num : 0,
      tel: json['tel']?.toString() ?? '',
      stock: json['stock']?.toString() ?? '',
      adresse: json['adresse']?.toString() ?? '',
    );
  }
}

class CarPartInfo {
  final String nom;
  final String reference;
  final List<String> compatibilite;
  final num prixDa;
  final num prixOrigine;
  final String disponibilite;
  final String etat;
  final String conseils;
  final List<StoreOffer> magasins;

  CarPartInfo({
    this.nom = '',
    this.reference = '',
    this.compatibilite = const [],
    this.prixDa = 0,
    this.prixOrigine = 0,
    this.disponibilite = '',
    this.etat = '',
    this.conseils = '',
    this.magasins = const [],
  });

  factory CarPartInfo.fromJson(Map<String, dynamic>? json) {
    if (json == null) return CarPartInfo();
    return CarPartInfo(
      nom: json['nom']?.toString() ?? '',
      reference: json['reference']?.toString() ?? '',
      compatibilite: (json['compatibilite'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      prixDa: (json['prix_da'] is num) ? json['prix_da'] as num : 0,
      prixOrigine:
          (json['prix_origine'] is num) ? json['prix_origine'] as num : 0,
      disponibilite: json['disponibilite']?.toString() ?? '',
      etat: json['etat']?.toString() ?? '',
      conseils: json['conseils']?.toString() ?? '',
      magasins: (json['magasins'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map((e) => StoreOffer.fromJson(e))
              .toList() ??
          const [],
    );
  }
}
