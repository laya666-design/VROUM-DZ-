import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../services/vehicule.dart';
import '../services/vehicule_service.dart';
import '../theme/app_theme.dart';

/// Une échéance concrète (assurance ou CT) pour un véhicule donné, calculée
/// à partir des dates renseignées via le scan carte grise/assurance/CT.
class _Echeance {
  final Vehicule vehicule;
  final bool estAssurance; // true = assurance, false = contrôle technique
  final DateTime date;

  _Echeance({required this.vehicule, required this.estAssurance, required this.date});

  int joursRestants(DateTime aujourdHui) => date.difference(aujourdHui).inDays;
}

/// Écran Rappels partagé (Conducteur / Magasin / Dépanneuse).
/// Affiche les vraies échéances (assurance, contrôle technique) calculées
/// à partir des dates enregistrées sur chaque véhicule : jours restants,
/// couleur selon l'urgence (rouge = expiré, orange = J-30, vert = ok),
/// triées de la plus urgente à la moins urgente. Un tap ouvre le véhicule.
class RappelsScreen extends StatelessWidget {
  final AppConfig config;
  final bool isAr;
  final String roleLabel;
  final void Function(Vehicule vehicule)? onOpenVehicle;

  const RappelsScreen({
    super.key,
    required this.config,
    this.isAr = false,
    this.roleLabel = 'compte',
    this.onOpenVehicle,
  });

  String _t(String fr, String ar) => isAr ? ar : fr;

  List<_Echeance> _buildEcheances(List<Vehicule> vehicules) {
    final echeances = <_Echeance>[];
    for (final v in vehicules) {
      if (v.assuranceExpiration != null) {
        echeances.add(_Echeance(vehicule: v, estAssurance: true, date: v.assuranceExpiration!));
      }
      if (v.controleTechniqueExpiration != null) {
        echeances.add(_Echeance(vehicule: v, estAssurance: false, date: v.controleTechniqueExpiration!));
      }
    }
    echeances.sort((a, b) => a.date.compareTo(b.date));
    return echeances;
  }

  // Véhicules sans aucune date renseignée (ni assurance ni CT) : rien à
  // afficher en échéance, mais on les signale quand même pour inciter au
  // scan plutôt que de les faire disparaître silencieusement.
  List<Vehicule> _vehiculesSansDate(List<Vehicule> vehicules) {
    return vehicules
        .where((v) => v.assuranceExpiration == null && v.controleTechniqueExpiration == null)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final vehicules = VehiculeService.getAll();
    final aujourdHui = DateTime.now();
    final today = DateTime(aujourdHui.year, aujourdHui.month, aujourdHui.day);
    final echeances = _buildEcheances(vehicules);
    final sansDate = _vehiculesSansDate(vehicules);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_t('Rappels', 'تذكيرات')),
        automaticallyImplyLeading: true,
      ),
      body: vehicules.isEmpty
          ? _EmptyRappels(isAr: isAr, roleLabel: roleLabel, primary: config.primaryColor)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                if (echeances.isEmpty && sansDate.isNotEmpty)
                  _NoDateNotice(isAr: isAr, primary: config.primaryColor)
                else ...[
                  for (final e in echeances) ...[
                    _EcheanceCard(
                      echeance: e,
                      today: today,
                      isAr: isAr,
                      onTap: onOpenVehicle == null ? null : () => onOpenVehicle!(e.vehicule),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (sansDate.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _t('Sans date renseignée', 'بدون تاريخ مسجل'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final v in sansDate) ...[
                      _VehiculeSansDateCard(
                        vehicule: v,
                        isAr: isAr,
                        primary: config.primaryColor,
                        onTap: onOpenVehicle == null ? null : () => onOpenVehicle!(v),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ],
              ],
            ),
    );
  }
}

class _EcheanceCard extends StatelessWidget {
  final _Echeance echeance;
  final DateTime today;
  final bool isAr;
  final VoidCallback? onTap;

  const _EcheanceCard({
    required this.echeance,
    required this.today,
    required this.isAr,
    this.onTap,
  });

  String _t(String fr, String ar) => isAr ? ar : fr;

  @override
  Widget build(BuildContext context) {
    final jours = echeance.joursRestants(today);
    final expire = jours < 0;
    final urgent = !expire && jours <= 30;

    final Color couleur = expire
        ? AppColors.error
        : urgent
            ? AppColors.warning
            : AppColors.success;
    final Color fond = expire
        ? AppColors.errorBg
        : urgent
            ? AppColors.warningBg
            : AppColors.successBg;

    final v = echeance.vehicule;
    final nomVehicule = v.nom.isNotEmpty ? v.nom : (v.marque.isNotEmpty ? v.marque : v.immatriculation);
    final typeLabel = echeance.estAssurance
        ? _t('Assurance', 'التأمين')
        : _t('Contrôle technique', 'المراقبة التقنية');

    final String statut;
    if (expire) {
      final joursDepasses = -jours;
      statut = _t(
        'Expirée depuis $joursDepasses j',
        'منتهية منذ $joursDepasses يوم',
      );
    } else if (jours == 0) {
      statut = _t('Expire aujourd\'hui', 'تنتهي اليوم');
    } else {
      statut = _t('Dans $jours j', 'خلال $jours يوم');
    }

    final dateStr =
        '${echeance.date.day.toString().padLeft(2, '0')}/${echeance.date.month.toString().padLeft(2, '0')}/${echeance.date.year}';

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: fond,
                child: Icon(
                  echeance.estAssurance ? Icons.shield_outlined : Icons.build_outlined,
                  color: couleur,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$typeLabel · $nomVehicule',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: fond,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            statut,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: couleur,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          dateStr,
                          style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _VehiculeSansDateCard extends StatelessWidget {
  final Vehicule vehicule;
  final bool isAr;
  final Color primary;
  final VoidCallback? onTap;

  const _VehiculeSansDateCard({
    required this.vehicule,
    required this.isAr,
    required this.primary,
    this.onTap,
  });

  String _t(String fr, String ar) => isAr ? ar : fr;

  @override
  Widget build(BuildContext context) {
    final nomVehicule = vehicule.nom.isNotEmpty
        ? vehicule.nom
        : (vehicule.marque.isNotEmpty ? vehicule.marque : vehicule.immatriculation);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: primary.withValues(alpha: 0.12),
                child: Icon(
                  vehicule.type == 'moto' || vehicule.type == 'scooter'
                      ? Icons.two_wheeler
                      : Icons.directions_car,
                  color: primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nomVehicule, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                    const SizedBox(height: 3),
                    Text(
                      _t(
                        'Scanne l\'assurance ou le CT pour activer les rappels',
                        'امسح التأمين أو الفحص لتفعيل التذكيرات',
                      ),
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoDateNotice extends StatelessWidget {
  final bool isAr;
  final Color primary;

  const _NoDateNotice({required this.isAr, required this.primary});

  String _t(String fr, String ar) => isAr ? ar : fr;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 48),
        child: Column(
          children: [
            Icon(Icons.event_available_outlined, size: 56, color: primary.withValues(alpha: 0.5)),
            const SizedBox(height: 14),
            Text(
              _t('Aucune date renseignée pour le moment', 'لا يوجد أي تاريخ مسجل حالياً'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              _t(
                'Scanne l\'assurance ou le contrôle technique d\'un véhicule pour voir ses échéances ici.',
                'امسح التأمين أو الفحص التقني لمركبة لرؤية مواعيدها هنا.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyRappels extends StatelessWidget {
  final bool isAr;
  final String roleLabel;
  final Color primary;

  const _EmptyRappels({
    required this.isAr,
    required this.roleLabel,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    final t = (String fr, String ar) => isAr ? ar : fr;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none_rounded, size: 64, color: primary.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              t('Aucun rappel pour le moment', 'لا توجد تذكيرات حالياً'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              t(
                'Les rappels (assurance, contrôle technique, abonnement…) apparaîtront ici pour ton $roleLabel.',
                'ستظهر التذكيرات (التأمين، المراقبة التقنية، الاشتراك…) هنا لحسابك.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
