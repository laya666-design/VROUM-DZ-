import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';

/// Annuaire des numéros d'urgence nationaux (Algérie).
/// Accessible depuis l'onglet Profil.
class EmergencyNumbersScreen extends StatelessWidget {
  final AppConfig config;
  final bool isAr;

  const EmergencyNumbersScreen({
    super.key,
    required this.config,
    this.isAr = false,
  });

  String _t(String fr, String ar) => isAr ? ar : fr;

  Future<void> _call(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = <_EmergencyGroup>[
      _EmergencyGroup(
        titleFr: 'Secours & secours médicaux',
        titleAr: 'الإنقاذ والإسعاف الطبي',
        color: const Color(0xFFEF4444),
        items: [
          _EmergencyItem(
            nameFr: 'Protection civile (pompiers)',
            nameAr: 'الحماية المدنية (الإطفاء)',
            number: '14',
            subtitleFr: 'Accidents, incendies, secours — gratuit',
            subtitleAr: 'حوادث، حرائق، إنقاذ — مجاني',
            icon: Icons.local_fire_department_rounded,
          ),
          _EmergencyItem(
            nameFr: 'Protection civile',
            nameAr: 'الحماية المدنية',
            number: '1021',
            subtitleFr: 'Numéro vert national',
            subtitleAr: 'الرقم الأخضر الوطني',
            icon: Icons.health_and_safety_rounded,
          ),
          _EmergencyItem(
            nameFr: 'SAMU',
            nameAr: 'سامو (الإسعاف الطبي)',
            number: '16',
            subtitleFr: 'Urgences médicales',
            subtitleAr: 'الطوارئ الطبية',
            icon: Icons.medical_services_rounded,
          ),
        ],
      ),
      _EmergencyGroup(
        titleFr: 'Police & gendarmerie',
        titleAr: 'الشرطة والدرك',
        color: const Color(0xFF3B82F6),
        items: [
          _EmergencyItem(
            nameFr: 'Police secours',
            nameAr: 'شرطة النجدة',
            number: '17',
            subtitleFr: 'Urgences police',
            subtitleAr: 'طوارئ الشرطة',
            icon: Icons.local_police_rounded,
          ),
          _EmergencyItem(
            nameFr: 'Sûreté nationale',
            nameAr: 'الأمن الوطني',
            number: '1548',
            subtitleFr: 'Centre opérationnel',
            subtitleAr: 'المركز العملياتي',
            icon: Icons.security_rounded,
          ),
          _EmergencyItem(
            nameFr: 'Gendarmerie nationale',
            nameAr: 'الدرك الوطني',
            number: '1055',
            subtitleFr: 'Zones rurales / routes — gratuit',
            subtitleAr: 'المناطق الريفية / الطرق — مجاني',
            icon: Icons.shield_rounded,
          ),
        ],
      ),
      _EmergencyGroup(
        titleFr: 'Autres numéros utiles',
        titleAr: 'أرقام مفيدة أخرى',
        color: const Color(0xFF22C55E),
        items: [
          _EmergencyItem(
            nameFr: 'Feux de forêt',
            nameAr: 'حرائق الغابات',
            number: '1070',
            subtitleFr: 'Direction générale des forêts',
            subtitleAr: 'المديرية العامة للغابات',
            icon: Icons.forest_rounded,
          ),
          _EmergencyItem(
            nameFr: 'Garde-côtes',
            nameAr: 'خفر السواحل',
            number: '1054',
            subtitleFr: 'Urgences en mer',
            subtitleAr: 'طوارئ بحرية',
            icon: Icons.sailing_rounded,
          ),
          _EmergencyItem(
            nameFr: 'Protection de l\'enfance',
            nameAr: 'حماية الطفولة',
            number: '1111',
            subtitleFr: 'Ligne d\'écoute enfants',
            subtitleAr: 'خط الاستماع للأطفال',
            icon: Icons.child_care_rounded,
          ),
        ],
      ),
    ];

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: config.primaryColor,
          foregroundColor: Colors.white,
          title: Text(_t('Numéros d\'urgence', 'أرقام الطوارئ')),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: _t('Retour', 'رجوع'),
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline,
                      color: Color(0xFFEF4444), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _t(
                        'Appels gratuits depuis mobile et fixe, même sans crédit. '
                        'En cas d\'accident sur la route, tu peux aussi utiliser le bouton SOS de l\'app pour alerter les dépanneuses de ta wilaya.',
                        'مكالمات مجانية من الجوال والثابت، حتى بدون رصيد. '
                        'في حالة حادث على الطريق، يمكنك أيضاً استخدام زر SOS في التطبيق لتنبيه سطحات ولايتك.',
                      ),
                      style: const TextStyle(
                          fontSize: 13, height: 1.35, color: Color(0xFF7F1D1D)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            for (final group in groups) ...[
              Text(
                _t(group.titleFr, group.titleAr),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: group.color,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < group.items.length; i++) ...[
                      if (i > 0)
                        Divider(height: 1, color: Colors.grey.shade200),
                      _NumberTile(
                        item: group.items[i],
                        accent: group.color,
                        isAr: isAr,
                        onCall: () => _call(group.items[i].number),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmergencyGroup {
  final String titleFr;
  final String titleAr;
  final Color color;
  final List<_EmergencyItem> items;
  const _EmergencyGroup({
    required this.titleFr,
    required this.titleAr,
    required this.color,
    required this.items,
  });
}

class _EmergencyItem {
  final String nameFr;
  final String nameAr;
  final String number;
  final String subtitleFr;
  final String subtitleAr;
  final IconData icon;
  const _EmergencyItem({
    required this.nameFr,
    required this.nameAr,
    required this.number,
    required this.subtitleFr,
    required this.subtitleAr,
    required this.icon,
  });
}

class _NumberTile extends StatelessWidget {
  final _EmergencyItem item;
  final Color accent;
  final bool isAr;
  final VoidCallback onCall;

  const _NumberTile({
    required this.item,
    required this.accent,
    required this.isAr,
    required this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    final name = isAr ? item.nameAr : item.nameFr;
    final sub = isAr ? item.subtitleAr : item.subtitleFr;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onCall,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(item.icon, color: accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.phone, color: Colors.white, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      item.number,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        letterSpacing: 0.5,
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
}
