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

  ControleTechniqueInfo({
    this.centre = '',
    this.numero = '',
    this.kilometrage = '',
  });

  factory ControleTechniqueInfo.fromJson(Map<String, dynamic>? json) {
    if (json == null) return ControleTechniqueInfo();
    return ControleTechniqueInfo(
      centre: json['centre']?.toString() ?? '',
      numero: json['numero']?.toString() ?? '',
      kilometrage: json['kilometrage']?.toString() ?? '',
    );
  }
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
