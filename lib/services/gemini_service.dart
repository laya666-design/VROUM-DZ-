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
    // Compresse / limite la taille pour rester sous le plafond ITPM Groq
    // (7000 tokens/min en on_demand). Une photo 4K en base64 dépasse
    // facilement 3000 tokens d'entrée à elle seule.
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
      // OTPM on_demand = 1000 ; on reste largement en dessous.
      "max_completion_tokens": reasoningEffort == 'none' ? 600 : 2500,
    };

    // Retry automatique sur rate_limit (ITPM/OTPM) : attend ~16s puis 1 essai.
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await http.post(
          Uri.parse(_workerUrl),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(body),
        );

        final data = jsonDecode(response.body);

        if (data['error'] != null) {
          final err = data['error'].toString();
          if (err.contains('rate_limit') && attempt == 0) {
            lastError = err;
            await Future<void>.delayed(const Duration(seconds: 17));
            continue;
          }
          throw Exception(err);
        }

        final content = data['choices']?[0]?['message']?['content'];
        if (content == null) {
          throw Exception('Reponse vide du serveur');
        }
        return content as String;
      } catch (e) {
        lastError = e;
        final msg = e.toString();
        if (msg.contains('rate_limit') && attempt == 0) {
          await Future<void>.delayed(const Duration(seconds: 17));
          continue;
        }
        rethrow;
      }
    }
    throw Exception(lastError?.toString() ?? 'Erreur inconnue Groq');
  }

  /// Transforme une erreur technique en message lisible pour l'utilisateur.
  String _friendlyOcrError(Object e) {
    final msg = e.toString();
    if (msg.contains('rate_limit') || msg.contains('ITPM') || msg.contains('OTPM')) {
      return 'Serveur momentanément saturé. Attends 20 secondes puis '
          'réessaie avec la même photo.';
    }
    if (msg.contains('<think>') || msg.contains('FormatException')) {
      return 'Analyse impossible (réponse invalide). Réessaie avec une '
          'photo plus nette et bien éclairée.';
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

ATTENTION CRITIQUE SUR LES DATES — ce document contient PLUSIEURS dates :
1. Date d enregistrement / immatriculation du vehicule (ex "12/12/2023" pres
   du numero de registration ou "تاريخ وضع المركبة في السير") → IGNORE-LA.
2. Date de la visite technique qui vient d etre effectuee (champ
   "تاريخ المراقبة" / "DATE" / date du jour du controle en haut) → IGNORE-LA.
3. Date de la PROCHAINE visite periodique (la seule date a retourner) :
   - cherche explicitement la mention "VISITE PERIODIQUE LE" suivie d une date
   - ou "طبيعة وتاريخ المراقبة اللاحقة" / "المراقبة اللاحقة"
   - ou "prochaine visite" / "visite periodique"
   - cette date est generalement en bas du document, dans un encadre ou apres
     un libelle clair "VISITE PERIODIQUE LE dd/mm/yyyy"
   → C EST CETTE DATE UNIQUEMENT qu il faut mettre dans "date_prochain_controle".

Exemple typique : si tu lis "VISITE PERIODIQUE LE 11/12/2025", alors
"date_prochain_controle" = "11/12/2025".

Ne prends JAMAIS la date d enregistrement ni la date de la visite du jour.
Si plusieurs dates futures existent, prends celle explicitement liee a
"VISITE PERIODIQUE" / "المراقبة اللاحقة".

Pour le centre : cherche "مركز المراقبة" / nom de l agence / "Z.A.C" / nom
du controleur ou du centre (ex "MEHDAOUI", "HADJADJ").
Pour le numero : le numero du proces-verbal (ex 6695729) en haut ou bas.

Retourne UNIQUEMENT ce JSON (aucun texte avant/apres, pas de markdown):

{
  "centre": "string ou null",
  "numero": "string ou null",
  "kilometrage": "string ou null",
  "date_prochain_controle": "dd/MM/yyyy ou null",
  "jours_restants": 0
}

REGLE: ne jamais inventer. Si la date "VISITE PERIODIQUE" n est pas lisible,
mets null plutot que de prendre une autre date du document.
''';

      final raw = await _callGroq(prompt, file);
      final json = _parseJson(raw);
      json.remove('magasins');
      return json;
    } catch (e) {
      return {'error': _friendlyOcrError(e)};
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
    final chassis = (json['chassis']?.toString() ?? '')
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (chassis.length < 3) return;
    final prefix3 = chassis.substring(0, 3);
    final prefix2 = chassis.substring(0, 2);
    var marque = (json['marque']?.toString() ?? '').toUpperCase().trim();
    if (marque == 'NULL' || marque == 'UNDEFINED' || marque == 'NONE') {
      marque = '';
      json['marque'] = null;
    }

    String? expected;
    // Toyota : JT... (VIN) ou codes type algériens NCP / NSP / NZE...
    if (prefix2 == 'JT' ||
        prefix3 == 'NCP' ||
        prefix3 == 'NSP' ||
        prefix3 == 'NZE' ||
        prefix3 == 'ZZE' ||
        prefix3 == 'SCP') {
      expected = 'TOYOTA';
    } else if (prefix3 == 'VF1') {
      expected = 'RENAULT';
    } else if (prefix3 == 'VF3') {
      expected = 'PEUGEOT';
    } else if (prefix3 == 'VF7') {
      expected = 'CITROEN';
    } else if (prefix2 == 'WV' || prefix3 == 'WVW' || prefix3 == 'WVG') {
      expected = 'VOLKSWAGEN';
    } else if (prefix3 == 'WDB' || prefix3 == 'WDD' || prefix3 == 'WDC') {
      expected = 'MERCEDES';
    } else if (prefix3 == 'WBA' || prefix3 == 'WBS') {
      expected = 'BMW';
    } else if (prefix3 == 'KMH' || prefix3 == 'U5Y' || prefix3 == 'TMA') {
      expected = 'HYUNDAI';
    } else if (prefix3 == 'U5Z' || prefix2 == 'KN') {
      expected = 'KIA';
    } else if (prefix3 == 'UU1') {
      expected = 'DACIA';
    }

    if (expected != null && (marque.isEmpty || marque != expected)) {
      // Chassis WMI fait foi quand la case marque est illisible / absente
      // ou clairement en conflit.
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
