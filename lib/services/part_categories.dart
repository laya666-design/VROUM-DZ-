/// Catégories de pièces pour filtrer les demandes côté magasins.
///
/// Un magasin doit cocher au moins une catégorie à l'inscription.
/// Si « Autre » est coché, un champ texte libre est obligatoire.
class PartCategory {
  final String id;
  final String labelFr;
  final String labelAr;

  const PartCategory({
    required this.id,
    required this.labelFr,
    required this.labelAr,
  });
}

const List<PartCategory> kPartCategories = [
  PartCategory(id: 'batterie', labelFr: 'Batterie', labelAr: 'بطارية'),
  PartCategory(id: 'freinage', labelFr: 'Freinage', labelAr: 'فرامل'),
  PartCategory(id: 'filtres', labelFr: 'Filtres', labelAr: 'فلاتر'),
  PartCategory(
      id: 'suspension',
      labelFr: 'Suspension / Direction',
      labelAr: 'تعليق / توجيه'),
  PartCategory(id: 'embrayage', labelFr: 'Embrayage', labelAr: 'قابض'),
  PartCategory(id: 'moteur', labelFr: 'Moteur', labelAr: 'محرك'),
  PartCategory(
      id: 'distribution', labelFr: 'Distribution', labelAr: 'توزيع'),
  PartCategory(
      id: 'electricite',
      labelFr: 'Électricité / Allumage',
      labelAr: 'كهرباء / إشعال'),
  PartCategory(id: 'carrosserie', labelFr: 'Carrosserie', labelAr: 'هيكل'),
  PartCategory(
      id: 'pneus', labelFr: 'Pneus / Jantes', labelAr: 'إطارات / جنوط'),
  PartCategory(
      id: 'huile_lubrifiants',
      labelFr: 'Huile / Lubrifiants',
      labelAr: 'زيت / مواد تشحيم'),
  PartCategory(
      id: 'refroidissement',
      labelFr: 'Refroidissement',
      labelAr: 'تبريد'),
  PartCategory(id: 'echappement', labelFr: 'Échappement', labelAr: 'عادم'),
  PartCategory(
      id: 'accessoires', labelFr: 'Accessoires', labelAr: 'إكسسوارات'),
  PartCategory(id: 'autre', labelFr: 'Autre', labelAr: 'أخرى'),
];

const String kCategorieAutre = 'autre';

/// Détecte automatiquement la catégorie à partir du nom de la pièce.
/// Retourne [kCategorieAutre] si aucune règle ne matche.
String detecterCategorie(String pieceNom) {
  final nom = pieceNom.toLowerCase().trim();
  if (nom.isEmpty) return kCategorieAutre;

  // Batterie
  if (nom.contains('batterie') ||
      nom.contains('batter') ||
      nom.contains('بطارية')) {
    return 'batterie';
  }

  // Freinage
  if (nom.contains('frein') ||
      nom.contains('plaquette') ||
      nom.contains('disque') ||
      nom.contains('etrier') ||
      nom.contains('étrier') ||
      nom.contains('machoire') ||
      nom.contains('mâchoire') ||
      nom.contains('abs') ||
      nom.contains('فرامل')) {
    return 'freinage';
  }

  // Filtres
  if (nom.contains('filtre') || nom.contains('فلتر')) {
    return 'filtres';
  }

  // Suspension / Direction
  if (nom.contains('amortisseur') ||
      nom.contains('ressort') ||
      nom.contains('rotule') ||
      nom.contains('biellette') ||
      nom.contains('triangle') ||
      nom.contains('silentbloc') ||
      nom.contains('silent bloc') ||
      nom.contains('direction') ||
      nom.contains('cremaillere') ||
      nom.contains('crémaillère') ||
      nom.contains('cardan') ||
      nom.contains('تعليق')) {
    return 'suspension';
  }

  // Embrayage
  if (nom.contains('embrayage') ||
      nom.contains('kit emb') ||
      nom.contains('volant moteur') ||
      nom.contains('butée') ||
      nom.contains('butee') ||
      nom.contains('قابض')) {
    return 'embrayage';
  }

  // Distribution
  if (nom.contains('distribution') ||
      nom.contains('courroie') ||
      nom.contains('chaine dist') ||
      nom.contains('chaîne dist') ||
      nom.contains('poulie') ||
      nom.contains('tendeur')) {
    return 'distribution';
  }

  // Refroidissement
  if (nom.contains('radiateur') ||
      nom.contains('thermostat') ||
      nom.contains('ventila') ||
      nom.contains('liquide de refroid') ||
      nom.contains('pompe a eau') ||
      nom.contains('pompe à eau') ||
      nom.contains('تبريد')) {
    return 'refroidissement';
  }

  // Échappement
  if (nom.contains('echappement') ||
      nom.contains('échappement') ||
      nom.contains('pot catalyt') ||
      nom.contains('silencieux') ||
      nom.contains('collecteur') ||
      nom.contains('sonde lambda') ||
      nom.contains('عادم')) {
    return 'echappement';
  }

  // Huile / Lubrifiants
  if (nom.contains('huile') ||
      nom.contains('lubrifiant') ||
      nom.contains('vidange') ||
      nom.contains('زيت')) {
    return 'huile_lubrifiants';
  }

  // Pneus / Jantes
  if (nom.contains('pneu') ||
      nom.contains('jante') ||
      nom.contains('roue') ||
      nom.contains('valve') ||
      nom.contains('إطار')) {
    return 'pneus';
  }

  // Électricité / Allumage
  if (nom.contains('alternateur') ||
      nom.contains('demarreur') ||
      nom.contains('démarreur') ||
      nom.contains('bougie') ||
      nom.contains('bobine') ||
      nom.contains('relais') ||
      nom.contains('fusible') ||
      nom.contains('faisceau') ||
      nom.contains('capteur') ||
      nom.contains('sonde') ||
      nom.contains('allumage') ||
      nom.contains('كهرباء')) {
    return 'electricite';
  }

  // Moteur (après distribution / refroidissement pour éviter les faux positifs)
  if (nom.contains('moteur') ||
      nom.contains('joint de culasse') ||
      nom.contains('culasse') ||
      nom.contains('piston') ||
      nom.contains('turbo') ||
      nom.contains('injecteur') ||
      nom.contains('pompe a injection') ||
      nom.contains('pompe à injection') ||
      nom.contains('support moteur') ||
      nom.contains('محرك')) {
    return 'moteur';
  }

  // Carrosserie
  if (nom.contains('pare-choc') ||
      nom.contains('pare choc') ||
      nom.contains('aile') ||
      nom.contains('capot') ||
      nom.contains('portiere') ||
      nom.contains('portière') ||
      nom.contains('retro') ||
      nom.contains('rétroviseur') ||
      nom.contains('retroviseur') ||
      nom.contains('phare') ||
      nom.contains('feu ') ||
      nom.contains('feux') ||
      nom.contains('optique') ||
      nom.contains('ampoule') ||
      nom.contains('pare-brise') ||
      nom.contains('pare brise') ||
      nom.contains('vitre') ||
      nom.contains('هيكل')) {
    return 'carrosserie';
  }

  // Accessoires
  if (nom.contains('accessoire') ||
      nom.contains('essuie') ||
      nom.contains('balais') ||
      nom.contains('klaxon') ||
      nom.contains('autoradio') ||
      nom.contains('tapis') ||
      nom.contains('couvre') ||
      nom.contains('إكسسوار')) {
    return 'accessoires';
  }

  return kCategorieAutre;
}

String labelCategorie(String id, {bool ar = false}) {
  for (final c in kPartCategories) {
    if (c.id == id) return ar ? c.labelAr : c.labelFr;
  }
  return id;
}
