import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../services/ocr_service.dart';
import '../services/vehicule.dart';
import '../services/vehicule_service.dart';
import '../widgets/ad_banner.dart';
import 'controle_technique_screen.dart';
import 'insurance_screen.dart';

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
    this.sousTitre =
        'Assurance, vignette et contrôle technique, par véhicule.',
    this.sousTitreAr = 'التأمين والرخصة والفحص التقني، لكل سيارة.',
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

  Future<void> _openVehicle(Vehicule v) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              backgroundColor: widget.config.primaryColor,
              foregroundColor: Colors.white,
              title: Text(v.nom),
              bottom: TabBar(
                indicatorColor: Colors.white,
                tabs: [
                  Tab(
                      icon: const Icon(Icons.security),
                      text: _t('Assurance', 'التأمين')),
                  Tab(
                      icon: const Icon(Icons.fact_check),
                      text: _t('Contrôle technique', 'الفحص التقني')),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                InsuranceScreen(config: widget.config, vehicule: v),
                ControleTechniqueScreen(config: widget.config, vehicule: v),
              ],
            ),
          ),
        ),
      ),
    );
    _refresh();
  }

  Widget _statusChip(DateTime? expiration, String labelVide) {
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.isExpired
            ? _t('Expiré depuis ${status.daysRemaining.abs()}j',
                'منتهي منذ ${status.daysRemaining.abs()} يوم')
            : _t('${status.daysRemaining}j restants',
                'باقي ${status.daysRemaining} يوم'),
        style:
            TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = SettingsService.isPremium;
    final showLockedCard =
        !isPremium && _vehicules.length >= VehiculeService.freeLimit;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(_titre, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(_sousTitre, style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 12),
            const AdBanner(),
            const SizedBox(height: 4),
            if (_vehicules.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(widget.iconePrincipale,
                          size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      Text(_labelVide,
                          style: const TextStyle(color: Colors.black54)),
                    ],
                  ),
                ),
              ),
            ..._vehicules.map((v) => Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.only(
                        left: 12, top: 12, bottom: 12, right: 4),
                    leading: CircleAvatar(
                      backgroundColor:
                          widget.config.primaryColor.withOpacity(0.1),
                      foregroundColor: widget.config.primaryColor,
                      child: Icon(_iconForType(v.type)),
                    ),
                    title: Text(v.nom,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          if (widget.types.length > 1)
                            Chip(
                              label: Text(_labelForType(v.type),
                                  style: const TextStyle(fontSize: 11)),
                              visualDensity: VisualDensity.compact,
                              backgroundColor:
                                  widget.config.primaryColor.withOpacity(0.08),
                            ),
                          _statusChip(
                              v.assuranceExpiration,
                              _t('Assurance non renseignée',
                                  'التأمين غير محدد')),
                          _statusChip(
                              v.controleTechniqueExpiration,
                              _t('CT non renseigné',
                                  'الفحص التقني غير محدد')),
                        ],
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: _t('Modifier', 'تعديل'),
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          onPressed: () =>
                              _openVehicleFormDialog(existing: v),
                        ),
                        IconButton(
                          tooltip: _t('Supprimer', 'حذف'),
                          icon: const Icon(Icons.delete_outline,
                              size: 20, color: Colors.red),
                          onPressed: () => _confirmDelete(v),
                        ),
                        const Icon(Icons.chevron_right, color: Colors.black38),
                      ],
                    ),
                    onTap: () => _openVehicle(v),
                  ),
                )),
            if (showLockedCard)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                color: Colors.grey.shade100,
                child: ListTile(
                  contentPadding: const EdgeInsets.all(12),
                  leading:
                      const Icon(Icons.lock_outline, color: Colors.black45),
                  title: Text(_t('Élément suivant', 'العنصر التالي'),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(_t(
                      'Réservé aux comptes Premium', 'حصري لحسابات Premium')),
                  trailing: Chip(
                    label: const Text('Premium',
                        style: TextStyle(fontSize: 11, color: Colors.white)),
                    backgroundColor: widget.config.primaryColor,
                  ),
                  onTap: _showPremiumSheet,
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _openVehicleFormDialog(),
                  icon: const Icon(Icons.add),
                  label: Text(_labelAjout),
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
