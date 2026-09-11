import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../services/ocr_service.dart';
import '../services/vehicule.dart';
import '../services/vehicule_service.dart';
import '../widgets/ad_banner.dart';
import '../widgets/screen_background.dart';
import 'ajouter_vehicule_flow_screen.dart';
import 'carte_grise_screen.dart';
import 'controle_technique_screen.dart';
import 'insurance_screen.dart';
import 'rappels_screen.dart';

class VehiclesScreen extends StatefulWidget {
  final AppConfig config;
  final bool isAr;

  /// Catégories affichées dans cette rubrique. ex: [TypeVehicule.voiture]
  /// pour la rubrique "Véhicules", ou [TypeVehicule.moto,
  /// TypeVehicule.scooter] pour la rubrique "Motos & scooters".
  final List<String> types;

  final String titre;
  final String titreAr;
  final String sousTitre;
  final String sousTitreAr;
  final IconData iconePrincipale;
  final String labelAjout;
  final String labelAjoutAr;
  final String labelVide;
  final String labelVideAr;

  const VehiclesScreen({
    super.key,
    required this.config,
    this.isAr = false,
    this.types = const [TypeVehicule.voiture],
    this.titre = 'Mes véhicules',
    this.titreAr = 'سياراتي',
    this.sousTitre = 'Scanne assurance & CT — rappels avant expiration.',
    this.sousTitreAr = 'امسح التأمين والفحص — تذكيرات قبل الانتهاء.',
    this.iconePrincipale = Icons.directions_car,
    this.labelAjout = 'Ajouter un véhicule',
    this.labelAjoutAr = 'إضافة سيارة',
    this.labelVide = 'Aucun véhicule pour le moment',
    this.labelVideAr = 'لا توجد سيارة حتى الآن',
  });

  @override
  State<VehiclesScreen> createState() => _VehiclesScreenState();
}

class _VehiclesScreenState extends State<VehiclesScreen> {
  List<Vehicule> _vehicules = [];

  bool get _ar => widget.isAr;
  String get _titre => _ar ? widget.titreAr : widget.titre;
  String get _sousTitre => _ar ? widget.sousTitreAr : widget.sousTitre;
  String get _labelAjout => _ar ? widget.labelAjoutAr : widget.labelAjout;
  String get _labelVide => _ar ? widget.labelVideAr : widget.labelVide;

  String _t(String fr, String ar) => _ar ? ar : fr;

  BackgroundCategory get _bgCategory {
    if (widget.types.contains(TypeVehicule.moto) ||
        widget.types.contains(TypeVehicule.scooter)) {
      return BackgroundCategory.moto;
    }
    return BackgroundCategory.voiture;
  }

  BackgroundCategory _bgCategoryFor(Vehicule v) {
    if (v.type == TypeVehicule.moto || v.type == TypeVehicule.scooter) {
      return BackgroundCategory.moto;
    }
    return BackgroundCategory.voiture;
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() => _vehicules = VehiculeService.getByTypes(widget.types));
  }

  IconData _iconForType(String type) {
    switch (type) {
      case TypeVehicule.moto:
        return Icons.two_wheeler;
      case TypeVehicule.scooter:
        return Icons.moped;
      default:
        return Icons.directions_car;
    }
  }

  String _labelForType(String type) {
    switch (type) {
      case TypeVehicule.moto:
        return _t('Moto', 'دراجة نارية');
      case TypeVehicule.scooter:
        return _t('Scooter', 'دراجة سكوتر');
      default:
        return _t('Voiture', 'سيارة');
    }
  }

  /// Remplace l'ancien formulaire texte (nom/marque saisis à la main) :
  /// on choisit le type puis on scanne la carte grise, qui crée
  /// directement la fiche véhicule avec les infos détectées.
  Future<void> _ajouterVehiculeViaScan() async {
    final isPremium = SettingsService.isPremium;
    final canAddFree = VehiculeService.canAddFreeForTypes(widget.types);
    if (!isPremium && !canAddFree) {
      _showPremiumSheet();
      return;
    }

    String selectedType = widget.types.first;

    if (widget.types.length > 1) {
      final chosen = await showDialog<String>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text(_t('Quel type de véhicule ?', 'ما نوع المركبة؟')),
            content: SegmentedButton<String>(
              segments: widget.types
                  .map((t) => ButtonSegment<String>(
                        value: t,
                        label: Text(_labelForType(t)),
                        icon: Icon(_iconForType(t)),
                      ))
                  .toList(),
              selected: {selectedType},
              onSelectionChanged: (s) =>
                  setDialogState(() => selectedType = s.first),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(_t('Annuler', 'إلغاء')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, selectedType),
                child: Text(_t('Continuer', 'متابعة')),
              ),
            ],
          ),
        ),
      );
      if (chosen == null) return;
      selectedType = chosen;
    }

    if (!mounted) return;
    // Parcours complet : carte grise (crée la fiche) -> assurance -> contrôle
    // technique, avec enchaînement automatique dès qu'une photo est scannée
    // avec succès, et un "Ajouter plus tard" pour passer l'étape sans photo.
    final cree = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AjouterVehiculeFlowScreen(
          config: widget.config,
          typeVehicule: selectedType,
          isAr: widget.isAr,
        ),
      ),
    );

    if (cree == true) _refresh();
  }

  /// Dialogue partagé pour l'ajout ET la modification d'un véhicule.
  /// Si [existing] est fourni, le formulaire est pré-rempli et on met à
  /// jour ce véhicule au lieu d'en créer un nouveau.
  Future<void> _openVehicleFormDialog({Vehicule? existing}) async {
    final isEdit = existing != null;

    if (!isEdit) {
      final isPremium = SettingsService.isPremium;
      final canAddFree = VehiculeService.canAddFreeForTypes(widget.types);
      if (!isPremium && !canAddFree) {
        _showPremiumSheet();
        return;
      }
    }

    final nomController = TextEditingController(text: existing?.nom ?? '');
    final marqueController =
        TextEditingController(text: existing?.marque ?? '');
    String selectedType = existing?.type ?? widget.types.first;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(isEdit
              ? _t('Modifier le véhicule', 'تعديل المركبة')
              : _labelAjout),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.types.length > 1) ...[
                SegmentedButton<String>(
                  segments: widget.types
                      .map((t) => ButtonSegment<String>(
                            value: t,
                            label: Text(_labelForType(t)),
                            icon: Icon(_iconForType(t)),
                          ))
                      .toList(),
                  selected: {selectedType},
                  onSelectionChanged: (s) =>
                      setDialogState(() => selectedType = s.first),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: nomController,
                decoration: InputDecoration(
                  labelText: _t('Nom', 'الاسم'),
                  hintText: widget.types.contains(TypeVehicule.voiture)
                      ? _t('ex: Peugeot 208', 'مثال: بيجو 208')
                      : _t('ex: Yamaha 125', 'مثال: ياماها 125'),
                ),
                autofocus: true,
                onChanged: (_) => setDialogState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: marqueController,
                decoration: InputDecoration(
                  labelText: _t('Marque / modèle (optionnel)',
                      'الماركة / الطراز (اختياري)'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(_t('Annuler', 'إلغاء')),
            ),
            FilledButton(
              onPressed: nomController.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: Text(
                  isEdit ? _t('Enregistrer', 'حفظ') : _t('Ajouter', 'إضافة')),
            ),
          ],
        ),
      ),
    );

    if (ok != true || nomController.text.trim().isEmpty) return;

    if (isEdit) {
      existing.nom = nomController.text.trim();
      existing.marque = marqueController.text.trim();
      existing.type = selectedType;
      await VehiculeService.update(existing);
    } else {
      final v = Vehicule(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        nom: nomController.text.trim(),
        marque: marqueController.text.trim(),
        type: selectedType,
      );
      await VehiculeService.add(v);
    }
    _refresh();
  }

  Future<void> _confirmDelete(Vehicule v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t('Supprimer ce véhicule ?', 'حذف هذه المركبة؟')),
        content: Text(
          _t(
            'Cette action est définitive. "${v.nom}" et toutes ses données '
            '(assurance, contrôle technique) seront supprimées.',
            'هذا الإجراء نهائي. سيتم حذف "${v.nom}" وجميع بياناته '
            '(التأمين، الفحص التقني).',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_t('Annuler', 'إلغاء')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t('Supprimer', 'حذف')),
          ),
        ],
      ),
    );

    if (ok != true) return;

    await VehiculeService.delete(v.id);
    _refresh();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(_t('"${v.nom}" a été supprimé.', 'تم حذف "${v.nom}".')),
        ),
      );
    }
  }

  void _showPremiumSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.workspace_premium,
                      color: widget.config.primaryColor, size: 28),
                  const SizedBox(width: 8),
                  Text(_t('Passe en Premium', 'الترقية إلى Premium'),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _t(
                  'La version gratuite permet de gérer 1 élément dans cette '
                  'rubrique. Passe en Premium pour en ajouter sans limite, '
                  'et pour activer les rappels par SMS et appel.',
                  'تسمح النسخة المجانية بإدارة عنصر واحد فقط في هذا القسم. '
                  'قم بالترقية إلى Premium لإضافة عناصر بلا حدود، وتفعيل '
                  'التذكيرات عبر الرسائل النصية والمكالمات.',
                ),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                    _t('Rappels par SMS / Appel', 'تذكيرات عبر SMS / مكالمة')),
                subtitle: Text(
                  _t(
                    'En plus des notifications sur le téléphone. '
                    'Bientôt disponible.',
                    'بالإضافة إلى إشعارات الهاتف. قريباً.',
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
                value: SettingsService.smsRemindersEnabled,
                onChanged: (val) async {
                  await SettingsService.setSmsRemindersEnabled(val);
                  setSheetState(() {});
                },
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: widget.config.primaryColor,
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                  },
                  child: Text(_t('Bientôt disponible', 'قريباً')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(IconData icon, String titre) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: widget.config.primaryColor, size: 20),
          const SizedBox(width: 8),
          Text(titre,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        ],
      ),
    );
  }

  Future<void> _openVehicle(Vehicule v) async {
    // Carte Grise Magic n'a de sens que pour identifier un moteur ->
    // affichée uniquement pour les voitures (pas motos/scooters).
    final showCarteGrise = v.type == TypeVehicule.voiture;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (routeContext) => Scaffold(
          appBar: AppBar(
            backgroundColor: widget.config.primaryColor,
            foregroundColor: Colors.white,
            title: Text(v.nom),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: _t('Retour', 'رجوع'),
              onPressed: () {
                if (Navigator.of(routeContext).canPop()) {
                  Navigator.of(routeContext).pop();
                }
              },
            ),
          ),
          // Une seule page, 3 sections dans l'ordre logique (identité du
          // véhicule d'abord, puis les deux documents à renouveler) —
          // plus d'onglets : chaque section reste accessible à tout
          // moment, sans parcours forcé, pour re-scanner plus tard
          // (ex: renouvellement de l'assurance l'année suivante).
          body: ScreenBackground(
            category: _bgCategoryFor(v),
            accentColor: widget.config.primaryColor,
            child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (showCarteGrise) ...[
                  _sectionHeader(Icons.badge, _t('Carte Grise', 'البطاقة الرمادية')),
                  CarteGriseScreen(
                    config: widget.config,
                    vehicule: v,
                    isAr: widget.isAr,
                    embedded: true,
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Divider(),
                  ),
                ],
                _sectionHeader(Icons.security, _t('Assurance', 'التأمين')),
                InsuranceScreen(
                  config: widget.config,
                  vehicule: v,
                  isAr: widget.isAr,
                  embedded: true,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Divider(),
                ),
                _sectionHeader(
                    Icons.fact_check, _t('Contrôle technique', 'الفحص التقني')),
                ControleTechniqueScreen(
                  config: widget.config,
                  vehicule: v,
                  isAr: widget.isAr,
                  embedded: true,
                ),
              ],
            ),
            ),
          ),
        ),
      ),
    );
    _refresh();
  }

  /// [prefix] ex: "Assurance" / "CT" → « Assurance 196j restants ».
  Widget _statusChip(DateTime? expiration, String labelVide, {String? prefix}) {
    if (expiration == null) {
      return Chip(
        label: Text(labelVide, style: const TextStyle(fontSize: 11)),
        visualDensity: VisualDensity.compact,
      );
    }
    final status = ExpiryStatus(expirationDate: expiration);
    Color bg;
    Color fg;
    switch (status.level) {
      case StatusLevel.ok:
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF166534);
        break;
      case StatusLevel.warning:
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFF92400E);
        break;
      case StatusLevel.expired:
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFF991B1B);
        break;
    }
    final p = (prefix != null && prefix.isNotEmpty) ? '$prefix ' : '';
    final text = status.isExpired
        ? _t('${p}expiré depuis ${status.daysRemaining.abs()}j',
            '$pمنتهي منذ ${status.daysRemaining.abs()} يوم')
        : _t('${p}${status.daysRemaining}j restants',
            '$pباقي ${status.daysRemaining} يوم');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style:
            TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  int get _alertCount {
    int n = 0;
    for (final v in _vehicules) {
      for (final d in [v.assuranceExpiration, v.controleTechniqueExpiration]) {
        if (d == null) continue;
        final s = ExpiryStatus(expirationDate: d);
        if (s.isExpired || s.daysRemaining <= 30) n++;
      }
    }
    return n;
  }

  Color _worstStatusColor(Vehicule v) {
    final statuses = <ExpiryStatus>[];
    if (v.assuranceExpiration != null) {
      statuses.add(ExpiryStatus(expirationDate: v.assuranceExpiration!));
    }
    if (v.controleTechniqueExpiration != null) {
      statuses.add(ExpiryStatus(expirationDate: v.controleTechniqueExpiration!));
    }
    if (statuses.any((s) => s.level == StatusLevel.expired)) {
      return const Color(0xFFEF4444);
    }
    if (statuses.any((s) => s.level == StatusLevel.warning)) {
      return const Color(0xFFF97316);
    }
    if (statuses.isEmpty) return Colors.grey.shade400;
    return widget.config.primaryColor;
  }

  Widget _buildHeroHeader() {
    final alerts = _alertCount;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            widget.config.primaryColor,
            widget.config.primaryColor.withOpacity(0.75),
            const Color(0xFF0F766E),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: widget.config.primaryColor.withOpacity(0.35),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(widget.iconePrincipale,
                    color: Colors.white, size: 26),
              ),
              const Spacer(),
              if (alerts > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.notifications_active,
                          color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        _t('$alerts alerte${alerts > 1 ? 's' : ''}',
                            '$alerts تنبيه'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 12),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  _titre,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              // + à droite du titre : ajoute un véhicule, ou Premium si limite.
              Material(
                color: Colors.white.withOpacity(0.22),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _ajouterVehiculeViaScan,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.add, color: Colors.white, size: 24),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _sousTitre,
            style: TextStyle(
              color: Colors.white.withOpacity(0.85),
              fontSize: 13.5,
            ),
          ),
          // Véhicules rassemblés dans le bandeau vert (plus de double
          // "1 véhicule / OK" + carte séparée en dessous).
          if (_vehicules.isNotEmpty) ...[
            const SizedBox(height: 14),
            ..._vehicules.map((v) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _buildVehicleCardInHero(v),
                )),
          ],
        ],
      ),
    );
  }

  /// Carte véhicule compacte, style clair, posée dans le bandeau vert.
  Widget _buildVehicleCardInHero(Vehicule v) {
    final accent = _worstStatusColor(v);
    final details = <String>[
      if (v.marque.isNotEmpty) v.marque,
      if (v.year != null) '${v.year}',
      if (v.immatriculation.isNotEmpty) v.immatriculation,
    ];
    final hasAssur = v.assuranceExpiration != null;
    final hasCt = v.controleTechniqueExpiration != null;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openVehicle(v),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withOpacity(0.35), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Bandeau couleur statut
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            widget.config.primaryColor.withOpacity(0.18),
                            widget.config.primaryColor.withOpacity(0.08),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(widget.iconePrincipale,
                          color: widget.config.primaryColor, size: 28),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            v.nom,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (details.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              details.join(' · '),
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          if (v.engineCode.isNotEmpty ||
                              v.fuelType.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              [
                                if (v.engineCode.isNotEmpty) v.engineCode,
                                if (v.fuelType.isNotEmpty) v.fuelType,
                              ].join(' · '),
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') {
                          _openVehicleFormDialog(existing: v);
                        } else if (value == 'delete') {
                          _confirmDelete(v);
                        }
                      },
                      itemBuilder: (ctx) => [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text(_t('Modifier', 'تعديل')),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(_t('Supprimer', 'حذف')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Chips statut
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _statusChip(
                      v.assuranceExpiration,
                      _t('Pas d\'assurance', 'لا يوجد تأمين'),
                      prefix: _t('Assurance', 'تأمين'),
                    ),
                    _statusChip(
                      v.controleTechniqueExpiration,
                      _t('Pas de CT', 'لا يوجد فحص تقني'),
                      prefix: _t('CT', 'فحص'),
                    ),
                  ],
                ),
              ),
              // Actions rapides
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _openVehicle(v),
                        icon: Icon(
                          hasAssur
                              ? Icons.verified_user_outlined
                              : Icons.document_scanner_outlined,
                          size: 16,
                        ),
                        label: Text(
                          hasAssur
                              ? _t('Voir assurance', 'عرض التأمين')
                              : _t('Scanner assurance', 'مسح التأمين'),
                          style: const TextStyle(fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF059669),
                          side: const BorderSide(color: Color(0xFFA7F3D0)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _openVehicle(v),
                        icon: Icon(
                          hasCt
                              ? Icons.fact_check_outlined
                              : Icons.document_scanner_outlined,
                          size: 16,
                        ),
                        label: Text(
                          hasCt
                              ? _t('Voir CT', 'عرض الفحص')
                              : _t('Scanner CT', 'مسح الفحص'),
                          style: const TextStyle(fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFD97706),
                          side: const BorderSide(color: Color(0xFFFDE68A)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statPill(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15)),
                  Text(label,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleCard(Vehicule v) {
    final accent = _worstStatusColor(v);
    // ValueKey unique par véhicule : évite le conflit de GlobalKey
    // "ink renderer" quand la liste se reconstruit (IndexedStack + Material).
    return Container(
      key: ValueKey('vehicule_card_${v.id}'),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => _openVehicle(v),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 6,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(22)),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    accent.withOpacity(0.15),
                                    accent.withOpacity(0.05),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(_iconForType(v.type),
                                  color: accent, size: 26),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    v.nom,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16.5,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                  if (v.marque.isNotEmpty ||
                                      v.year != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      [
                                        if (v.marque.isNotEmpty) v.marque,
                                        if (v.year != null) '${v.year}',
                                      ].join(' · '),
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'edit') {
                                  _openVehicleFormDialog(existing: v);
                                } else if (value == 'delete') {
                                  _confirmDelete(v);
                                }
                              },
                              itemBuilder: (ctx) => [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text(_t('Modifier', 'تعديل')),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(_t('Supprimer', 'حذف')),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            if (widget.types.length > 1)
                              _miniChip(
                                _labelForType(v.type),
                                widget.config.primaryColor.withOpacity(0.12),
                                widget.config.primaryColor,
                              ),
                            _statusChip(
                              v.assuranceExpiration,
                              _t('Pas d\'assurance', 'لا يوجد تأمين'),
                              prefix: _t('Assurance', 'تأمين'),
                            ),
                            _statusChip(
                              v.controleTechniqueExpiration,
                              _t('Pas de CT', 'لا يوجد فحص تقني'),
                              prefix: _t('CT', 'فحص'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Text(
                              _t('Voir le détail', 'عرض التفاصيل'),
                              style: TextStyle(
                                color: widget.config.primaryColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.arrow_forward_ios,
                                size: 12, color: widget.config.primaryColor),
                          ],
                        ),
                      ],
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

  Widget _miniChip(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _emptyFeature({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return Material(
      color: color.withOpacity(0.07),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.18)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(icon, size: 22, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: color.withOpacity(0.7)),
            ],
          ),
        ),
      ),
    );
  }

  /// État vide allégé : uniquement les 3 actions cliquables (plus de gros
  /// bloc « Aucun véhicule » / bouton central).
  /// Ouvre le parcours d'ajout en précisant l'intention (carte grise vs
  /// assurance/CT) pour que l'utilisateur ne soit pas surpris de voir
  /// d'abord le scanner carte grise.
  Future<void> _startFlowForAssuranceCt() async {
    // Sans véhicule, on doit d'abord créer la fiche via la carte grise.
    // On le dit clairement avant d'ouvrir le scan.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t('Assurance & CT', 'التأمين والفحص')),
        content: Text(
          _t(
            'Pour scanner l\'assurance ou le contrôle technique, il faut d\'abord créer le véhicule avec la carte grise.\n\n'
            'On commence par la carte grise, puis tu pourras enchaîner sur l\'assurance et le CT.',
            'لمسح التأمين أو الفحص التقني، يجب أولاً إنشاء المركبة عبر البطاقة الرمادية.\n\n'
            'نبدأ بالبطاقة الرمادية، ثم يمكنك متابعة التأمين والفحص.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_t('Annuler', 'إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t('Commencer', 'ابدأ')),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await _ajouterVehiculeViaScan();
    }
  }

  Widget _buildEmptyState() {
    final primary = widget.config.primaryColor;
    return Column(
      children: [
        _emptyFeature(
          icon: Icons.document_scanner_rounded,
          color: primary,
          title: _t('Carte grise', 'البطاقة الرمادية'),
          subtitle: _t(
            'Marque, modèle, année, châssis — en quelques secondes',
            'الماركة والموديل والسنة والهيكل — في ثوانٍ',
          ),
          onTap: _ajouterVehiculeViaScan,
        ),
        _emptyFeature(
          icon: Icons.shield_outlined,
          color: const Color(0xFF10B981),
          title: _t('Assurance & CT', 'التأمين والفحص'),
          subtitle: _t(
            'D\'abord la carte grise, puis scan assurance & CT (dates dedans)',
            'أولاً البطاقة الرمادية، ثم مسح التأمين والفحص (التواريخ فيها)',
          ),
          onTap: _startFlowForAssuranceCt,
        ),
        _emptyFeature(
          icon: Icons.notifications_active_outlined,
          color: const Color(0xFFF59E0B),
          title: _t('Rappels automatiques', 'تذكيرات تلقائية'),
          subtitle: _t(
            'Jours restants, alertes J-30 / J-15 / J-7 — sans amende',
            'الأيام المتبقية، تنبيهات قبل 30 و15 و7 أيام — بلا غرامة',
          ),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => RappelsScreen(
                  config: widget.config,
                  isAr: widget.isAr,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildLockedCard() {
    return Container(
      key: const ValueKey('vehicule_locked_card'),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [
            widget.config.primaryColor.withOpacity(0.08),
            const Color(0xFFFEF3C7).withOpacity(0.6),
          ],
        ),
        border: Border.all(color: widget.config.primaryColor.withOpacity(0.25)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: _showPremiumSheet,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.lock_outline,
                      color: widget.config.primaryColor),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t('Ajouter un autre véhicule', 'إضافة مركبة أخرى'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _t('Passe en Premium pour continuer',
                            'قم بالترقية إلى Premium للمتابعة'),
                        style: TextStyle(
                            color: Colors.grey.shade700, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.workspace_premium,
                    color: const Color(0xFFF59E0B), size: 26),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScreenBackground(
      category: _bgCategory,
      accentColor: widget.config.primaryColor,
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            children: [
              // Titre + bouton + + véhicules dans le bandeau vert.
              // Le + (à droite de « Mes véhicules ») gère aussi le passage Premium.
              _buildHeroHeader(),
              const SizedBox(height: 12),
              const AdBanner(),
              if (_vehicules.isEmpty) ...[
                const SizedBox(height: 10),
                _buildEmptyState(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
