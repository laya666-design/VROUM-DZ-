import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../services/vehicule_service.dart';
import '../theme/app_theme.dart';

/// Écran Rappels partagé (Conducteur / Magasin / Dépanneuse).
/// Affiche les prochains rappels locaux (assurance, CT, etc.) quand des
/// véhicules sont enregistrés ; sinon un message adapté au rôle.
class RappelsScreen extends StatelessWidget {
  final AppConfig config;
  final bool isAr;
  final String roleLabel;

  const RappelsScreen({
    super.key,
    required this.config,
    this.isAr = false,
    this.roleLabel = 'compte',
  });

  String _t(String fr, String ar) => isAr ? ar : fr;

  @override
  Widget build(BuildContext context) {
    final vehicules = VehiculeService.getAll();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_t('Rappels', 'تذكيرات')),
        // Retour visible quand on arrive depuis Véhicules (état vide).
        automaticallyImplyLeading: true,
      ),
      body: vehicules.isEmpty
          ? _EmptyRappels(
              isAr: isAr,
              roleLabel: roleLabel,
              primary: config.primaryColor,
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: vehicules.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final v = vehicules[i];
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: config.primaryColor.withValues(alpha: 0.15),
                      child: Icon(
                        v.type == 'moto' || v.type == 'scooter'
                            ? Icons.two_wheeler
                            : Icons.directions_car,
                        color: config.primaryDark,
                      ),
                    ),
                    title: Text(
                      v.nom.isNotEmpty ? v.nom : (v.marque.isNotEmpty ? v.marque : v.immatriculation),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      _t(
                        'Voir les échéances dans le détail du véhicule',
                        'راجع المواعيد في تفاصيل المركبة',
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                );
              },
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
