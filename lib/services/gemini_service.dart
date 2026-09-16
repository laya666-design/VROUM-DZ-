import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Version Cloudflare Worker + Google Gemini (API compatible OpenAI).
/// La cle API Gemini est protegee cote serveur (Worker), jamais exposee dans l app.
///
/// Modele actuel : gemini-3.6-flash (GA).
/// Historique : Groq qwen preview retire → Gemini 2.5-flash → Gemini 2.5
/// retire pour les nouveaux comptes (404 "no longer available") → 3.6-flash.
/// Ne plus jamais hardcoder un modele "preview" ou une ancienne generation.

class GeminiService {
  static const String _workerUrl =
      'https://tight-smoke-4dfa.laya666.workers.dev';

  Future<String> _callVisionModel(
    String prompt,
    File file, {
    String reasoningEffort = 'none',
  }) async {
    // Gemini 3.6 Flash (remplace 2.5-flash retire par Google — 404 model_not_found).
    // Le raisonnement interne consomme des tokens : on laisse une marge large
    // pour le JSON final (sinon content vide + finish_reason=length).
    final bytes = await file.readAsBytes();
    final base64Image = base64Encode(bytes);

    final body = {
      "model": "gemini-3.6-flash",
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
      "temperature": 0.1,
      "reasoning_effort": reasoningEffort,
      // 2048 : marge pour thinking + JSON carte grise / CT / pieces.
      "max_completion_tokens": 2048,
    };

    // Retry automatique sur limite de debit (HTTP 429) : attend ~16s puis
    // 1 essai. On verifie d abord le code HTTP (fiable quel que soit le
    // fournisseur derriere le Worker), avec un filet de secours sur le
    // texte de l erreur pour les cas ou le 429 n est pas exact.
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await http.post(
          Uri.parse(_workerUrl),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(body),
        );

        final isRateLimited = response.statusCode == 429;
        final decoded = jsonDecode(response.body);
        // Gemini peut renvoyer un objet {error/choices} OU un tableau [{error}]
        final Map<String, dynamic> data;
        if (decoded is List) {
          data = decoded.isNotEmpty && decoded.first is Map
              ? Map<String, dynamic>.from(decoded.first as Map)
              : <String, dynamic>{
                  'error': {'message': 'HTTP ${response.statusCode}'},
                };
        } else if (decoded is Map) {
          data = Map<String, dynamic>.from(decoded);
        } else {
          throw Exception('Reponse serveur invalide (HTTP ${response.statusCode})');
        }

        final errObj = data['error'];
        final errMsg = errObj is Map
            ? (errObj['message']?.toString() ?? errObj.toString())
            : errObj?.toString();
        if (errMsg != null || isRateLimited || response.statusCode >= 400) {
          final err = errMsg ?? 'HTTP ${response.statusCode}';
          if ((isRateLimited || _looksLikeRateLimit(err)) && attempt == 0) {
            lastError = err;
            await Future<void>.delayed(const Duration(seconds: 17));
            continue;
          }
          throw Exception(err);
        }

        final content = data['choices'] is List && (data['choices'] as List).isNotEmpty
            ? (data['choices'] as List).first is Map
                ? ((data['choices'] as List).first as Map)['message'] is Map
                    ? (((data['choices'] as List).first as Map)['message']
                        as Map)['content']
                    : null
                : null
            : null;
        if (content == null || (content is String && content.trim().isEmpty)) {
          final finish = data['choices'] is List && (data['choices'] as List).isNotEmpty
              ? ((data['choices'] as List).first as Map)['finish_reason']?.toString() ?? ''
              : '';
          throw Exception(
            'Reponse vide du serveur'
            '${finish.isNotEmpty ? ' (finish_reason=$finish)' : ''}. '
            'Réessaie avec une photo plus nette.',
          );
        }
        return content as String;
      } catch (e) {
        lastError = e;
        if (_looksLikeRateLimit(e.toString()) && attempt == 0) {
          await Future<void>.delayed(const Duration(seconds: 17));
          continue;
        }
        rethrow;
      }
    }
    throw Exception(lastError?.toString() ?? 'Erreur inconnue du serveur IA');
  }

  /// Vrai si le texte d erreur ressemble a une limite de debit, quel que
  /// soit le fournisseur (Groq: rate_limit/ITPM/OTPM ; Gemini:
  /// RESOURCE_EXHAUSTED/quota).
  bool _looksLikeRateLimit(String msg) {
    final m = msg.toLowerCase();
    return m.contains('rate_limit') ||
        m.contains('resource_exhausted') ||
        m.contains('quota') ||
        m.contains('429') ||
        m.contains('itpm') ||
        m.contains('otpm');
  }

  /// Transforme une erreur technique en message lisible pour l'utilisateur.
  String _friendlyOcrError(Object e) {
    final msg = e.toString();
    if (_looksLikeRateLimit(msg)) {
      return 'Serveur momentanément saturé. Attends 20 secondes puis '
          'réessaie avec la même photo.';
    }
    final lower = msg.toLowerCase();
    if (lower.contains('model_not_found') ||
        lower.contains('no longer available') ||
        lower.contains('not_found')) {
      return 'Modèle IA indisponible côté serveur. Mets à jour l\'app '
          '(gemini-3.6-flash) puis réessaie.';
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

      final raw = await _callVisionModel(prompt, file);
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

REGLE SUR LA DATE D EXPIRATION — ce document contient PLUSIEURS dates
(date d enregistrement/immatriculation, date de la visite du jour, date
de la PROCHAINE visite periodique, parfois tamponnee ou surlignee).
Repere TOUTES les dates lisibles sur le document, au format JJ/MM/AAAA,
quel que soit leur libelle ou emplacement, par exemple pres de :
- "تاريخ وضع المركبة في السير" (immatriculation)
- "تاريخ المراقبة" / date du jour du controle
- "VISITE PERIODIQUE LE", "طبيعة وتاريخ المراقبة اللاحقة",
  "المراقبة اللاحقة", "prochaine visite"
- toute autre date visible sur le document, tamponnee ou surlignee

La date a retourner dans "date_prochain_controle" est TOUJOURS LA PLUS
RECENTE (la plus loin dans le futur) parmi TOUTES ces dates : sur ce
type de document, la date de la prochaine visite periodique est
structurellement posterieure a toutes les autres dates presentes.
Compare les ANNEES en priorite (ex: 2026 est plus recent que 2025) et
relis bien le chiffre de l annee avant de trancher si un reflet ou un
surlignage le rend ambigu — ne te fie pas a la position sur la page,
uniquement a la valeur des dates elles-memes.

Exemple : si tu lis "12/12/2023" (immatriculation) et "VISITE PERIODIQUE
LE 11/12/2026", alors "date_prochain_controle" = "11/12/2026" (la plus
recente des deux).

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

REGLE: ne jamais inventer. Si aucune date n est lisible sur le document,
mets null.
''';

      final raw = await _callVisionModel(prompt, file);
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
  ///
  /// Gère VOITURES et MOTOS/SCOOTERS (GENRE = MOTO / دراجة نارية).
  Future<Map<String, dynamic>> analyzeCarteGrise(File file) async {
    try {
      final prompt = '''
Tu es un expert en cartes grises algeriennes (carte jaune / quittance), VOITURES ET MOTOS.
REGLE CRITIQUE ABSOLUE: Ne jamais inventer une information non visible sur l image.
Si un champ n est pas clairement lisible, mets null. Aucune deduction gratuite.
Ignore le haut du document (nom du proprietaire, adresse, commune, wilaya) - concentre-toi UNIQUEMENT sur le TABLEAU D IDENTIFICATION du bas.

=== GENRE (voiture ou moto) ===
Regarde d abord la case "النوع" / "GENRE" :
- MOTO / دراجة نارية / SCOOTER -> c est une moto. Les marques moto sont differentes (AS MOTORS, YAMAHA, HONDA, BAJAJ, etc.).
- VOITURE / سيارة -> voiture classique.

=== MARQUE = PRIORITE NUMERO 1 (OBLIGATOIRE) ===
Sur TOUTES les cartes grises algeriennes, la marque est dans la case :
  "الصنف" (arabe)  +  sous-libelle francais "MARQUE"
Cette case est a cote de "الطراز" / "TYPE".

PROCEDURE OBLIGATOIRE pour "marque" :
1. Trouve la case "الصنف" / "MARQUE" dans le tableau du bas.
2. Lis EXACTEMENT le texte ecrit DANS cette case (pas ailleurs, pas le haut du document).
3. Si le texte est en ARABE, TRADUIS-LE en majuscules francaises :
   بيجو / بيجوو / بيجوه -> PEUGEOT
   تويوتا / تويو تا -> TOYOTA
   رينو -> RENAULT
   نيسان -> NISSAN
   هيونداي / هيونداى -> HYUNDAI
   كيا -> KIA
   فولكسفاغن / فولكس واجن -> VOLKSWAGEN
   داسيا -> DACIA
   سيتروين -> CITROEN
   فيات -> FIAT
   شيفروليه -> CHEVROLET
   سوزوكي -> SUZUKI
   ميتسوبيشي -> MITSUBISHI
   فورد -> FORD
   اوبل -> OPEL
   مازدا -> MAZDA
   هوندا -> HONDA
   مرسيدس -> MERCEDES
   بي ام دبليو -> BMW
   شيري / شيرى -> CHERY
   جيتور -> JETOUR
   هافال / هافل -> HAVAL
   جيلي / جيلى -> GEELY
   ام جي / إم جي -> MG
   بي واي دي -> BYD
   تشانجان / شانجان -> CHANGAN
   جاك -> JAC
   دونغفنغ -> DONGFENG
   بايك -> BAIC
   اكسيد -> EXEED
   اومودا / أومودا -> OMODA
   جايكو -> JAECOO
4. Si le texte est deja en latin, prends-le tel quel en majuscules.
   Marques VOITURE frequentes : PEUGEOT, TOYOTA, RENAULT, CHERY, JETOUR, HAVAL, GWM, GEELY, MG, BYD, CHANGAN, JAC, DONGFENG, BAIC, EXEED, OMODA, JAECOO, DFSK, FOTON.
   Marques MOTO frequentes en Algerie (tres important) :
   AS MOTORS, AS-MOTORS, ASMOTORS -> "AS MOTORS"
   YAMAHA, HONDA, SUZUKI, KAWASAKI, BAJAJ, TVS, HERO, SYM, KYMCO,
   PIAGGIO, VESPA, CFMOTO, APRILIA, DUCATI, KTM, BMW MOTO.
5. INTERDICTIONS :
   - Ne confonds JAMAIS "بيجو" (PEUGEOT) avec "تويوتا" (TOYOTA).
   - Ne deduis PAS la marque depuis le chassis si la case الصنف est lisible.
   - Ne mets JAMAIS une ville (ANNABA, ALGER, ORAN, CONSTANTINE, SETIF...) comme marque ou chassis.
   - Ne mets JAMAIS TOYOTA si tu vois بيجو (meme partiellement).
6. Si la case الصنف est illisible -> marque = null (ne devine pas).

=== TYPE / MODELE ===
- "الطراز" / TYPE : code type (ex RM125, VF3XG8HHC, NCP92LBEMRK). Mets-le dans "type".
  Pour une moto AS MOTORS, le type est souvent RM125, RM150, etc. -> modele = "RM125".
  IMPORTANT voiture : un code qui commence par VF3 = Peugeot, VF1 = Renault, VF7 = Citroen.
  Si "type" commence par VF3 et que marque est null, alors marque = PEUGEOT.
- "modele" : pour les motos, reprends souvent le TYPE (RM125). Pour les voitures, le nom commercial si visible (Clio, 208...).

=== CHASSIS = PRIORITE NUMERO 2 (NE JAMAIS CONFONDRE AVEC UNE VILLE) ===
Le chassis est dans la case "رقم التسلسلي في الطراز" / "N° DANS LA SERIE DU TYPE" (ou "N° DANS LA SERIE").
Copie EXACTEMENT le code alphanumerique ecrit dans CETTE case (ex: DZKRM12517B, B00245, VF3XG8HHC...).
REGLES STRICTES anti-hallucination :
- INTERDIT de mettre une ville algerienne (ANNABA, ALGER, ALGERIE, ORAN, CONSTANTINE, SETIF, BLIDA, BATNA, BEJAIA, TIZI, SKIKDA, ANNABA, DALGER, DJELFA...).
- INTERDIT de mettre le nom du proprietaire, l adresse, la commune ou la wilaya.
- Si tu lis "ANNABA" ou "ALGER" ou "DALGER", ce n est PAS le chassis -> mets null pour chassis et relis la case N° DANS LA SERIE.
- Un vrai chassis moto/voiture contient des chiffres ET des lettres (souvent 8 a 17 caracteres). Une ville pure = faux.

=== AUTRES CHAMPS ===
- "القوة" / PUISSANCE FISCALE : souvent 3 chiffres (009, 005...).
- Immatriculation, annee (4 chiffres) si visibles dans le tableau.

Indices chassis/type (SEULEMENT si marque encore null apres lecture de الصنف) :
   VF3 -> PEUGEOT | VF1 -> RENAULT | VF7 -> CITROEN
   JT / NCP / NSP / NZE / ZZE / SCP -> TOYOTA
   WVW / WVG -> VOLKSWAGEN | U5Y / KMH -> HYUNDAI | U5Z / KN -> KIA
   DZKRM / RM125 + AS -> AS MOTORS (moto)

engine_code / fuel_type : deduis UNIQUEMENT s ils sont TRES fiables, sinon null.
Pour une moto 125 cm3 essence, fuel_type = "essence" est acceptable ; engine_code reste null si inconnu.

Retourne UNIQUEMENT ce JSON (aucun texte avant/apres, pas de markdown):

{
  "marque": "string ou null (majuscules, ex AS MOTORS ou PEUGEOT)",
  "modele": "string ou null (ex RM125)",
  "type": "string ou null (ex RM125)",
  "annee": "aaaa ou null",
  "chassis": "string ou null (JAMAIS une ville)",
  "puissance_fiscale": "string ou null",
  "immatriculation": "string ou null",
  "engine_code": "ex K9K, 1KR, ou null si incertain",
  "fuel_type": "diesel, essence ou gpl, ou null si incertain"
}
''';

      final raw = await _callVisionModel(prompt, file);
      final json = _parseJson(raw);
      json.remove('magasins');
      // Filet de sécurité : corrige une marque clairement incohérente avec le
      // préfixe chassis (WMI) si le chassis est suffisamment long.
      _correctMarqueFromChassis(json);
      // Empêche définitivement qu'une ville algérienne finisse dans chassis.
      _sanitizeChassis(json);
      return json;
    } catch (e) {
      return {'error': _friendlyOcrError(e)};
    }
  }

  /// Liste des noms de villes / lieux algériens fréquemment hallucinés
  /// à la place du vrai n° de châssis (ANNABA, ALGER, DALGER…).
  static const _villesAlgerie = {
    'ANNABA', 'ALGER', 'ALGERIE', 'ALGERIA', 'ORAN', 'CONSTANTINE',
    'SETIF', 'BLIDA', 'BATNA', 'BEJAIA', 'TIZI', 'SKIKDA', 'DALGER',
    'DJELFA', 'TIARET', 'MOSTAGANEM', 'TEBESSA', 'BISKRA', 'SIDI',
    'BELABBES', 'TLEMCEN', 'BOUMERDES', 'BOUIRA', 'JIJEL', 'GHARDAIA',
    'OUARGLA', 'ADRAR', 'TAMANRASSET', 'ILLIZI', 'TINDOUF', 'NAAMA',
    'ELBAYADH', 'KHENCHELA', 'OUMELBOUAGHI', 'MASCARA', 'RELIZANE',
    'CHLEF', 'AINDEFLA', 'MEDEA', 'TIPAZA', 'MILA',
    'SOUKAHRAS', 'GUELMA', 'ELTARF', 'COMMUNE', 'WILAYA',
  };

  void _sanitizeChassis(Map<String, dynamic> json) {
    final raw = (json['chassis']?.toString() ?? '').trim().toUpperCase();
    if (raw.isEmpty) return;
    final cleaned = raw.replaceAll(RegExp(r'[^A-Z0-9]'), '');
    // Ville pure ou quasi-ville -> null
    if (_villesAlgerie.contains(cleaned) ||
        _villesAlgerie.contains(raw) ||
        (cleaned.length <= 8 &&
            RegExp(r'^[A-Z]+$').hasMatch(cleaned) &&
            !RegExp(r'[0-9]').hasMatch(cleaned))) {
      json['chassis'] = null;
      return;
    }
    // Trop court et uniquement lettres -> suspect
    if (cleaned.length < 5 && !RegExp(r'[0-9]').hasMatch(cleaned)) {
      json['chassis'] = null;
    }
  }

  /// Déduit une marque à partir d'un code type / chassis (préfixe WMI).
  /// Retourne null si le préfixe n'est pas reconnu.
  String? _marqueFromWmiCode(String code) {
    final c = code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (c.length < 2) return null;
    final p3 = c.length >= 3 ? c.substring(0, 3) : c;
    final p2 = c.substring(0, 2);
    // Codes type algériens Peugeot/Renault/Citroën (VF…) — très fiables
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

  /// Corrige la marque en s'appuyant sur type + chassis.
  ///
  /// Règles (alignées sur la case الصنف) :
  /// 1. Un code TYPE commençant par VF3/VF1/VF7 prime TOUJOURS
  ///    (ex. VF3XG8HHC → PEUGEOT même si un chassis JT… a été halluciné).
  /// 2. Le chassis WMI ne remplit la marque QUE si elle est encore vide.
  /// 3. On n'écrase JAMAIS une marque déjà lue (بيجو → PEUGEOT, etc.)
  ///    avec un préfixe JT douteux — bug fréquent observé.
  void _correctMarqueFromChassis(Map<String, dynamic> json) {
    var marque = (json['marque']?.toString() ?? '').toUpperCase().trim();
    if (marque == 'NULL' || marque == 'UNDEFINED' || marque == 'NONE') {
      marque = '';
      json['marque'] = null;
    }
    // Normalise variantes AS MOTORS
    if (marque == 'ASMOTORS' ||
        marque == 'AS-MOTORS' ||
        marque == 'AS MOTOR' ||
        marque == 'AS-MOTOR') {
      marque = 'AS MOTORS';
      json['marque'] = 'AS MOTORS';
    }

    final type = (json['type']?.toString() ?? '')
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final modele = (json['modele']?.toString() ?? '')
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final chassis = (json['chassis']?.toString() ?? '')
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');

    // 1) Codes type algériens VF* (très fiables) — dans type, modele OU chassis
    for (final code in [type, modele, chassis]) {
      if (code.length < 3) continue;
      final p3 = code.substring(0, 3);
      if (p3 == 'VF3') {
        json['marque'] = 'PEUGEOT';
        return;
      }
      if (p3 == 'VF1') {
        json['marque'] = 'RENAULT';
        return;
      }
      if (p3 == 'VF7') {
        json['marque'] = 'CITROEN';
        return;
      }
    }

    // 1b) Moto AS MOTORS : type/chassis DZKRM* ou RM125/RM150…
    final blob = '$type $modele $chassis'.toUpperCase();
    if (marque.isEmpty || marque == 'AS' || marque.startsWith('AS ')) {
      if (blob.contains('DZKRM') ||
          RegExp(r'\bRM[0-9]{2,3}\b').hasMatch(blob) ||
          blob.contains('ASMOTORS') ||
          blob.contains('ASMOTORS') ||
          blob.contains('AS MOTORS')) {
        // Si on a déjà AS MOTORS on garde ; sinon on force si indices clairs
        if (marque.isEmpty || marque == 'AS') {
          json['marque'] = 'AS MOTORS';
          if ((json['modele']?.toString() ?? '').isEmpty &&
              RegExp(r'RM[0-9]{2,3}').hasMatch(blob)) {
            final m = RegExp(r'(RM[0-9]{2,3})').firstMatch(blob);
            if (m != null) json['modele'] = m.group(1);
          }
          return;
        }
      }
    }

    // 2) Marque déjà lue dans الصنف → on ne touche pas
    if (marque.isNotEmpty) return;

    // 3) Marque vide → tenter WMI sur type puis chassis
    for (final code in [type, modele, chassis]) {
      final fromWmi = _marqueFromWmiCode(code);
      if (fromWmi != null) {
        json['marque'] = fromWmi;
        return;
      }
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

      final raw = await _callVisionModel(prompt, file);
      return _parseJson(raw);
    } catch (e) {
      return {'error': _friendlyOcrError(e), 'magasins': []};
    }
  }
}
