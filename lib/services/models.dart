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
      // Corrigés : ces 3 champs lisaient les mauvaises clés JSON
      // ('nom'/'marque'/'police' au lieu de 'nom_assure'/'marque_vehicule'
      // /'numero_police' réellement renvoyées par le prompt Gemini) — ils
      // étaient donc TOUJOURS vides en production, malgré une IA qui
      // répondait correctement.
      nom: json['nom_assure']?.toString() ?? '',
      marque: json['marque_vehicule']?.toString() ?? '',
      police: json['numero_police']?.toString() ?? '',
      debut: json['date_debut']?.toString() ?? '',
      // Corrigé : le prompt Gemini renvoie la clé "date_expiration", pas
      // "expiration" — avec l'ancienne clé ce champ était TOUJOURS vide et
      // la date IA n'était jamais prise en compte dans le calcul du statut.
      expirationStr: json['date_expiration']?.toString() ?? '',
    );
  }

  /// Parse le champ dd/MM/yyyy (ou dd-MM-yyyy / dd.MM.yyyy) renvoyé par
  /// Gemini, ou null si absent/invalide.
  DateTime? get expirationParsed {
    final s = expirationStr.trim();
    if (s.isEmpty || s.toLowerCase() == 'null') return null;
    final m = RegExp(r'(\d{1,2})\s*[\/\.\-]\s*(\d{1,2})\s*[\/\.\-]\s*(\d{2,4})')
        .firstMatch(s);
    if (m == null) return null;
    final day = int.tryParse(m.group(1)!);
    final month = int.tryParse(m.group(2)!);
    var year = int.tryParse(m.group(3)!);
    if (day == null || month == null || year == null) return null;
    if (year < 100) year += 2000;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    if (year < 2000 || year > 2100) return null;
    try {
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
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

  /// Parse le champ dd/MM/yyyy (ou dd-MM-yyyy / dd.MM.yyyy) renvoyé par
  /// Gemini, ou null si absent/invalide.
  DateTime? get dateProchainControleParsed {
    final s = dateProchainControle.trim();
    if (s.isEmpty || s.toLowerCase() == 'null') return null;
    final m = RegExp(r'(\d{1,2})\s*[\/\.\-]\s*(\d{1,2})\s*[\/\.\-]\s*(\d{2,4})')
        .firstMatch(s);
    if (m == null) return null;
    final day = int.tryParse(m.group(1)!);
    final month = int.tryParse(m.group(2)!);
    var year = int.tryParse(m.group(3)!);
    if (day == null || month == null || year == null) return null;
    if (year < 100) year += 2000;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    if (year < 2000 || year > 2100) return null;
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
  final num prixMin;
  final num prixMax;
  final String disponibilite;
  final String etat;
  final String conseils;
  final List<StoreOffer> magasins;

  CarPartInfo({
    this.nom = '',
    this.reference = '',
    this.compatibilite = const [],
    this.prixMin = 0,
    this.prixMax = 0,
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
      // Corrigés : ces clés ne correspondaient pas à celles réellement
      // renvoyées par le prompt Gemini ("prix_dzd_min"/"prix_dzd_max" et
      // "conseil" au singulier) — le prix affiché était donc TOUJOURS
      // "0 DA" et le conseil de montage n'apparaissait jamais, quelle que
      // soit la réponse de l'IA.
      prixMin: (json['prix_dzd_min'] is num) ? json['prix_dzd_min'] as num : 0,
      prixMax: (json['prix_dzd_max'] is num) ? json['prix_dzd_max'] as num : 0,
      disponibilite: json['disponibilite']?.toString() ?? '',
      etat: json['etat']?.toString() ?? '',
      conseils: json['conseil']?.toString() ?? '',
      magasins: (json['magasins'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map((e) => StoreOffer.fromJson(e))
              .toList() ??
          const [],
    );
  }
}
