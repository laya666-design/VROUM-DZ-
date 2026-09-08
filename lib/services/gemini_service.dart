import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Version Cloudflare Worker + Groq
/// La cle API Groq est protegee cote serveur (Worker), jamais exposee dans l app.

class GeminiService {
  static const String _workerUrl =
      'https://tight-smoke-4dfa.laya666.workers.dev';

  Future<String> _callGroq(
    String prompt,
    File file, {
    String reasoningEffort = 'none',
  }) async {
    final bytes = await file.readAsBytes();
    final base64Image = base64Encode(bytes);

    final body = {
      "model": "qwen/qwen3.6-27b",
      "messages": [
        {
          "role": "user",
          "content": [
            {"type": "text", "text": prompt},
            {
              "type": "image_url",
              "image_url": {"url": "data:image/jpeg;base64,$base64Image"}
            }
          ]
        }
      ],
      "temperature": 0.2,
      "reasoning_effort": reasoningEffort,
      // Le mode reflexion ("default") genere du texte de raisonnement avant
      // le JSON final : il faut assez de tokens pour ne pas couper la
      // reponse avant qu elle n arrive au JSON.
      "max_completion_tokens": reasoningEffort == 'none' ? 1024 : 4096,
    };

    // Relance automatique en cas d erreur temporaire (quota/rate limit
    // Groq depasse, coupure reseau, reponse serveur vide) : jusqu a 3
    // tentatives avec un petit delai croissant, avant d abandonner et de
    // remonter l erreur a l ecran. Avant ce correctif, une seule erreur
    // (ex "rate_limit_exceeded") faisait directement echouer l analyse.
    const maxTentatives = 3;
    Object? derniereErreur;
    for (var tentative = 1; tentative <= maxTentatives; tentative++) {
      try {
        final response = await http.post(
          Uri.parse(_workerUrl),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(body),
        );

        final data = jsonDecode(response.body);

        if (data['error'] != null) {
          throw Exception(data['error'].toString());
        }

        final content = data['choices']?[0]?['message']?['content'];
        if (content == null) {
          throw Exception('Reponse vide du serveur');
        }
        return content as String;
      } catch (e) {
        derniereErreur = e;
        final msg = e.toString().toLowerCase();
        // Erreurs qui ne se resoudront jamais en reessayant (image
        // invalide, prompt refuse...) : pas la peine de perdre du temps.
        final definitivementInutile =
            msg.contains('image') && msg.contains('invalid');
        if (definitivementInutile || tentative == maxTentatives) break;
        await Future.delayed(Duration(milliseconds: 700 * tentative));
      }
    }
    throw derniereErreur ?? Exception('Echec de la requete');
  }

  /// Transforme une erreur technique (JSON invalide, reponse tronquee,
  /// contenant encore un bloc <think> non ferme, etc.) en message
  /// comprehensible pour l utilisateur, plutot que d afficher la
  /// FormatException brute dans l ecran.
  String _friendlyOcrError(Object e) {
    final msg = e.toString();
    if (msg.contains('<think>') || msg.contains('FormatException')) {
      return 'Analyse impossible (reponse invalide). Reessayez avec une '
          'photo plus nette et bien eclairee.';
    }
    return msg;
  }

  Map<String, dynamic> _parseJson(String raw) {
    // Retire un eventuel bloc de raisonnement <think>...</think>
    String cleaned =
        raw.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim();
    cleaned = cleaned.replaceAll('```json', '').replaceAll('```', '').trim();

    try {
      final json = jsonDecode(cleaned) as Map<String, dynamic>;
      json['magasins'] = [];
      return json;
    } catch (_) {
      // Filet de secours: extrait le premier bloc { ... } trouve dans le texte
      final match = RegExp(r'\{[\s\S]*\}').firstMatch(cleaned);
      if (match != null) {
        final json = jsonDecode(match.group(0)!) as Map<String, dynamic>;
        json['magasins'] = [];
        return json;
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> analyzeInsuranceCard(File file) async {
    try {
      final prompt = '''
Tu es un expert assurance auto pour l Algerie.
REGLE CRITIQUE: Ne jamais inventer de nom de magasin, adresse ou telephone.
Analyse cette image de carte jaune assurance auto algerienne.
Retourne UNIQUEMENT ce JSON (aucun texte avant/apres, pas de markdown):

{
  "compagnie": "string ou null",
  "nom_assure": "string ou null",
  "marque_vehicule": "string ou null",
  "numero_police": "string ou null",
  "date_expiration": "dd/MM/yyyy ou null",
  "jours_restants": 0,
  "magasins": []
}

REGLE: magasins doit toujours etre un tableau vide [].
''';

      final raw = await _callGroq(prompt, file);
      return _parseJson(raw);
    } catch (e) {
      return {'error': _friendlyOcrError(e), 'magasins': []};
    }
  }

  Future<Map<String, dynamic>> analyzeControleTechnique(File file) async {
    try {
      final prompt = '''
Tu es un expert controle technique automobile pour l Algerie.
REGLE CRITIQUE: Ne jamais inventer de nom de centre, adresse ou telephone.
Analyse cette image d attestation de controle technique algerien (document
bilingue arabe/francais, souvent intitule "Proces-verbal de controle
technique des vehicules" / "محضر المراقبة التقنية للسيارات" ou "VISITE
PERIODIQUE").

METHODE OBLIGATOIRE POUR LA DATE (ce document contient PLUSIEURS dates,
imprimees ou manuscrites, parfois peu nettes) :
ETAPE 1 — Repere et lis TOUTES les dates presentes sur le document, sans
exception, ou qu elles soient (haut, bas, tableaux, mentions manuscrites en
couleur), et liste-les toutes au format dd/MM/yyyy dans le champ
"toutes_les_dates".
ETAPE 2 — Parmi ces dates, identifie celle qui est la PLUS RECENTE
(chronologiquement la plus loin dans le futur / la plus grande une fois
comparees). C est presque toujours la date de la PROCHAINE visite
periodique (les autres dates du document — immatriculation, visite deja
effectuee — sont forcement plus anciennes qu elle).
ETAPE 3 — Mets cette date la plus recente, et uniquement elle, dans
"date_prochain_controle".

Exemple : si tu lis les dates 12/12/2023, 11/12/2023 et 11/12/2026 sur le
document, alors "toutes_les_dates" = ["12/12/2023", "11/12/2023",
"11/12/2026"] et "date_prochain_controle" = "11/12/2026" (la plus recente
des trois).

Pour le centre : cherche "مركز المراقبة" / nom de l agence / "Z.A.C" / nom
du controleur ou du centre (ex "MEHDAOUI", "HADJADJ").
Pour le numero : le numero du proces-verbal (ex 6695729) en haut ou bas.

Retourne UNIQUEMENT ce JSON (aucun texte avant/apres, pas de markdown):

{
  "toutes_les_dates": ["dd/MM/yyyy", "..."],
  "centre": "string ou null",
  "numero": "string ou null",
  "kilometrage": "string ou null",
  "date_prochain_controle": "dd/MM/yyyy ou null",
  "jours_restants": 0
}

REGLE: ne jamais inventer une date qui n est pas ecrite sur le document. Si
aucune date n est lisible, mets un tableau vide et null.
''';

      final raw = await _callGroq(prompt, file);
      final json = _parseJson(raw);
      json.remove('magasins');
      _appliquerDateLaPlusRecente(json);
      return json;
    } catch (e) {
      return {'error': _friendlyOcrError(e)};
    }
  }

  /// Filet de securite cote code : le modele s est deja trompe plusieurs
  /// fois en indiquant une date qui n etait pas la plus recente malgre la
  /// consigne du prompt. On recalcule ici nous-memes le maximum a partir
  /// de "toutes_les_dates" (celles reellement lues sur le document) et on
  /// ecrase "date_prochain_controle" avec ce resultat, plutot que de faire
  /// une confiance aveugle au choix du modele.
  void _appliquerDateLaPlusRecente(Map<String, dynamic> json) {
    final brutes = json['toutes_les_dates'];
    if (brutes is! List || brutes.isEmpty) return;

    DateTime? maxDate;
    String? maxDateStr;
    for (final d in brutes) {
      final parsed = _parseDateFr(d.toString());
      if (parsed == null) continue;
      if (maxDate == null || parsed.isAfter(maxDate)) {
        maxDate = parsed;
        maxDateStr = d.toString();
      }
    }
    if (maxDateStr != null) {
      json['date_prochain_controle'] = maxDateStr;
      json['jours_restants'] = maxDate!.difference(DateTime.now()).inDays;
    }
  }

  /// Parse une date au format dd/MM/yyyy (ou d/M/yyyy). Retourne null si le
  /// format n est pas reconnu, plutot que de lever une exception.
  DateTime? _parseDateFr(String s) {
    final match =
        RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(s.trim());
    if (match == null) return null;
    final jour = int.tryParse(match.group(1)!);
    final mois = int.tryParse(match.group(2)!);
    final annee = int.tryParse(match.group(3)!);
    if (jour == null || mois == null || annee == null) return null;
    try {
      return DateTime(annee, mois, jour);
    } catch (_) {
      return null;
    }
  }

  /// Analyse une photo de carte grise algérienne (jaune) : extrait les
  /// champs officiels (type, année, châssis, puissance) puis déduit le
  /// code moteur et le carburant pour alimenter la compatibilité pièces
  /// (voir Vehicule.engineCode / fuelType).
  Future<Map<String, dynamic>> analyzeCarteGrise(File file) async {
    try {
      final prompt = '''
Tu es un expert en cartes grises automobiles algeriennes (carte jaune).
REGLE CRITIQUE ABSOLUE: Ne jamais inventer une information non visible sur l image.
Si un champ n est pas clairement lisible, mets null. Aucune deduction gratuite.

Ce document est majoritairement en ARABE. Les cases francaises (MARQUE, TYPE, GENRE...)
sont souvent vides ou minuscules ; la valeur reelle est ecrite en arabe a cote
ou en lettres latines majuscules dans la case de la marque.

PRIORITE ABSOLUE POUR LA MARQUE :
Sur les cartes grises / quittances algeriennes, la marque se trouve dans la
case intitulee "الصنف" (en arabe) avec le sous-libelle francais "MARQUE"
juste en dessous. C est CETTE case-la qu il faut lire en priorite.
(Ne confonds pas avec "العلامة" qui n est pas le champ standard ici.)

1. Localise la case "الصنف" / "MARQUE" dans le tableau d identification
   (souvent a cote de "الطراز" / "TYPE").
2. La valeur est le plus souvent ecrite en ARABE (ex: تويوتا, رينو, بيجو...).
   TRADUIS-LA systematiquement en francais majuscules :
   تويوتا → TOYOTA
   رينو → RENAULT
   بيجو → PEUGEOT
   نيسان → NISSAN
   هيونداي / هيونداى → HYUNDAI
   كيا → KIA
   فولكسفاغن / فولكس واجن → VOLKSWAGEN
   داسيا → DACIA
   سيتروين → CITROEN
   فيات → FIAT
   شيفروليه → CHEVROLET
   سوزوكي → SUZUKI
   ميتسوبيشي → MITSUBISHI
   فورد → FORD
   اوبل → OPEL
   مازدا → MAZDA
   هوندا → HONDA
   مرسيدس → MERCEDES
   بي ام دبليو → BMW
3. Si la case contient deja du texte latin majuscule (TOYOTA, RENAULT...),
   prends-le tel quel.
4. Indices chassis (WMI) en verification secondaire uniquement :
   NCP / JT / JTD / JTDB / JTN → TOYOTA
   VF1 → RENAULT
   VF3 → PEUGEOT
   VF7 → CITROEN
   WVW / WVG → VOLKSWAGEN
   U5Y / KMH → HYUNDAI / KIA
5. Si tu lis clairement "تويوتا" (ou TOYOTA) dans la case الصنف/MARQUE,
   retourne "marque": "TOYOTA". Ne mets JAMAIS RENAULT a la place.
6. Ne jamais inventer une marque si la case est illisible → null.

Autres champs (meme tableau) :
- "الطراز" / TYPE : code type / modele (ex NCP92LBEMRK).
- "القوة" / PUISSANCE : puissance fiscale (ex 005).
- "الطاقة" / ENERGIE : ES-GPL, diesel, essence...
- Chassis / numero de serie du type si present ailleurs.
- Immatriculation (N° D'IMMATRICULATION).
- Annee si visible.

Une fois marque + annee + puissance + chassis connus, deduis engine_code
et fuel_type UNIQUEMENT s ils sont tres fiables pour ce couple marque/modele
algerien. Sinon mets null.

Retourne UNIQUEMENT ce JSON (aucun texte avant/apres, pas de markdown):

{
  "marque": "string ou null (en majuscules francaises, ex TOYOTA)",
  "modele": "string ou null",
  "type": "string ou null",
  "annee": "aaaa ou null",
  "chassis": "string ou null",
  "puissance_fiscale": "string ou null",
  "immatriculation": "string ou null",
  "engine_code": "ex K9K, 1KR, deduit ou null si incertain",
  "fuel_type": "diesel, essence ou gpl, deduit ou null si incertain"
}
''';

      final raw = await _callGroq(prompt, file);
      final json = _parseJson(raw);
      json.remove('magasins');
      // Filet de sécurité : corrige une marque clairement incohérente avec le
      // préfixe chassis (WMI) si le chassis est suffisamment long.
      _correctMarqueFromChassis(json);
      return json;
    } catch (e) {
      return {'error': _friendlyOcrError(e)};
    }
  }

  /// Si le chassis commence par un WMI connu et que la marque renvoyée
  /// contredit ce WMI de façon évidente, on force la marque correcte.
  void _correctMarqueFromChassis(Map<String, dynamic> json) {
    final chassis = (json['chassis']?.toString() ?? '').toUpperCase().trim();
    if (chassis.length < 3) return;
    final prefix = chassis.substring(0, 3);
    final marque = (json['marque']?.toString() ?? '').toUpperCase().trim();

    String? expected;
    // Toyota : JT... (VIN) ou codes type algeriens NCP / NSP / NZE...
    if (prefix.startsWith('JT') ||
        prefix == 'JTD' ||
        prefix.startsWith('JTN') ||
        prefix == 'NCP' ||
        prefix == 'NSP' ||
        prefix == 'NZE' ||
        prefix == 'ZZE') {
      expected = 'TOYOTA';
    } else if (prefix == 'VF1') {
      expected = 'RENAULT';
    } else if (prefix == 'VF3') {
      expected = 'PEUGEOT';
    } else if (prefix == 'VF7') {
      expected = 'CITROEN';
    } else if (prefix.startsWith('WV')) {
      expected = 'VOLKSWAGEN';
    }

    if (expected != null && marque.isNotEmpty && marque != expected) {
      // Conflit clair → on fait confiance au chassis (plus fiable que l'OCR
      // de la case marque quand la photo est floue).
      json['marque'] = expected;
    } else if (expected != null && marque.isEmpty) {
      json['marque'] = expected;
    }
  }

  /// [vehicleContext] optionnel : résumé véhicule (ex: "Renault Clio 4 · K9K
  /// · diesel") issu de la carte grise scannée. Quand renseigné, Gemini
  /// identifie la piece en connaissant deja le moteur/la motorisation
  /// au lieu de deviner uniquement sur la photo — moins d ambiguite sur
  /// la reference et la compatibilite.
  Future<Map<String, dynamic>> analyzeCarPart(
    File file, {
    String vehicleContext = '',
  }) async {
    try {
      final contexteVehicule = vehicleContext.trim().isEmpty
          ? ''
          : '''
Contexte vehicule connu (issu de la carte grise scannee par l utilisateur,
fiable, ne pas ignorer) : $vehicleContext
Ce vehicule EXACT doit apparaitre en PREMIER dans "compatibilite", avec son
nom complet tel que donne ci-dessus (ex: si le contexte est "Renault Clio 4",
la liste doit commencer par "Renault Clio 4", jamais un autre modele a la
place). N ajoute d autres modeles compatibles qu apres celui-ci, et
seulement s ils partagent vraiment la meme piece (meme plateforme/moteur) —
n invente pas une liste generique de modeles de la meme marque.
''';

      final prompt = '''
Tu es un expert pieces auto pour l Algerie (Annaba).
REGLE CRITIQUE: Ne jamais inventer de nom de magasin, adresse ou telephone.
Identifie la piece auto sur la photo pour le marche Algerien.
$contexteVehicule
Retourne UNIQUEMENT ce JSON (aucun texte avant/apres, pas de markdown):

{
  "nom": "nom exact piece",
  "reference": "reference possible ou null",
  "compatibilite": ["Clio 4", "Symbol", "etc"],
  "prix_dzd_min": 0,
  "prix_dzd_max": 0,
  "conseil": "conseil montage court",
  "magasins": []
}

REGLE CRITIQUE: magasins = [] toujours vide. Ne jamais inventer de telephone.
''';

      final raw = await _callGroq(prompt, file);
      return _parseJson(raw);
    } catch (e) {
      return {'error': _friendlyOcrError(e), 'magasins': []};
    }
  }
}
